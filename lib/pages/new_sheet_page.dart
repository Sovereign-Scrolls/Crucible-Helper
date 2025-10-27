import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../shared/character_cache_service.dart';
import '../shared/impersonation_service.dart';
import '../shared/admin_cache_service.dart';
import '../config/app_config.dart';
import '../models/character.dart';
import '../main.dart' show CharacterSheetPage;

class NewSheetPage extends StatefulWidget {
  const NewSheetPage({super.key});
  @override
  State<NewSheetPage> createState() => _NewSheetPageState();
}

class _NewSheetPageState extends State<NewSheetPage> {
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  String _selectedSkillSort = 'Alphabetical';
  final bool _isEditMode = false;
  
  // Impersonation state
  bool _isImpersonating = false;
  
  // Menu functionality state
  bool _isSuperAdmin = false;
  final bool _hasUnsubmittedChanges = false;
  final List<String> _skillSortOptions = ['Alphabetical', 'Type', 'Frequency'];

  // Quick weapon stats
  int _hth1 = 1; // totals including base and penalties
  int _hth2 = 2;
  int _rng1 = 1;
  int _rng2 = 2;
  int _attackLevel = 0;

  // Cultivation tier ordering loaded from Rules
  List<String> _tierOrder = const [];
  int _currentTierBodyDr = 0;

  // Convert snapshot data to Character object for old sheet
  Character? _getCharacterFromSnapshot() {
    if (_snapshot == null) return null;
    
    try {
      final characterData = _snapshot!['character'] as Map<String, dynamic>?;
      if (characterData == null) return null;
      
      return Character.fromJson(characterData);
    } catch (e) {
      print('❌ NewSheetPage: Error converting snapshot to Character: $e');
      return null;
    }
  }

  // Check super admin permissions
  Future<void> _checkSuperAdminPermissions() async {
    try {
      final isAdmin = await AdminCacheService.getAdminStatus(
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              _isSuperAdmin = status;
            });
          }
        },
        forceRefresh: false,
      );
      setState(() {
        _isSuperAdmin = isAdmin;
      });
    } catch (e) {
      print('❌ NewSheetPage: Error checking admin permissions: $e');
    }
  }

  // Load skill sort preference
  Future<void> _loadSkillSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSort = prefs.getString('skill_sort_preference');
      if (savedSort != null && _skillSortOptions.contains(savedSort)) {
        setState(() {
          _selectedSkillSort = savedSort;
        });
      }
    } catch (e) {
      print('❌ NewSheetPage: Error loading skill sort preference: $e');
    }
  }

  // Show stored cores dialog
  void _showStoredCores() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Loading Stored Cores...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Getting stored cores...'),
              ],
            ),
          );
        },
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User not authenticated')),
        );
        return;
      }

      final idToken = await user.getIdToken();
      final characterData = _snapshot!['character'] as Map<String, dynamic>?;
      final characterNumber = characterData?['characterNumber']?.toString() ?? 'main';
      
      // Use the Firebase Function to get stored cores
      final response = await http.get(
        Uri.parse('${AppConfig.getStoredCoresUrl}?characterId=${user.uid}_$characterNumber'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          final coresByTier = responseData['coresByTier'] as Map<String, dynamic>;
          
          // Close loading dialog
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          
          _showStoredCoresDialog(coresByTier);
        } else {
          // Close loading dialog
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${responseData['error']}')),
          );
        }
      } else {
        // Close loading dialog
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading stored cores: HTTP ${response.statusCode}')),
        );
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error loading stored cores: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stored cores: $error')),
      );
    }
  }

  // Show stored cores dialog
  void _showStoredCoresDialog(Map<String, dynamic> coresByTier) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.inventory, color: Colors.orange),
              SizedBox(width: 8),
              Text('Stored Cores'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: coresByTier.entries.map((entry) {
                final tier = entry.key;
                final cores = entry.value as Map<String, dynamic>;
                return Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      ...cores.entries.map((coreEntry) {
                        return Padding(
                          padding: EdgeInsets.only(left: 16),
                          child: Text('${coreEntry.key}: ${coreEntry.value}'),
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // Sync character data
  Future<void> _syncCharacterData() async {
    // Show loading indicator
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Regenerating from Master Logs...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final effectiveEmail = ImpersonationService.getEffectiveEmail() ?? user?.email;
      if (effectiveEmail == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ User not authenticated')),
          );
        }
        return;
      }

      print('🔄 Syncing character data for: $effectiveEmail (impersonating: ${ImpersonationService.isImpersonating})');
      
      // Refresh character cache
      await CharacterCacheService.refreshIfStale();
      
      // Reload the page data
      await _load();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Character data synced successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error syncing character data: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to sync character data: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _checkSuperAdminPermissions();
    _loadSkillSortPreference();
    
    // Initialize impersonation status
    _isImpersonating = ImpersonationService.isImpersonating;
    
    // Listen to impersonation status changes
    ImpersonationService.listenable.addListener(() {
      if (mounted) {
        final wasImpersonating = _isImpersonating;
        final nowImpersonating = ImpersonationService.isImpersonating;
        
        setState(() {
          _isImpersonating = nowImpersonating;
        });
        
        // Reload data if impersonation status changed
        if (wasImpersonating != nowImpersonating) {
          print('🎭 NewSheetPage: Impersonation status changed, reloading data');
          _load();
        }
        
        // If we stopped impersonating, navigate back to home
        if (wasImpersonating && !nowImpersonating) {
          print('🔄 NewSheetPage: Impersonation stopped, navigating to home...');
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    
    try {
      Map<String, dynamic>? snap;
      
      // Check if we're impersonating and load appropriate data
      if (ImpersonationService.isImpersonating) {
        print('🎭 NewSheetPage: Loading impersonated character data');
        snap = await _loadImpersonatedCharacterData();
      } else {
        print('🔄 NewSheetPage: Loading normal character data');
        try {
          await CharacterCacheService.refreshIfStale();
        } catch (e) {
          debugPrint('NewSheetPage: refreshIfStale failed: $e');
        }
        snap = await CharacterCacheService.loadCachedSnapshot();
        if (snap != null) {
          print('🔄 NewSheetPage: Normal cached data keys: ${snap.keys.toList()}');
          print('🔄 NewSheetPage: Normal character section: ${snap['character']}');
          print('🔄 NewSheetPage: Normal affinities section: ${snap['affinities']}');
        }
      }
      
      setState(() { 
        _snapshot = snap; 
        _loading = false; 
      });
      
      // Compute weapon quick stats once snapshot available
      if (snap != null) {
        _computeWeaponStats(snap);
        await _loadTierOrder();
        _computeBodyDr(snap);
      }
    } catch (e) {
      print('❌ NewSheetPage: Error loading character data: $e');
      setState(() { 
        _snapshot = null; 
        _loading = false; 
      });
    }
  }

  Future<Map<String, dynamic>?> _loadImpersonatedCharacterData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🎭 NewSheetPage: No user found for impersonation');
        return null;
      }

      final targetUid = ImpersonationService.getEffectiveUid();
      if (targetUid == null) {
        print('🎭 NewSheetPage: No target UID for impersonation');
        return null;
      }

      print('🎭 NewSheetPage: Loading character data for impersonated user: $targetUid');
      
      // Use the same approach as the main page - get character ID first, then load full details
      final idToken = await user.getIdToken();
      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getCharacters?impersonateUid=$targetUid'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true && responseData['characters'] != null) {
          final characters = responseData['characters'] as List;
          if (characters.isNotEmpty) {
            // Get the character ID and load full details (same as main page)
            final characterData = characters[0];
            final characterId = characterData['id'] as String;
            print('🎭 NewSheetPage: Got character ID: $characterId, loading full details...');
            
            // Parse character number from the ID (format is usually {uid}_{characterNumber})
            String characterNumber;
            if (characterId.contains('_')) {
              characterNumber = characterId.split('_').last;
            } else {
              characterNumber = characterId;
            }
            print('🎭 NewSheetPage: Using character number: $characterNumber');
            
            // Load full character details and build snapshot from Firestore
            return await _loadImpersonatedCharacterSnapshot(characterNumber, targetUid);
          }
        }
      }
      
      print('❌ NewSheetPage: Failed to load impersonated character data - Status: ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ NewSheetPage: Error loading impersonated character data: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadImpersonatedCharacterSnapshot(String characterNumber, String targetUid) async {
    try {
      print('🎭 NewSheetPage: Building snapshot for character number $characterNumber in user $targetUid');
      
      final db = FirebaseFirestore.instance;
      final charRef = db.collection('players').doc(targetUid).collection('characters').doc(characterNumber);
      
      // Check if character document exists
      print('🎭 NewSheetPage: Checking path: ${charRef.path}');
      final charSnap = await charRef.get();
      if (!charSnap.exists) {
        print('❌ NewSheetPage: Character document does not exist at path: ${charRef.path}');
        
        // Let's try to list what characters do exist for this user
        final charactersQuery = await db.collection('players').doc(targetUid).collection('characters').get();
        print('🎭 NewSheetPage: Available characters for user $targetUid:');
        for (final doc in charactersQuery.docs) {
          print('  - Character ID: ${doc.id}');
        }
        return null;
      }

      // Build the same structure as CharacterCacheService.fetchCharacterSnapshot
      final futures = <Future>[];
      Map<String, dynamic> result = {
        'character': charSnap.data(),
      };

      // essence/summary
      futures.add(charRef.collection('essence').doc('summary').get().then((s) {
        result['essence'] = s.data() ?? {};
      }));

      // build (all + Total)
      futures.add(charRef.collection('build').get().then((s) {
        final entries = <Map<String, dynamic>>[];
        Map<String, dynamic>? total;
        for (final d in s.docs) {
          if (d.id.toLowerCase() == 'total') {
            total = d.data();
          } else {
            entries.add({'id': d.id, ...d.data()});
          }
        }
        result['build'] = {'entries': entries, 'total': total};
      }));

      // affinity_points (all + Total)
      futures.add(charRef.collection('affinity_points').get().then((s) {
        final entries = <Map<String, dynamic>>[];
        Map<String, dynamic>? total;
        for (final d in s.docs) {
          if (d.id.toLowerCase() == 'total') {
            total = d.data();
          } else {
            entries.add({'id': d.id, ...d.data()});
          }
        }
        result['affinity_points'] = {'entries': entries, 'total': total};
      }));

      // affinities (tiers)
      futures.add(charRef.collection('affinities').get().then((aff) async {
        final affMap = <String, dynamic>{};
        for (final a in aff.docs) {
          final tiers = await a.reference.collection('tiers').get();
          final tierMap = <String, dynamic>{};
          for (final t in tiers.docs) {
            tierMap[t.id] = t.data();
          }
          affMap[a.id] = tierMap;
        }
        result['affinities'] = affMap;
      }));

      // skills/Total cost only
      futures.add(charRef.collection('skills').doc('Total').get().then((s) {
        result['skillsTotal'] = s.data() ?? {};
      }));

      // skills entries (full skills data)
      futures.add(charRef.collection('skills').get().then((typesSnap) async {
        final entries = <Map<String, dynamic>>[];
        for (final typeDoc in typesSnap.docs) {
          final typeId = typeDoc.id;
          if (typeId.toLowerCase() == 'total') continue;
          try {
            final itemsSnap = await typeDoc.reference.collection('items').get();
            for (final item in itemsSnap.docs) {
              final data = Map<String, dynamic>.from(item.data());
              data['name'] ??= item.id;
              data['type'] ??= typeId;
              // Normalize level to lowercase key alongside existing Level
              final dynamic rawLevel = data['level'] ?? data['Level'];
              if (rawLevel is num) data['level'] = rawLevel.toInt();
              if (rawLevel is String) data['level'] = int.tryParse(rawLevel) ?? 0;
              entries.add(data);
            }
          } catch (_) {
            // If no items subcollection, fall back to using the type doc as one entry
            final data = Map<String, dynamic>.from(typeDoc.data());
            data['name'] ??= typeId;
            data['type'] ??= typeId;
            final dynamic rawLevel = data['level'] ?? data['Level'];
            if (rawLevel is num) data['level'] = rawLevel.toInt();
            if (rawLevel is String) data['level'] = int.tryParse(rawLevel) ?? 0;
            entries.add(data);
          }
        }
        result['skillsEntries'] = entries;
      }));

      await Future.wait(futures);

      print('🎭 NewSheetPage: Successfully built snapshot with keys: ${result.keys.toList()}');
      print('🎭 NewSheetPage: Character data: ${result['character']}');
      print('🎭 NewSheetPage: Affinities data: ${result['affinities']}');
      print('🎭 NewSheetPage: Skills entries count: ${(result['skillsEntries'] as List?)?.length ?? 0}');
      print('🎭 NewSheetPage: Skills total: ${result['skillsTotal']}');
      
      return result;
    } catch (e) {
      print('❌ NewSheetPage: Error building impersonated character snapshot: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Character Sheet'),
        backgroundColor: Colors.black,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) async {
              switch (value) {
                case 'old_sheet':
                  final character = _getCharacterFromSnapshot();
                  if (character != null) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CharacterSheetPage(character: character),
                    ));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Character data not available')),
                    );
                  }
                  break;
                case 'cores':
                  _showStoredCores();
                  break;
                case 'sync':
                  _syncCharacterData();
                  break;
                case 'edit':
                  // Edit mode functionality - for now just show a message
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Edit mode not yet implemented in new sheet')),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'cores',
                child: Row(
                  children: [
                    Icon(Icons.inventory, size: 20),
                    SizedBox(width: 12),
                    Text('Stored Cores'),
                  ],
                ),
              ),
              if (_isSuperAdmin)
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 12),
                      Text('Edit Mode'),
                    ],
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'sync',
                child: Row(
                  children: [
                    Icon(Icons.sync, size: 20),
                    SizedBox(width: 12),
                    Text('Sync Character Data'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'old_sheet',
                child: Row(
                  children: [
                    Icon(Icons.history, color: Colors.white),
                    SizedBox(width: 8),
                    Text('View Old Sheet'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Impersonation banner (always at top)
          if (_isImpersonating)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade800, Colors.red.shade700],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_search,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🎭 IMPERSONATING USER',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          ImpersonationService.targetEmail ?? 'Unknown User',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ImpersonationService.stop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ Stopped impersonating user'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(Icons.close, color: Colors.white, size: 16),
                    label: Text(
                      'STOP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.2),
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size(0, 0),
                    ),
                  ),
                ],
              ),
            ),
          // Main content
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _snapshot == null
              ? const Center(child: Text('No character data found'))
              : _buildContent(),
          ),
        ],
      ),
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
    final character = Map<String, dynamic>.from(_snapshot!['character'] ?? {});
    final essence = Map<String, dynamic>.from(_snapshot!['essence'] ?? {});
    final build = Map<String, dynamic>.from(_snapshot!['build'] ?? {});
    final ap = Map<String, dynamic>.from(_snapshot!['affinity_points'] ?? {});
    final affinities = Map<String, dynamic>.from(_snapshot!['affinities'] ?? {});
    final skillsTotalDoc = Map<String, dynamic>.from(_snapshot!['skillsTotal'] ?? const {});

    // Use Total document data for build calculations
    final buildTotalDoc = Map<String, dynamic>.from(build['total'] ?? const {});
    final buildTotal = _asInt(buildTotalDoc['amount']);
    final skillsCost = _asInt(buildTotalDoc['skills'] ?? skillsTotalDoc['Cost']); // Fallback to old calculation
    final essenceCost = _asInt(buildTotalDoc['essence'] ?? 0);
    final spentBuild = _asInt(buildTotalDoc['spent'] ?? 0); // This will be negative
    final unspentBuild = _asInt(buildTotalDoc['unspent'] ?? 0);
    // Use Total document data for affinity points calculations
    final apTotalDoc = Map<String, dynamic>.from(ap['total'] ?? const {});
    final apAmount = _asInt(apTotalDoc['amount']);
    final perfectCultivationPoints = _asInt(apTotalDoc['Perfect Cultivation Points'] ?? 0);
    final totalAP = _asInt(apTotalDoc['Total Affinity Points'] ?? apAmount); // Fallback to amount for old data
    final affinitiesCost = _asInt(apTotalDoc['spent'] ?? 0);
    final unspentAP = _asInt(apTotalDoc['unspent'] ?? 0);
    final maxSlot = _asInt(apTotalDoc['Max Slot'] ?? 0);
    final slotable = _asInt(apTotalDoc['Slotable'] ?? 0);
    
    // Build affinity cost rows from Total document
    final List<Map<String, dynamic>> affinityCostRows = [];
    affinities.forEach((name, tiers) {
      final total = Map<String, dynamic>.from(tiers['Total'] ?? const {});
      final cost = _asInt(total['Cost'] ?? total['cost'] ?? total['Amount'] ?? total['amount']);
      affinityCostRows.add({'name': name.toString(), 'cost': cost, 'level': _asInt(total['Level'] ?? total['level'])});
    });
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
                        hitPointsFromAdvancements: _asInt(essence['hitPointsFromAdvancements']),
                        hpCost: essenceCost,
                        spent: spentBuild,
                        unspent: unspentBuild,
                      ),
                      bottomTitle: 'Affinity Points',
                      bottomValue: '$totalAP ($unspentAP)',
                      onTapBottom: () => _showAffinityPointBreakdown(
                        context,
                        apAmount: apAmount,
                        perfectCultivationPoints: perfectCultivationPoints,
                        totalAP: totalAP,
                        totalCost: affinitiesCost,
                        unspentAP: unspentAP,
                        maxSlot: maxSlot,
                        slotable: slotable,
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
              ...skills.map((s) => _skillRow(s)),
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
        try { return Map<String, dynamic>.from(value); } catch (_) {}
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
        final character = Map<String, dynamic>.from(_snapshot?['character'] ?? const {});
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
            // Get Effective Level from database Total entry
            final affinityTiers = _toMap(entry.value);
            final totalData = _toMap(affinityTiers['Total']);
            final dbEffectiveLevel = _asInt(totalData['Effective Level'] ?? totalData['effectiveLevel'] ?? 0);

            return Semantics(
              label: '$name affinity, effective level $dbEffectiveLevel',
              button: true,
              child: InkWell(
                onTap: () => _showAffinityBreakdown(
                  name: name,
                  totalLevel: purchasedSum + (isFree ? (currentIdx >= 0 ? (currentIdx - ironIdx + 1).clamp(0, 99) : 0) : 0),
                  penaltyPerTier: penaltyPerTier,
                  penaltyTiers: penaltyTiers,
                  effectiveLevel: dbEffectiveLevel,
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
                                  '$name: $dbEffectiveLevel',
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
    // Gather tier levels for this affinity from cached snapshot
    final affinities = _toMap(_snapshot?['affinities']);
    final entry = _toMap(affinities[name]);
    final Map<String, dynamic> tiersMap = {};
    for (final e in entry.entries) {
      tiersMap[e.key] = _toMap(e.value);
    }

    // Get data from Total entry in database
    final total = Map<String, dynamic>.from(tiersMap['Total'] ?? const {});
    final dbTotalLevel = _asInt(total['Level'] ?? total['level']);
    final dbTotalCost = _asInt(total['Cost'] ?? total['cost']);
    final dbAscensionAdjustment = _asInt(total['Ascension Adjustment'] ?? total['ascensionAdjustment'] ?? 0);
    final dbEffectiveLevel = _asInt(total['Effective Level'] ?? total['effectiveLevel'] ?? effectiveLevel);

    // Tier order and current tier
    final character = Map<String, dynamic>.from(_snapshot?['character'] ?? const {});
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiersOrder = _tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'];
    final currentIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());

    // Build table rows for all tiers that have levels > 0
    final tableRows = <TableRow>[];
    
    // Add header row
    tableRows.add(TableRow(
      decoration: BoxDecoration(color: Colors.grey[800]),
      children: const [
        Padding(padding: EdgeInsets.all(8), child: Text('Adjustment', style: TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: EdgeInsets.all(8), child: Text('Level', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: EdgeInsets.all(8), child: Text('Cost', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));
    
    // Add tier rows for tiers that have levels > 0
    for (final tier in tiersOrder) {
      final tierData = Map<String, dynamic>.from(_toMap(tiersMap[tier]));
      final tierLevel = _asInt(tierData['Level'] ?? tierData['level']);
      
      if (tierLevel > 0) {
        final tierCost = _asInt(tierData['Cost'] ?? tierData['cost']);
        final isFreeTier = isFreeAffinity && tiersOrder.indexOf(tier) <= currentIdx;
        final adjustmentText = isFreeTier ? '$tier Tier (+1 Race)' : '$tier Tier';
        
        tableRows.add(TableRow(children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(adjustmentText)),
          Padding(padding: const EdgeInsets.all(8), child: Text('$tierLevel', textAlign: TextAlign.center)),
          Padding(padding: const EdgeInsets.all(8), child: Text('$tierCost', textAlign: TextAlign.right)),
        ]));
      }
    }
    
    // Add Total Level row
    tableRows.add(TableRow(
      decoration: BoxDecoration(color: Colors.grey[700]),
      children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Total Level', style: TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8), child: Text('$dbTotalLevel', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8), child: Text('$dbTotalCost', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));
    
    // Add Ascension Adjustment row
    tableRows.add(TableRow(children: [
      const Padding(padding: EdgeInsets.all(8), child: Text('Ascension Adjustment')),
      Padding(padding: const EdgeInsets.all(8), child: Text('-$dbAscensionAdjustment', textAlign: TextAlign.center)),
      const Padding(padding: EdgeInsets.all(8), child: Text('-', textAlign: TextAlign.right)),
    ]));
    
    // Add Effective Level row
    tableRows.add(TableRow(
      decoration: BoxDecoration(color: Colors.grey[700]),
      children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Effective Level', style: TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8), child: Text('$dbEffectiveLevel', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8), child: Text('$dbTotalCost', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$name Affinity Details'),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Centered Effective Level
                Center(
                  child: Text(
                    'Effective Level: $dbEffectiveLevel',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Table
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Table(
                    border: TableBorder.all(color: Colors.grey),
                    columnWidths: const { 0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1) },
                    children: tableRows,
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
      required int apAmount,
      required int perfectCultivationPoints,
      required int totalAP,
      required int totalCost,
      required int unspentAP,
      required int maxSlot,
      required int slotable,
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
              Text('Affinity Points: $apAmount'),
              if (perfectCultivationPoints > 0) ...[
                const SizedBox(height: 4),
                Text('Perfect Cultivation Points: $perfectCultivationPoints'),
              ],
              const SizedBox(height: 8),
              Text('Total Affinity Points: $totalAP', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Max Slot: $maxSlot'),
              Text('Slotable: $slotable', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(height: 16),
              const Text('Spent by Affinity:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rows
                        .where((r) => r['cost'] != null)
                        .map((r) => Text('${r['name']}: ${r['cost']}'))
                        .toList(),
                  ),
                ),
              ),
              const Divider(height: 16),
              Text('Total Spent: $totalCost'),
              Text('Unspent: $unspentAP', style: const TextStyle(fontWeight: FontWeight.bold)),
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
    final character = Map<String, dynamic>.from(_snapshot?['character'] ?? const {});
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiers = (_tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'])
        .where((t){ final k=t.toLowerCase(); return k!='mortal' && k!='moral'; })
        .toList();
    final currentIdx = tiers.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
    final listed = currentIdx >= 0 ? tiers.sublist(0, currentIdx + 1).reversed.toList() : <String>[];
    final essence = Map<String, dynamic>.from(_snapshot?['essence'] ?? const {});
    final bodyByTier = Map<String, dynamic>.from(essence['bodyEssenceByTier'] ?? const {});

    int drFromBodyLevel(int level) => level ~/ 3; // e.g., 6 -> 2

    // Precompute body DR per tier
    final Map<String, int> bodyDR = {};
    for (final t in tiers) {
      final v = Map<String, dynamic>.from(bodyByTier[t] ?? const {});
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
    final character = Map<String, dynamic>.from(_snapshot?['character'] ?? const {});
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
            // Title
            Text(
              '$title • $label',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Separator line
            Container(
              width: double.infinity,
              height: 1,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            
            // Base information
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Base:', style: TextStyle(fontSize: 16)),
                Text('$base', style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isOneHanded 
                      ? 'Attack Bonus: (Attack $_attackLevel/2)'
                      : 'Attack Bonus: (2 × Attack $_attackLevel/3)',
                  style: const TextStyle(fontSize: 16),
                ),
                Text('$bonus', style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ascension Adjustment:', style: TextStyle(fontSize: 16)),
                Text(
                  '-${(currentIdx - ironIdx).clamp(0, 999) * (isOneHanded ? 1 : 2)}',
                  style: const TextStyle(fontSize: 16, color: Colors.orange),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Separator line
            Container(
              width: double.infinity,
              height: 1,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            
            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${base + bonus - ((currentIdx - ironIdx).clamp(0, 999) * (isOneHanded ? 1 : 2))}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Rules section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rules:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOneHanded 
                        ? 'The base weapon strike does $base. At each even purchase damage increases by 1.\n-1 attack bonus every ascension.'
                        : 'The base weapon strike does $base. At every third purchase damage increases by 2.\n-2 attack bonus every ascension.',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
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
    final body = Map<String, dynamic>.from(essence['bodyEssenceByTier'] ?? const {});
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
            final tierData = Map<String, dynamic>.from(e.value ?? const {});
            final level = _asInt(tierData['Level'] ?? tierData['level']);
            final essenceAmt = _asInt(tierData['Essence'] ?? tierData['essence']);
            return Text('${e.key}: $essenceAmt (Level $level)', style: const TextStyle(color: Colors.white));
          }),
        ],
        Text('Total: $total', style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  void _showEssenceBreakdown(BuildContext context, Map<String, dynamic> essence) {
    final base = _asInt(essence['base']);
    final hp = _asInt(essence['hitPointsFromAdvancements']);
    final total = _asInt(essence['total']);
    final body = Map<String, dynamic>.from(essence['bodyEssenceByTier'] ?? const {});
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
                  final tierData = Map<String, dynamic>.from(e.value ?? const {});
                  final level = _asInt(tierData['Level'] ?? tierData['level']);
                  final essenceAmt = _asInt(tierData['Essence'] ?? tierData['essence']);
                  return Text('${e.key}: $essenceAmt (Level $level)');
                }),
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
      required int spent,
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
            Text('− Essence: $hpCost'),
            Text('Total Spent: $spent'),
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
                  style: (Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white, decoration: TextDecoration.none))
                      ?? const TextStyle(color: Colors.white, decoration: TextDecoration.none),
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
        try { return Map<String, dynamic>.from(cached); } catch (_) {}
      }
      if (cached is String && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
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

    List<int> calcCosts(int base, int lvl) {
      if (base <= 0 || lvl <= 0) return List<int>.filled(lvl, 1);
      return List<int>.generate(lvl, (i) => (base - i).clamp(1, base));
    }

    final costs = calcCosts(baseBuild, level);
    final totalCost = costs.fold<int>(0, (sum, c) => sum + c);
    final hasVerbals = verbal.isNotEmpty;

    // Calculate ascension adjustment
    final character = Map<String, dynamic>.from(_snapshot?['character'] ?? const {});
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiersOrder = _tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'];
    final ironIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == 'iron');
    final currentIdx = tiersOrder.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
    final ascensions = (ironIdx >= 0 && currentIdx >= 0) ? (currentIdx - ironIdx) : 0;
    final ascensionAdjustment = ascensions; // Each ascension reduces by 1
    final adjustedLevel = (level - ascensionAdjustment).clamp(0, level);
    final adjustedCosts = calcCosts(baseBuild, adjustedLevel);
    final adjustedTotalCost = adjustedCosts.fold<int>(0, (sum, c) => sum + c);

    final usesChecked = List<bool>.filled(level, false);

    // Load existing note (from cache, then Firestore if missing)
    final String initialNote = await _loadSkillNote(type, name) ?? '';
    final TextEditingController noteController = TextEditingController(text: initialNote);

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
                    length: hasVerbals ? 4 : 3,
                    initialIndex: 0,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: hasVerbals
                              ? const [Tab(text: 'Verbal'), Tab(text: 'Rules'), Tab(text: 'Cost'), Tab(text: 'Notes')]
                              : const [Tab(text: 'Rules'), Tab(text: 'Cost'), Tab(text: 'Notes')],
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
                                            ? 'Skill Build Total: $adjustedTotalCost (${adjustedCosts.join(" + ")})\nBase Cost: $baseBuild'
                                            : 'Skill Build Total: $adjustedTotalCost (${adjustedCosts.join(" + ")})',
                                        style: const TextStyle(fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: TextField(
                                        controller: noteController,
                                        minLines: 6,
                                        maxLines: null,
                                        decoration: const InputDecoration(
                                          labelText: 'Notes',
                                          border: OutlineInputBorder(),
                                          hintText: 'Write your notes about this skill here...'
                                        ),
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
                                            ? 'Skill Build Total: $adjustedTotalCost (${adjustedCosts.join(" + ")})\nBase Cost: $baseBuild'
                                            : 'Skill Build Total: $adjustedTotalCost (${adjustedCosts.join(" + ")})',
                                        style: const TextStyle(fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: TextField(
                                        controller: noteController,
                                        minLines: 6,
                                        maxLines: null,
                                        decoration: const InputDecoration(
                                          labelText: 'Notes',
                                          border: OutlineInputBorder(),
                                          hintText: 'Write your notes about this skill here...'
                                        ),
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
            TextButton(
              onPressed: () async {
                await _saveSkillNote(type, name, noteController.text.trim());
                Navigator.of(context).pop();
              },
              child: const Text('Save Notes'),
            ),
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
      final affinities = Map<String, dynamic>.from(snap['affinities'] ?? const {});
      final attackEntry = Map<String, dynamic>.from(affinities['Attack'] ?? affinities['attack'] ?? const {});
      final attackTotal = Map<String, dynamic>.from(attackEntry['Total'] ?? const {});
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
    final character = Map<String, dynamic>.from(snap['character'] ?? const {});
    final currentTier = (character['cultivationTier'] ?? '').toString();
    final tiers = (_tierOrder.isNotEmpty ? _tierOrder : ['Iron','Silver','Gold','Jade','Saint','Sovereign'])
        .where((t){ final k=t.toLowerCase(); return k!='mortal' && k!='moral'; })
        .toList();
    final currentIdx = tiers.indexWhere((t) => t.toLowerCase() == currentTier.toLowerCase());
    final essence = Map<String, dynamic>.from(snap['essence'] ?? const {});
    final bodyByTier = Map<String, dynamic>.from(essence['bodyEssenceByTier'] ?? const {});

    int drFromBodyLevel(int level) => level ~/ 3;
    final Map<String, int> bodyDR = {};
    for (final t in tiers) {
      final v = Map<String, dynamic>.from(bodyByTier[t] ?? const {});
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

  // Load/save skill notes (cached + Firestore), per character/skill
  Future<String?> _loadSkillNote(String type, String skillName) async {
    final boxName = 'skillNotes';
    if (!Hive.isBoxOpen(boxName)) { try { await Hive.openBox(boxName); } catch (_) {} }
    final box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;
    final key = await _composeSkillNoteKey(type, skillName);
    final cached = box?.get(key);
    if (cached is String) return cached;
    try {
      final doc = await _skillDocRef(type, skillName).get();
      final data = doc.data();
      final note = (data != null) ? (data['Notes'] ?? data['notes'] ?? '') : '';
      if (note is String) { await box?.put(key, note); return note; }
    } catch (_) {}
    return null;
  }

  Future<void> _saveSkillNote(String type, String skillName, String note) async {
    final boxName = 'skillNotes';
    if (!Hive.isBoxOpen(boxName)) { try { await Hive.openBox(boxName); } catch (_) {} }
    final box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;
    final key = await _composeSkillNoteKey(type, skillName);
    try { await box?.put(key, note); } catch (_) {}
    try { await _skillDocRef(type, skillName).set({'Notes': note}, SetOptions(merge: true)); } catch (_) {}
  }

  Future<String> _composeSkillNoteKey(String type, String skillName) async {
    final path = _snapshot?['characterRefPath']?.toString();
    if (path != null && path.contains('/')) return '$path|$type|$skillName|note';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final charNum = (_snapshot?['character']?['characterNumber'] ?? 'unknown').toString();
    return 'players/$uid/characters/$charNum|$type|$skillName|note';
  }

  DocumentReference<Map<String, dynamic>> _skillDocRef(String type, String skillName) {
    final path = _snapshot?['characterRefPath']?.toString();
    String uid;
    String charNum;
    if (path != null) {
      final parts = path.split('/');
      uid = parts.length >= 2 ? parts[1] : (FirebaseAuth.instance.currentUser?.uid ?? 'unknown');
      charNum = parts.length >= 4 ? parts[3] : (_snapshot?['character']?['characterNumber'] ?? 'unknown').toString();
    } else {
      uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      charNum = (_snapshot?['character']?['characterNumber'] ?? 'unknown').toString();
    }
    return FirebaseFirestore.instance
        .collection('players').doc(uid)
        .collection('characters').doc(charNum)
        .collection('skills').doc(type)
        .collection('items').doc(skillName);
  }
}


