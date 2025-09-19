import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../shared/rules_service.dart';
import '../main.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});
  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> with RouteAware {
  int _scopeIndex = 0; // 0 Skills, 1 Status, 2 Races
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  // Filters
  String _type = 'All'; // All | Common | Race | Affinity
  String _race = 'Any';
  String _affinity = 'Any';
  String _frequency = 'Any';

  // Options
  final List<String> _types = const ['All', 'Common', 'Race', 'Affinity'];
  List<String> _races = ['Any'];
  List<String> _affinities = ['Any'];
  List<String> _frequencies = ['Any'];

  // Favorites
  final String _boxName = 'rulesCache';
  final String _favoritesKey = 'favorites';
  Set<String> _favoriteIds = <String>{};

  @override
  void initState() {
    super.initState();
    _refreshIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Auto-refresh when returning to this page
  @override
  void didPopNext() {
    _refreshIfNeeded();
  }

  Future<void> _refreshIfNeeded() async {
    setState(() { _loading = true; });
    try {
      await RulesService.fetchAndCacheRules();
      await _loadIndexes();
      await _loadFavorites();
      await _search('');
    } catch (_) {}
    if (mounted) setState(() { _loading = false; });
  }

  Future<void> _loadFavorites() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);
    final List<dynamic>? saved = box.get(_favoritesKey)?.cast<dynamic>();
    _favoriteIds = saved == null
        ? <String>{}
        : saved.map((e) => e.toString()).toSet();
  }

  Future<void> _persistFavorites() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);
    await box.put(_favoritesKey, _favoriteIds.toList());
  }

  String _ruleId(Map<String, dynamic> r) {
    final name = (r['Name'] ?? '').toString();
    final section = (r['section'] ?? '').toString();
    final race = (r['Race'] ?? '').toString();
    final affinity = (r['Affinity'] ?? '').toString();
    return [section, name, race, affinity].where((s) => s.isNotEmpty).join('|');
  }

  void _toggleFavorite(Map<String, dynamic> r) async {
    final id = _ruleId(r);
    setState(() {
      if (_favoriteIds.contains(id)) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
    await _persistFavorites();
  }

  Future<void> _copyToClipboard(String text, {String label = 'Copied'}) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  Future<void> _loadIndexes() async {
    final cached = await RulesService.loadCachedRules();
    if (cached == null) return;
    final rules = json.decode(cached);

    // Races
    final Set<String> races = {'Any'};
    for (final r in (rules['Races'] as List? ?? const [])) {
      if (r is Map<String, dynamic>) {
        final n = (r['Name'] ?? '').toString();
        if (n.isNotEmpty) races.add(n);
      }
    }

    // Affinities
    final Set<String> affinities = {'Any'};
    for (final s in (rules['Affinity Skills'] as List? ?? const [])) {
      if (s is Map<String, dynamic>) {
        final a = (s['Affinity'] ?? '').toString();
        if (a.isNotEmpty) affinities.add(a);
      }
    }

    // Enumerations (derive from skills if dedicated sections not present)
    final Set<String> freqs = {'Any'};
    void collectFrom(List list) {
      for (final s in list) {
        if (s is Map<String, dynamic>) {
          final f = (s['Frequency'] ?? '').toString();
          if (f.isNotEmpty) freqs.add(f);
        }
      }
    }
    collectFrom(rules['Common Skills'] as List? ?? const []);
    collectFrom(rules['Affinity Skills'] as List? ?? const []);
    for (final r in (rules['Races'] as List? ?? const [])) {
      if (r is Map<String, dynamic>) {
        collectFrom(r['Race Skills'] as List? ?? const []);
      }
    }

    setState(() {
      _races = races.toList()..sort();
      _affinities = affinities.toList()..sort();
      _frequencies = freqs.toList()..sort();
    });
  }

  Future<void> _search(String q) async {
    _query = q;
    final cached = await RulesService.loadCachedRules();
    if (cached == null) return;
    final rules = json.decode(cached);

    final List<Map<String, dynamic>> hits = [];

    void scanList(String section, List<dynamic> list, {String? parentRace, String? parentAffinity}) {
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final name = (item['Name'] ?? '').toString();
          final desc = (item['Description'] ?? '').toString();
          if (q.isEmpty || name.toLowerCase().contains(q.toLowerCase()) || desc.toLowerCase().contains(q.toLowerCase())) {
            final enriched = { 'section': section, ...item };
            if (parentRace != null) enriched['Race'] = parentRace;
            if (parentAffinity != null) enriched['Affinity'] = parentAffinity;
            hits.add(enriched);
          }
        }
      }
    }

    if (_scopeIndex == 0) {
      // Skills scope
      scanList('Common Skills', (rules['Common Skills'] as List?) ?? []);
      // Affinity Skills
      scanList('Affinity Skills', (rules['Affinity Skills'] as List?) ?? [], parentAffinity: null);
      // Race skills can be available both globally and embedded per race; include both
      scanList('Race Skills', (rules['Race Skills'] as List?) ?? []);
      final races = (rules['Races'] as List?) ?? [];
      for (final r in races.whereType<Map<String, dynamic>>()) {
        final raceSkills = (r['Race Skills'] as List?) ?? [];
        final raceName = (r['Name'] ?? '').toString();
        scanList('Race Skills', raceSkills, parentRace: raceName);
      }
    } else if (_scopeIndex == 1) {
      // Status Effects scope
      for (final item in (rules['Status Effects'] as List?) ?? []) {
        if (item is Map<String, dynamic>) {
          final name = (item['Name'] ?? '').toString();
          final desc = item.entries
              .where((e) => e.key != 'Name')
              .map((e) => '${e.key}: ${e.value}')
              .join('  •  ');
          if (q.isEmpty || name.toLowerCase().contains(q.toLowerCase()) || desc.toLowerCase().contains(q.toLowerCase())) {
            hits.add({ 'section': 'Status Effects', ...item });
          }
        }
      }
    } else if (_scopeIndex == 2) {
      // Races scope
      final races = (rules['Races'] as List?) ?? [];
      for (final r in races.whereType<Map<String, dynamic>>()) {
        final name = (r['Name'] ?? '').toString();
        final summary = (r['Description'] ?? '').toString();
        if (q.isEmpty || name.toLowerCase().contains(q.toLowerCase()) || summary.toLowerCase().contains(q.toLowerCase())) {
          hits.add({ 'section': 'Races', ...r });
        }
      }
    }

    // Apply filters
    bool matchesFilters(Map<String, dynamic> s) {
      final section = (s['section'] ?? '').toString();
      final freq = (s['Frequency'] ?? '').toString();
      final race = (s['Race'] ?? '').toString();
      final affinity = (s['Affinity'] ?? '').toString();

      // Filters only apply in Skills scope
      if (_scopeIndex != 0) return true;

      // Type filter
      if (_type == 'Common' && section != 'Common Skills') return false;
      if (_type == 'Race' && section != 'Race Skills') return false;
      if (_type == 'Affinity' && section != 'Affinity Skills') return false;

      if (_race != 'Any' && race != _race) return false;
      if (_affinity != 'Any' && affinity != _affinity) return false;
      if (_frequency != 'Any' && freq != _frequency) return false;

      return true;
    }

    final filtered = hits.where(matchesFilters).take(200).toList();

    setState(() { _results = filtered; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rules'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Skills'), icon: Icon(Icons.menu_book)),
                ButtonSegment(value: 1, label: Text('Status'), icon: Icon(Icons.healing)),
                ButtonSegment(value: 2, label: Text('Races'), icon: Icon(Icons.groups)),
              ],
              selected: {_scopeIndex},
              onSelectionChanged: (s) {
                setState(() {
                  _scopeIndex = s.first;
                  if (_scopeIndex != 0) {
                    _type = 'All';
                    _race = 'Any';
                    _affinity = 'Any';
                    _frequency = 'Any';
                  }
                });
                _search(_query);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search rules…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => _search(v),
            ),
          ),
          if (_scopeIndex == 0) _buildFilters(),
          if (_loading) LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final name = (r['Name'] ?? r['Race'] ?? r['name'] ?? r['id'] ?? '').toString();
                final section = (r['section'] ?? '').toString();
                final desc = _scopeIndex == 1
                    ? r.entries.where((e) => e.key != 'Name').map((e) => '${e.key}: ${e.value}').join('  •  ')
                    : (r['Description'] ?? '').toString();
                final verbal = (r['Verbal'] ?? '').toString();
                final id = _ruleId(r);
                final isFav = _favoriteIds.contains(id);
                // Improve label for skills: show specific Affinity or Race instead of generic section
                String label = section;
                if (_scopeIndex == 0) {
                  if (section == 'Affinity Skills') {
                    label = (r['Affinity'] ?? '').toString().isNotEmpty
                        ? (r['Affinity'] ?? '').toString()
                        : 'Affinity';
                  } else if (section == 'Race Skills') {
                    label = (r['Race'] ?? '').toString().isNotEmpty
                        ? (r['Race'] ?? '').toString()
                        : 'Race';
                  } else if (section == 'Common Skills') {
                    label = 'Common';
                  }
                }
                return ListTile(
                  title: Text(name),
                  subtitle: Text(
                    _scopeIndex == 0
                        ? (label.isEmpty ? desc : '[$label]  $desc')
                        : (desc.isEmpty ? 'Tap to view' : desc),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Copy rules',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copyToClipboard(desc, label: 'Rules copied'),
                      ),
                      if (verbal.isNotEmpty)
                        IconButton(
                          tooltip: 'Copy verbal',
                          icon: const Icon(Icons.record_voice_over, size: 18),
                          onPressed: () => _copyToClipboard(verbal, label: 'Verbal copied'),
                        ),
                      IconButton(
                        tooltip: isFav ? 'Unfavorite' : 'Favorite',
                        icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : null, size: 20),
                        onPressed: () => _toggleFavorite(r),
                      ),
                    ],
                  ),
                  onTap: () {
                    // Defer modal opening to the next frame to avoid web mouse tracker assert
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      showModalBottomSheet(context: context, builder: (_) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: Theme.of(context).textTheme.titleLarge),
                              if (_scopeIndex == 0) ...[
                                if (verbal.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text('Verbal: $verbal'),
                                ],
                                const SizedBox(height: 12),
                                if (((r['Description'] ?? r['Desc'] ?? '').toString()).isNotEmpty)
                                  Text((r['Description'] ?? r['Desc'] ?? '').toString())
                                else ...[
                                  // Fallback: print key details if description missing (common in some race skills)
                                  ...r.entries
                                      .where((e) => e.key != 'Name')
                                      .map((e) => Padding(
                                            padding: const EdgeInsets.only(bottom: 6.0),
                                            child: Text('${e.key}: ${e.value}'),
                                          )),
                                ],
                              ] else if (_scopeIndex == 1) ...[
                                const SizedBox(height: 12),
                                ...r.entries.where((e) => e.key != 'Name').map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text('${e.key}: ${e.value}'),
                                )),
                              ] else ...[
                                const SizedBox(height: 12),
                                if ((r['Description'] ?? '').toString().isNotEmpty) ...[
                                  Text('Description', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text((r['Description'] ?? '').toString()),
                                  const SizedBox(height: 12),
                                ],
                                if ((r['Costume Requirements'] ?? '').toString().isNotEmpty) ...[
                                  Text('Costume Requirements', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text((r['Costume Requirements'] ?? '').toString()),
                                  const SizedBox(height: 12),
                                ],
                                if ((r['Notes'] ?? '').toString().isNotEmpty) ...[
                                  Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text((r['Notes'] ?? '').toString()),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ],
                          ),
                        ),
                        );
                      });
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _dd('Type', _type, _types, (v) => setState(() { _type = v; _search(_query); })),
          _dd('Race', _race, _races, (v) => setState(() { _race = v; _search(_query); })),
          _dd('Affinity', _affinity, _affinities, (v) => setState(() { _affinity = v; _search(_query); })),
          _dd('Frequency', _frequency, _frequencies, (v) => setState(() { _frequency = v; _search(_query); })),
        ],
      ),
    );
  }

  Widget _dd(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: DropdownButton<String>(
        value: options.contains(value) ? value : options.first,
        underline: SizedBox.shrink(),
        items: options.map((e) => DropdownMenuItem<String>(value: e, child: Text('$label: $e'))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}


