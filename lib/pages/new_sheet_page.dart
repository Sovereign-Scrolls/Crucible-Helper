import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../shared/character_cache_service.dart';

class NewSheetPage extends StatefulWidget {
  const NewSheetPage({super.key});
  @override
  State<NewSheetPage> createState() => _NewSheetPageState();
}

class _NewSheetPageState extends State<NewSheetPage> {
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  String _selectedSkillSort = 'Alphabetical';
  bool _isEditMode = false;

  // Quick weapon stats
  int _hth1 = 1; // totals including base and penalties
  int _hth2 = 2;
  int _rng1 = 1;
  int _rng2 = 2;
  int _attackLevel = 0;

  // Cultivation tier ordering loaded from Rules
  List<String> _tierOrder = const [];
  int _currentTierBodyDr = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSkillSortPreference();
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    try {
      await CharacterCacheService.refreshIfStale();
    } catch (e) {
      debugPrint('NewSheetPage: refreshIfStale failed: $e');
    }
    final snap = await CharacterCacheService.loadCachedSnapshot();
    setState(() { _snapshot = snap; _loading = false; });
    // Compute weapon quick stats once snapshot available
    if (snap != null) {
      _computeWeaponStats(snap);
      await _loadTierOrder();
      _computeBodyDr(snap);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('New Sheet'),
        backgroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _snapshot == null
              ? const Center(child: Text('No character data found'))
              : _buildContent(),
    );
  }

  Color _getCultivationColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'iron': return Colors.grey;
      case 'silver': return Colors.blueGrey;
      case 'gold': return Colors.amber;
      case 'jade': return Colors.teal;
      case 'saint': return Colors.purple;
      case 'sovereign': return Colors.redAccent;
      default: return Colors.white;
    }
  }

  Widget _buildContent() {
    final character = (_snapshot!['character'] ?? {}) as Map<String, dynamic>;
    final essence = (_snapshot!['essence'] ?? {}) as Map<String, dynamic>;
    final build = (_snapshot!['build'] ?? {}) as Map<String, dynamic>;
    final ap = (_snapshot!['affinity_points'] ?? {}) as Map<String, dynamic>;
    final affinities = (_snapshot!['affinities'] ?? {}) as Map<String, dynamic>;
    final skillsTotalDoc = (_snapshot!['skillsTotal'] ?? const {}) as Map<String, dynamic>;

    final buildTotal = _asInt((build['total'] ?? const {})['amount']);
    final skillsCost = _asInt(skillsTotalDoc['Cost']);
    final hpFromAdv = _asInt(essence['hitPointsFromAdvancements']);
    final hpCost = hpFromAdv * 2;
    final spentBuild = skillsCost + hpCost;
    final unspentBuild = buildTotal - spentBuild;
    final totalAP = _asInt((ap['total'] ?? const {})['amount']);
    // Sum costs across each affinity's Total
    int affinitiesCost = 0;
    final List<Map<String, dynamic>> affinityCostRows = [];
    affinities.forEach((name, tiers) {
      final total = (tiers['Total'] ?? const {}) as Map<String, dynamic>;
      final cost = _asInt(total['Cost'] ?? total['cost'] ?? total['Amount'] ?? total['amount']);
      affinitiesCost += cost;
      affinityCostRows.add({'name': name.toString(), 'cost': cost, 'level': _asInt(total['Level'] ?? total['level'])});
    });
    final unspentAP = totalAP - affinitiesCost;
    final totalHP = essence['total'] ?? essence['hitPointsFromAdvancements'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                (character['characterName'] ?? 'Unnamed').toString(),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${character['cultivationTier'] ?? 'Unknown'} tier ${character['race'] ?? ''}',
                style: TextStyle(
                  fontSize: 18,
                  color: _getCultivationColor((character['cultivationTier'] ?? '').toString()),
                ),
              ),
              const SizedBox(height: 16),

              // Two cards side-by-side: Left stacks DR + Essence; Right stacks Build + Affinity Points
              Row(
                children: [
                  Expanded(
                    child: _metricStackCard(
                      topTitle: 'DR',
                      topValue: '$_currentTierBodyDr',
                      onTapTop: () => _showDRInfo(context),
                      bottomTitle: 'Essence',
                      bottomValue: '$totalHP',
                      onTapBottom: () => _showEssenceBreakdown(context, essence),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metricStackCard(
                      topTitle: 'Build Total',
                      topValue: '$buildTotal ($unspentBuild)',
                      onTapTop: () => _showBuildBreakdown(
                        context,
                        totalBuild: buildTotal,
                        skillsCost: skillsCost,
                        hitPointsFromAdvancements: hpFromAdv,
                        hpCost: hpCost,
                        unspent: unspentBuild,
                      ),
                      bottomTitle: 'Affinity Points',
                      bottomValue: '$totalAP ($unspentAP)',
                      onTapBottom: () => _showAffinityPointBreakdown(
                        context,
                        totalAP: totalAP,
                        totalCost: affinitiesCost,
                        rows: affinityCostRows,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Row 3: Weapon quick stats
              Row(
                children: [
                  // Left: Hand to Hand
                  Expanded(
                    child: _weaponSection(
                      title: 'Hand to Hand',
                      entries: [
                        MapEntry('1 Handed', '$_hth1'),
                        MapEntry('2 Handed', '$_hth2'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right: Ranged
                  Expanded(
                    child: _weaponSection(
                      title: 'Ranged',
                      entries: [
                        MapEntry('1 Handed', '$_rng1'),
                        MapEntry('2 Handed', '$_rng2'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Affinities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),

          _affinitiesGrid(affinities),

          const Divider(height: 32),

          // Skills header and sort dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Skills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _selectedSkillSort,
                onChanged: (value) async {
                  setState(() {
                    _selectedSkillSort = value!;
                  });
                  await _saveSkillSortPreference(_selectedSkillSort);
                },
                items: const [
                  DropdownMenuItem(value: 'Alphabetical', child: Text('Alphabetical')),
                  DropdownMenuItem(value: 'Type', child: Text('Type')),
                  DropdownMenuItem(value: 'Frequency', child: Text('Frequency')),
                ],
              ),
            ],
          ),
          ..._groupSkills(_snapshot!['skillsEntries'] as List<dynamic>? ?? const [], _selectedSkillSort, (character['race'] ?? '').toString()).entries.expand((entry) {
            final groupName = entry.key;
            final skills = entry.value;
            return [
              if (groupName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: Text(groupName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ...skills.map((s) => _skillRow(s)).toList(),
            ];
          }),
        ],
      ),
    );
  }

  int _getDRForTier(String tier) {
    const tiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    final index = tiers.indexWhere((t) => t.toLowerCase() == tier.toLowerCase());
    if (index < 0) return 0;
    // Example mapping to DR; adjust if you had a different map
    const drValues = [1, 2, 3, 4, 5, 6];
    return drValues[index];
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map) {
      try {
        return value.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {
        try { return Map<String, dynamic>.from(value as Map); } catch (_) {}
      }
    }
    return <String, dynamic>{};
  }

  Widget _affinitiesGrid(Map<String, dynamic> affinities) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const int columns = 3;
        const double spacing = 6.0;
        final double totalSpacing = (columns - 1) * spacing;
        final double itemWidth = (constraints.maxWidth - totalSpacing) / columns;

        final entries = affinities.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        final character = (_snapshot?['character'] ?? const {}) as Map<String, dynamic>;
        final currentTier = (character['cultivationTier'] ?? '').toString();
        final freeAffinity = (character['free_affinity'] ?? character['freeAffinity'] ?? '').toString();
        final tiersOrder = _tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'];
        final ironIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == 'iron');
        final currentIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
        final tiersAboveIron = (ironIdx >= 0 && currentIdx >= 0) ? (currentIdx - ironIdx) : 0;
        final penaltyPerTier = 2;
        final penalty = (tiersAboveIron > 0) ? penaltyPerTier * tiersAboveIron : 0;
        final List<String> penaltyTiers = (ironIdx >= 0 && currentIdx > ironIdx)
            ? tiersOrder.sublist(ironIdx + 1, currentIdx + 1)
            : <String>[];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: entries.map((entry) {
            final name = entry.key;
            final tiers = _toMap(entry.value);
            final isFree = freeAffinity.toLowerCase() == name.toLowerCase();
            // Sum per-tier purchased levels up to current
            int purchasedSum = 0;
            if (currentIdx >= 0) {
              for (int i = 0; i <= currentIdx; i++) {
                final tierName = tiersOrder[i];
                final tierData = _toMap(tiers[tierName]);
                final lvl = _asInt(tierData['Level'] ?? tierData['level']);
                purchasedSum += lvl;
              }
            }
            final freeBonus = isFree ? (currentIdx >= 0 ? (currentIdx - ironIdx + 1).clamp(0, 99) : 0) : 0; // +1 per tier from Iron to current
            final effectiveLevel = (purchasedSum + freeBonus - penalty).clamp(0, 9999);

            return Semantics(
              label: '$name affinity, effective level $effectiveLevel',
              button: true,
              child: InkWell(
                onTap: () => _showAffinityBreakdown(
                  name: name,
                  totalLevel: purchasedSum + (isFree ? (currentIdx >= 0 ? (currentIdx - ironIdx + 1).clamp(0, 99) : 0) : 0),
                  penaltyPerTier: penaltyPerTier,
                  penaltyTiers: penaltyTiers,
                  effectiveLevel: effectiveLevel,
                  isFreeAffinity: isFree,
                  freeTiers: isFree ? (ironIdx >= 0 && currentIdx >= ironIdx ? tiersOrder.sublist(ironIdx, currentIdx + 1) : <String>[]) : const <String>[],
                ),
                borderRadius: BorderRadius.circular(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: SizedBox(
                    width: itemWidth,
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: Colors.grey[850],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(
                                  '$name: $effectiveLevel',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showAffinityBreakdown({
    required String name,
    required int totalLevel,
    required int penaltyPerTier,
    required List<String> penaltyTiers,
    required int effectiveLevel,
    required bool isFreeAffinity,
    required List<String> freeTiers,
  }) async {
    // Load multiplier from Rules DB
    double multiplier = 1.0;
    try {
      final doc = await FirebaseFirestore.instance.collection('Rules').doc('Affinities').collection('All').doc(name).get();
      final data = doc.data();
      if (data != null) {
        final m = data['Multiplier'] ?? data['multiplier'] ?? data['Multipler'];
        if (m is num) multiplier = m.toDouble();
        if (m is String) multiplier = double.tryParse(m) ?? multiplier;
      }
    } catch (_) {}

    // Gather tier levels for this affinity from cached snapshot
    final affinities = _toMap(_snapshot?['affinities']);
    final entry = _toMap(affinities[name]);
    final Map<String, dynamic> tiersMap = {};
    for (final e in entry.entries) {
      tiersMap[e.key] = _toMap(e.value);
    }

    // Tier order and current tier
    final character = (_snapshot?['character'] ?? const {}) as Map<String, dynamic>;
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiersOrder = _tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'];
    final currentIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());

    int calcCost(int level, {required bool freeFirstLevel}) {
      if (level <= 0) return 0;
      if (freeFirstLevel) {
        // cost = multiplier * (triangular(level+1) - 1)
        final base = ((level + 1) * (level + 1 + 1)) / 2.0 - 1.0;
        return (base * multiplier).round();
      } else {
        final base = (level * (level + 1)) / 2.0;
        return (base * multiplier).round();
      }
    }

    // Build purchases table rows for tiers up to current
    final shownTiers = currentIdx >= 0 ? tiersOrder.sublist(0, currentIdx + 1) : <String>[];
    final rows = shownTiers.map((tier) {
      final purchased = _asInt((_toMap(tiersMap[tier]))['Level'] ?? (_toMap(tiersMap[tier]))['level']);
      final displayLevel = isFreeAffinity ? purchased + 1 : purchased; // show free included
      final cost = calcCost(purchased, freeFirstLevel: isFreeAffinity);
      return {'tier': tier, 'level': displayLevel, 'cost': cost};
    }).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$name Affinity Details'),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Effective Level', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('$currentTier: $effectiveLevel', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (currentIdx > 0 || isFreeAffinity) ...[
                  const SizedBox(height: 8),
                  const Text('Tier adjustments:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (penaltyTiers.isEmpty && !isFreeAffinity) const Text('None'),
                  if (penaltyTiers.isNotEmpty) ...penaltyTiers.map((t) => Text('−$penaltyPerTier: $t (Ascention adjustment)')),
                  if (isFreeAffinity && freeTiers.isNotEmpty)
                    ...freeTiers.map((t) => Text('+1: $t (Race Affinty)')),
                ],
                const SizedBox(height: 16),
                const Text('Purchases by Tier:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Table(
                    border: TableBorder.all(color: Colors.grey),
                    columnWidths: const { 0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1) },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey[800]),
                        children: const [
                          Padding(padding: EdgeInsets.all(8), child: Text('Bought in Tier', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Level', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Cost', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                      ...rows.map((r) => TableRow(children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text(r['tier'] as String)),
                        Padding(padding: const EdgeInsets.all(8), child: Text('${r['level']}', textAlign: TextAlign.center)),
                        Padding(padding: const EdgeInsets.all(8), child: Text('${r['cost']}', textAlign: TextAlign.right)),
                      ])).toList(),
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey[700]),
                        children: [
                          const Padding(padding: EdgeInsets.all(8), child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${rows.fold<int>(0, (s, r) => s + (r['level'] as int))}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${rows.fold<int>(0, (s, r) => s + (r['cost'] as int))}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _StatBox({required String label, required String value, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Text(label, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox({required String label, required String value, required VoidCallback onTap, bool showInfoIcon = true, VoidCallback? onBoxTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Text(label, style: const TextStyle(fontSize: 16)),
            ),
            if (showInfoIcon) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onTap,
                child: Icon(Icons.info_outline, size: 16, color: Colors.grey[300]),
              ),
            ],
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white),
            borderRadius: BorderRadius.circular(8),
          ),
          child: GestureDetector(
            onTap: onBoxTap ?? onTap,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  void _showAffinityPointBreakdown(
    BuildContext context, {
      required int totalAP,
      required int totalCost,
      required List<Map<String, dynamic>> rows,
    }
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Affinity Points Breakdown'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Affinity Points: $totalAP'),
              const SizedBox(height: 8),
              const Text('Spent by Affinity:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rows
                        .where((r) => r['cost'] != null)
                        .map((r) => Text(
                              '${r['name']}: ${r['cost']}${(r['level'] ?? 0) > 0 ? ' (Level ${r['level']})' : ''}',
                            ))
                        .toList(),
                  ),
                ),
              ),
              const Divider(height: 16),
              Text('Total Spent: $totalCost'),
              Text('Unspent: ${totalAP - totalCost}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showDRInfo(BuildContext context) {
    // Build DR breakdown using snapshot essence + current tier
    final character = (_snapshot?['character'] ?? const {}) as Map<String, dynamic>;
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiers = (_tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'])
        .where((t){ final k=t.toLowerCase(); return k!='mortal' && k!='moral'; })
        .toList();
    final currentIdx = tiers.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
    final listed = currentIdx >= 0 ? tiers.sublist(0, currentIdx + 1).reversed.toList() : <String>[];
    final essence = (_snapshot?['essence'] ?? const {}) as Map<String, dynamic>;
    final bodyByTier = (essence['bodyEssenceByTier'] ?? const {}) as Map<String, dynamic>;

    int drFromBodyLevel(int level) => level ~/ 3; // e.g., 6 -> 2

    // Precompute body DR per tier
    final Map<String, int> bodyDR = {};
    for (final t in tiers) {
      final v = (bodyByTier[t] as Map<String, dynamic>?) ?? const {};
      final lvl = _asInt(v['Level'] ?? v['level']);
      bodyDR[t] = drFromBodyLevel(lvl);
    }

    // For each listed tier (current down to Iron), sum body DR purchased at that tier and above (applies downward)
    final lines = <String>[];
    for (int i = 0; i < listed.length; i++) {
      final t = listed[i];
      int extra = 0;
      for (int j = 0; j <= i; j++) {
        extra += bodyDR[listed[j]] ?? 0;
      }
      lines.add('• $t: $extra');
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Damage Resistance (DR)'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('By Tier:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (lines.isEmpty) const Text('No tiers available') else ...lines.map((s) => Text(s)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _weaponSection({required String title, required List<MapEntry<String, String>> entries}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < entries.length; i++) ...[
                Expanded(child: _miniBox(label: entries[i].key, value: entries[i].value, onTap: () => _showWeaponBreakdown(title, entries[i].key))),
                if (i < entries.length - 1) const SizedBox(width: 8),
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBox({required String label, required String value, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(value, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showWeaponBreakdown(String title, String label) {
    final character = (_snapshot?['character'] ?? const {}) as Map<String, dynamic>;
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiersOrder = (_tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'])
        .where((t){ final k=t.toLowerCase(); return k!='mortal' && k!='moral'; })
        .toList();
    final ironIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == 'iron');
    final currentIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
    final listed = currentIdx >= 0 ? tiersOrder.sublist(0, currentIdx + 1).reversed.toList() : <String>[];

    final bool isOneHanded = label.toLowerCase().contains('1');
    final int base = isOneHanded ? 1 : 2;
    final int bonus = isOneHanded ? (_attackLevel ~/ 2) : (2 * (_attackLevel ~/ 3));

    int valueForTier(String tier) {
      final idx = tiersOrder.indexWhere((t) => t.toLowerCase() == tier.toLowerCase());
      final ascensions = (ironIdx >= 0 && idx >= 0) ? (idx - ironIdx) : 0;
      final penaltyPerAscension = isOneHanded ? 1 : 2;
      final val = base + bonus - (penaltyPerAscension * ascensions);
      return val < base ? base : val;
    }

    final lines = listed.map((t) {
      final idx = tiersOrder.indexWhere((x) => x.toLowerCase() == t.toLowerCase());
      final asc = (ironIdx >= 0 && idx >= 0) ? (idx - ironIdx) : 0;
      final penaltyPerAscension = isOneHanded ? 1 : 2;
      return '• $t: ${valueForTier(t)} (base $base + bonus $bonus − $penaltyPerAscension × ascensions $asc)';
    }).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$title • $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attack Level: $_attackLevel'),
            Text('Base: $base'),
            Text('Bonus: $bonus'),
            const SizedBox(height: 8),
            const Text('By Tier:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (lines.isEmpty) const Text('No tiers available') else ...lines.map((s) => Text(s)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildEssence(Map<String, dynamic> essence) {
    final base = essence['base'] ?? 0;
    final hp = essence['hitPointsFromAdvancements'] ?? 0;
    final body = (essence['bodyEssenceByTier'] ?? const {}) as Map<String, dynamic>;
    final total = essence['total'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Base: $base', style: const TextStyle(color: Colors.white)),
        Text('Hit Points: $hp', style: const TextStyle(color: Colors.white)),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text('Body Essence by Tier:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ...body.entries.map((e) {
            final tierData = (e.value as Map<String, dynamic>? ?? const {});
            final level = _asInt(tierData['Level'] ?? tierData['level']);
            final essenceAmt = _asInt(tierData['Essence'] ?? tierData['essence']);
            return Text('${e.key}: $essenceAmt (Level $level)', style: const TextStyle(color: Colors.white));
          }).toList(),
        ],
        Text('Total: $total', style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  void _showEssenceBreakdown(BuildContext context, Map<String, dynamic> essence) {
    final base = _asInt(essence['base']);
    final hp = _asInt(essence['hitPointsFromAdvancements']);
    final total = _asInt(essence['total']);
    final body = (essence['bodyEssenceByTier'] ?? const {}) as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Essence Details'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Base Essence: $base'),
              Text('Hit Points from Advancements: $hp'),
              const SizedBox(height: 8),
              const Text('Body Essence by Tier:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (body.isEmpty)
                const Text('None')
              else
                ...body.entries.map((e) {
                  final tierData = (e.value as Map<String, dynamic>? ?? const {});
                  final level = _asInt(tierData['Level'] ?? tierData['level']);
                  final essenceAmt = _asInt(tierData['Essence'] ?? tierData['essence']);
                  return Text('${e.key}: $essenceAmt (Level $level)');
                }).toList(),
              const Divider(height: 16),
              Text('Total Essence: $total', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showBuildBreakdown(
    BuildContext context, {
      required int totalBuild,
      required int skillsCost,
      required int hitPointsFromAdvancements,
      required int hpCost,
      required int unspent,
    }
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Build Total Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Build: $totalBuild'),
            const SizedBox(height: 8),
            Text('− Skills: $skillsCost'),
            Text('− Hit Points (2 × $hitPointsFromAdvancements): $hpCost'),
            const Divider(height: 16),
            Text('Unspent Build: $unspent', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupSkills(List<dynamic> raw, String sortBy, String characterRace) {
    final skills = raw.whereType<Map<String, dynamic>>().map((e) {
      final name = (e['name'] ?? e['Name'] ?? e['id'] ?? 'Unknown').toString();
      final type = (e['type'] ?? e['Type'] ?? 'Common').toString();
      final frequency = (e['frequency'] ?? e['Frequency'] ?? 'Passive').toString();
      return {
        'name': name,
        'type': type,
        'level': (e['level'] is num) ? (e['level'] as num).toInt() : (int.tryParse('${e['level']}') ?? 0),
        'frequency': frequency,
        'delivery': (e['delivery'] ?? e['Delivery'])?.toString(),
        'verbal': (e['verbal'] ?? e['Verbal'])?.toString(),
        'description': (e['description'] ?? e['Description'])?.toString(),
      };
    }).toList();

    Map<String, List<Map<String, dynamic>>> grouped = {};

    if (sortBy == 'Type') {
      final order = ['Common', characterRace];
      for (final s in skills) {
        final key = (s['type'] as String);
        grouped.putIfAbsent(key, () => []).add(s);
      }
      for (final key in grouped.keys) {
        grouped[key]!.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      }
      final sorted = Map<String, List<Map<String, dynamic>>>.fromEntries(
        grouped.entries.toList()
          ..sort((a, b) {
            int aIndex = order.indexOf(a.key);
            int bIndex = order.indexOf(b.key);
            if (aIndex == -1 && bIndex == -1) return a.key.compareTo(b.key);
            if (aIndex == -1) return 1;
            if (bIndex == -1) return -1;
            return aIndex.compareTo(bIndex);
          }),
      );
      return sorted;
    }

    if (sortBy == 'Frequency') {
      final frequencyOrder = ['Passive', 'At Will', 'Encounter', 'Bell', 'Daily', 'Weekend'];
      for (final s in skills) {
        final key = (s['frequency'] as String);
        grouped.putIfAbsent(key, () => []).add(s);
      }
      for (final key in grouped.keys) {
        grouped[key]!.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      }
      final sorted = Map<String, List<Map<String, dynamic>>>.fromEntries(
        grouped.entries.toList()
          ..sort((a, b) {
            int aIndex = frequencyOrder.indexOf(a.key);
            int bIndex = frequencyOrder.indexOf(b.key);
            if (aIndex == -1 && bIndex == -1) return a.key.compareTo(b.key);
            if (aIndex == -1) return 1;
            if (bIndex == -1) return -1;
            return aIndex.compareTo(bIndex);
          }),
      );
      return sorted;
    }

    // Alphabetical
    skills.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return {'': skills};
  }

  Widget _skillRow(Map<String, dynamic> s) {
    final isPassiveOrAtWill = (s['frequency'] == 'Passive' || s['frequency'] == 'At Will');
    return InkWell(
      onTap: () => _showSkillInfoDialog(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white, decoration: TextDecoration.none),
                  children: [
                    TextSpan(text: s['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    TextSpan(text: ' (${s['type']} • Level ', style: const TextStyle(fontSize: 14)),
                    TextSpan(text: '${s['level']}', style: const TextStyle(fontSize: 14)),
                    TextSpan(text: ' • ${s['frequency']})', style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
            if (_isEditMode && !isPassiveOrAtWill)
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.amber, size: 20),
                  onPressed: () {
                    // Future: open skill details dialog for advancement
                  },
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _sanitizeRuleId(String name) {
    try {
      var id = name.replaceAll('/', ' - ').replaceAll(RegExp(r"\s+"), ' ').trim();
      if (id.length > 1500) id = id.substring(0, 1500);
      return id;
    } catch (_) { return name; }
  }

  Future<Map<String, dynamic>?> _fetchSkillRule(String type, String name) async {
    final boxName = 'rulesDocCache';
    if (!Hive.isBoxOpen(boxName)) { try { await Hive.openBox(boxName); } catch (_) {} }
    final box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;
    final id = _sanitizeRuleId(name);
    final paths = [
      'Rules/Skills/$type/$id',
      'Rules/Skills/Common/$id',
      'Rules/Skills/Races/$id',
    ];
    for (final path in paths) {
      final cached = box?.get(path);
      if (cached is Map) {
        try { return Map<String, dynamic>.from(cached as Map); } catch (_) {}
      }
      if (cached is String && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached);
          if (decoded is Map) return Map<String, dynamic>.from(decoded as Map);
        } catch (_) {}
      }
    }
    // Fetch from Firestore
    for (final path in paths) {
      try {
        final parts = path.split('/');
        final snap = await FirebaseFirestore.instance
          .collection(parts[0]).doc(parts[1])
          .collection(parts[2]).doc(parts[3]).get();
        if (snap.exists) {
          final data = Map<String, dynamic>.from(snap.data()!);
          try { await box?.put(path, data); } catch (_) {}
          return data;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _showSkillInfoDialog(Map<String, dynamic> s) async {
    final name = (s['name'] ?? s['Name'] ?? '').toString();
    final type = (s['type'] ?? s['Type'] ?? 'Common').toString();
    final level = _asInt(s['level'] ?? s['Level']);
    final rule = await _fetchSkillRule(type, name) ?? {};
    final frequency = (rule['Frequency'] ?? s['frequency'] ?? '').toString();
    final delivery = (rule['Delivery'] ?? s['delivery'] ?? '').toString();
    final verbal = (rule['Verbal'] ?? s['verbal'] ?? '').toString();
    final rulesText = (rule['rules'] ?? rule['Rules'] ?? rule['Description'] ?? s['description'] ?? '').toString();
    final baseBuild = _asInt(rule['Build'] ?? rule['BaseBuild'] ?? 0);

    List<int> _calcCosts(int base, int lvl) {
      if (base <= 0 || lvl <= 0) return List<int>.filled(lvl, 1);
      return List<int>.generate(lvl, (i) => (base - i).clamp(1, base));
    }

    final costs = _calcCosts(baseBuild, level);
    final totalCost = costs.fold<int>(0, (sum, c) => sum + c);
    final hasVerbals = verbal.isNotEmpty;

    final usesChecked = List<bool>.filled(level, false);

    showDialog(
      context: context,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final dialogHeight = screenHeight * 0.65;
        return AlertDialog(
          titlePadding: const EdgeInsets.all(16),
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$name ($type)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${frequency.isNotEmpty ? frequency : ''}${delivery.isNotEmpty ? ' • $delivery' : ''}',
                style: TextStyle(fontSize: 14, color: Colors.grey[300]),
              ),
            ],
          ),
          content: SizedBox(
            height: dialogHeight,
            width: double.maxFinite,
            child: Column(
              children: [
                // Uses row (read-only checkboxes)
                Row(
                  children: [
                    const Text('Uses:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    for (int i = 0; i < level; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: StatefulBuilder(
                          builder: (context, setState) {
                            return Checkbox(
                              value: usesChecked[i],
                              onChanged: (val) => setState(() => usesChecked[i] = val ?? false),
                              visualDensity: VisualDensity.compact,
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DefaultTabController(
                    length: hasVerbals ? 3 : 2,
                    initialIndex: 0,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: hasVerbals
                              ? const [Tab(text: 'Verbal'), Tab(text: 'Rules'), Tab(text: 'Cost')]
                              : const [Tab(text: 'Rules'), Tab(text: 'Cost')],
                          labelColor: Colors.white,
                        ),
                        Expanded(
                          child: TabBarView(
                            children: hasVerbals
                                ? [
                                    SingleChildScrollView(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(verbal, style: const TextStyle(fontSize: 16)),
                                    ),
                                    SingleChildScrollView(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(rulesText, style: const TextStyle(fontSize: 16)),
                                    ),
                                    Center(
                                      child: Text(
                                        baseBuild > 0
                                            ? 'Skill Build Total: $totalCost (${costs.join(" + ")})\nBase Cost: $baseBuild'
                                            : 'Skill Build Total: $totalCost (${costs.join(" + ")})',
                                        style: const TextStyle(fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ]
                                : [
                                    SingleChildScrollView(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(rulesText, style: const TextStyle(fontSize: 16)),
                                    ),
                                    Center(
                                      child: Text(
                                        baseBuild > 0
                                            ? 'Skill Build Total: $totalCost (${costs.join(" + ")})\nBase Cost: $baseBuild'
                                            : 'Skill Build Total: $totalCost (${costs.join(" + ")})',
                                        style: const TextStyle(fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _loadSkillSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    // Prefer the same key as old sheet if present for continuity
    final legacy = prefs.getString('skill_sort_preference');
    final current = prefs.getString('skill_sorting');
    final value = legacy ?? current;
    if (value != null && ['Alphabetical', 'Type', 'Frequency'].contains(value)) {
      setState(() { _selectedSkillSort = value; });
    }
  }

  Future<void> _saveSkillSortPreference(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skill_sorting', value);
    await prefs.setString('skill_sort_preference', value);
  }

  Future<void> _computeWeaponStats(Map<String, dynamic> snap) async {
    try {
      // Default baseline
      int hth1 = 0, hth2 = 0, rng1 = 0, rng2 = 0;

      // Derive Attack level from affinities (Total.Level)
      int attackLevel = 0;
      final affinities = (snap['affinities'] ?? const {}) as Map<String, dynamic>;
      final attackEntry = (affinities['Attack'] ?? affinities['attack'] ?? const {}) as Map<String, dynamic>;
      final attackTotal = (attackEntry['Total'] ?? const {}) as Map<String, dynamic>;
      attackLevel = _asInt(attackTotal['Level'] ?? attackTotal['level']);

      // Compute totals including base and ascension penalties for CURRENT tier
      final tiers = (_tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'])
          .where((t){ final k=t.toLowerCase(); return k!='mortal' && k!='moral'; })
          .toList();
      final ironIdx = tiers.indexWhere((t) => t.toLowerCase() == 'iron');
      final currentTier = (snap['character']?['cultivationTier'] ?? '').toString();
      final currentIdx = tiers.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
      final penalty = (ironIdx >= 0 && currentIdx >= 0) ? (currentIdx - ironIdx) : 0;

      int totalFor(bool isOneHanded) {
        final base = isOneHanded ? 1 : 2;
        final bonus = isOneHanded ? (attackLevel ~/ 2) : (2 * (attackLevel ~/ 3));
        final penaltyPerAscension = isOneHanded ? 1 : 2;
        final val = base + bonus - (penaltyPerAscension * penalty);
        return val < base ? base : val;
      }

      hth1 = totalFor(true);
      hth2 = totalFor(false);
      rng1 = totalFor(true);
      rng2 = totalFor(false);

      setState(() {
        _hth1 = hth1;
        _hth2 = hth2;
        _rng1 = rng1;
        _rng2 = rng2;
        _attackLevel = attackLevel;
      });
    } catch (_) {
      // Ignore errors; keep defaults
    }
  }

  Future<void> _loadTierOrder() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('Rules').doc('Cultivation Tiers').collection('All').get();
      final rows = snap.docs
          .map((d) => {'name': d.id.toString(), 'row': (d.data()['_sheetRow'] ?? d.data()['sheetRow'] ?? 0)})
          .toList();
      rows.sort((a, b) => (a['row'] as num).compareTo(b['row'] as num));
      final ordered = rows
          .map((e) => e['name'] as String)
          .where((t) {
            final k = t.toLowerCase();
            return k != 'mortal' && k != 'moral';
          })
          .toList();
      setState(() { _tierOrder = ordered; });
    } catch (_) {}
  }

  void _computeBodyDr(Map<String, dynamic> snap) {
    final character = (snap['character'] ?? const {}) as Map<String, dynamic>;
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiers = (_tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'])
        .where((t){ final k=t.toLowerCase(); return k!='mortal' && k!='moral'; })
        .toList();
    final currentIdx = tiers.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
    final essence = (snap['essence'] ?? const {}) as Map<String, dynamic>;
    final bodyByTier = (essence['bodyEssenceByTier'] ?? const {}) as Map<String, dynamic>;

    int drFromBodyLevel(int level) => level ~/ 3;
    final Map<String, int> bodyDR = {};
    for (final t in tiers) {
      final v = (bodyByTier[t] as Map<String, dynamic>?) ?? const {};
      final lvl = _asInt(v['Level'] ?? v['level']);
      bodyDR[t] = drFromBodyLevel(lvl);
    }
    int currentDr = 0;
    if (currentIdx >= 0) {
      for (int j = 0; j <= 0; j++) {} // placeholder no-op
      // Sum body DR purchased at current tier and above (applies downward to current)
      for (int k = 0; k < bodyDR.length; k++) {}
      for (int i = 0; i < tiers.length; i++) {
        // Include tiers with index >= currentIdx (higher tiers) — but our ordering is ascending by row (lower to higher)
      }
      // Compute as sum of bodyDR for tiers whose index is >= currentIdx
      for (int i = currentIdx; i < tiers.length; i++) {
        currentDr += bodyDR[tiers[i]] ?? 0;
      }
    }
    setState(() { _currentTierBodyDr = currentDr; });
  }

  Widget _metricCard({required String title, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(value, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricStackCard({
    required String topTitle,
    required String topValue,
    required VoidCallback onTapTop,
    required String bottomTitle,
    required String bottomValue,
    required VoidCallback onTapBottom,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTapTop,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(topTitle, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(topValue, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onTapBottom,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(bottomTitle, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(bottomValue, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


