import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'shared/rules_service.dart';
import 'dart:html' as html;

import 'models/character.dart'; 
import 'pages/login_page.dart';
import 'pages/events_page.dart';
import 'utils/skill_lookup.dart';

// Data structures for unsubmitted advancement
class AffinityChange {
  final String timestamp;
  final String affinityName;
  final String adjustment; // e.g., "Bought in Gold"
  final int cost;
  final int levelChange; // +1 for increase, -1 for decrease

  AffinityChange({
    required this.timestamp,
    required this.affinityName,
    required this.adjustment,
    required this.cost,
    required this.levelChange,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'affinityName': affinityName,
    'adjustment': adjustment,
    'cost': cost,
    'levelChange': levelChange,
  };

  factory AffinityChange.fromJson(Map<String, dynamic> json) => AffinityChange(
    timestamp: json['timestamp'],
    affinityName: json['affinityName'],
    adjustment: json['adjustment'],
    cost: json['cost'],
    levelChange: json['levelChange'],
  );
}

class SkillChange {
  final String timestamp;
  final String skillName;
  final String skillType;
  final int levelChange; // +1 for increase, -1 for decrease
  final int cost;

  SkillChange({
    required this.timestamp,
    required this.skillName,
    required this.skillType,
    required this.levelChange,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'skillName': skillName,
    'skillType': skillType,
    'levelChange': levelChange,
    'cost': cost,
  };

  factory SkillChange.fromJson(Map<String, dynamic> json) => SkillChange(
    timestamp: json['timestamp'],
    skillName: json['skillName'],
    skillType: json['skillType'],
    levelChange: json['levelChange'],
    cost: json['cost'],
  );
}

class EssenceChange {
  final String timestamp;
  final int essenceAdjustment; // +1 for increase, -1 for decrease
  final int cost;

  EssenceChange({
    required this.timestamp,
    required this.essenceAdjustment,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'essenceAdjustment': essenceAdjustment,
    'cost': cost,
  };

  factory EssenceChange.fromJson(Map<String, dynamic> json) => EssenceChange(
    timestamp: json['timestamp'],
    essenceAdjustment: json['essenceAdjustment'],
    cost: json['cost'],
  );
}

class UnsubmittedAdvancement {
  final List<AffinityChange> affinityChanges;
  final List<SkillChange> skillChanges;
  final List<EssenceChange> essenceChanges;
  // Future: essenceChanges, etc.

  UnsubmittedAdvancement({
    this.affinityChanges = const [],
    this.skillChanges = const [],
    this.essenceChanges = const [],
  });

  Map<String, dynamic> toJson() => {
    'affinityChanges': affinityChanges.map((change) => change.toJson()).toList(),
    'skillChanges': skillChanges.map((change) => change.toJson()).toList(),
    'essenceChanges': essenceChanges.map((change) => change.toJson()).toList(),
  };

  factory UnsubmittedAdvancement.fromJson(Map<String, dynamic> json) => UnsubmittedAdvancement(
    affinityChanges: (json['affinityChanges'] as List<dynamic>?)
        ?.map((change) => AffinityChange.fromJson(change))
        .toList() ?? [],
    skillChanges: (json['skillChanges'] as List<dynamic>?)
        ?.map((change) => SkillChange.fromJson(change))
        .toList() ?? [],
    essenceChanges: (json['essenceChanges'] as List<dynamic>?)
        ?.map((change) => EssenceChange.fromJson(change))
        .toList() ?? [],
  );
}


Character? cachedCharacter;


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    await RulesService.fetchAndCacheRules();
    print('✅ rules.json successfully cached.');
  } catch (e) {
    print('❌ Error caching rules.json: $e');
  }

  runApp(const CrucibleHelperApp());
}

class CrucibleHelperApp extends StatelessWidget {
  const CrucibleHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crucible Helper',
      theme: ThemeData.dark(),
      home: LoginPage(), // Start at the login page
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Character? character;

  @override
  void initState() {
    super.initState();
    fetchCharacter();
  }

  Future<void> fetchCharacter() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      if (email == null) {
        throw Exception("User email is null");
      }

      final ref = FirebaseStorage.instance.ref().child('users/$email/pc.json');
      final data = await ref.getData();
      if (data != null) {
        final jsonString = utf8.decode(data);
        final jsonMap = json.decode(jsonString);
        setState(() {
          character = Character.fromJson(jsonMap);
        });
      }
    } catch (e) {
      print('Error fetching character JSON: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage()));
            },
            tooltip: 'Profile',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double screenHeight = constraints.maxHeight;
                    double logoSize = screenHeight * 0.25; // 25% of the screen height

                    if (logoSize > 200) {
                      logoSize = 200; // Cap it at 200px so it doesn't get too big
                    }

                    return Image.asset(
                      'assets/logo.png',
                      height: logoSize,
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _HomeButton(
                    icon: Icons.person,
                    label: 'Character',
                    onPressed: () {
                      if (character != null) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CharacterSheetPage(character: character!),
                        ));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Character data not loaded yet')),
                        );
                      }
                    },
                  ),
                  _HomeButton(
                    icon: Icons.qr_code,
                    label: 'Cores',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MonsterCoresPage()));
                    },
                  ),
                  _HomeButton(
                    icon: Icons.timer,
                    label: 'Death',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DeathTimerPage()));
                    },
                  ),
                  _HomeButton(
                    icon: Icons.calendar_today,
                    label: 'Events',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => EventsPage()));
                    },
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _HomeButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: Colors.grey[800],
          onPressed: onPressed,
          child: Icon(icon, size: 28),
        ),
        SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12))
      ],
    );
  }
}

class CharacterSheetPage extends StatefulWidget {
  final Character character;
  const CharacterSheetPage({super.key, required this.character});

  @override
  State<CharacterSheetPage> createState() => _CharacterSheetPageState();
}

class _CharacterSheetPageState extends State<CharacterSheetPage> {
  late int currentHP;
  String _selectedSkillSort = 'Frequency';
  final List<String> _skillSortOptions = ['Alphabetical', 'Type', 'Frequency'];
  Map<String, dynamic>? rulesJson;
  bool _isEditMode = false;
  
  // Track unspent points for edit mode
  int _originalUnspentAffinityPoints = 0;
  int _originalUnspentBuildPoints = 0;
  int _currentUnspentAffinityPoints = 0;
  int _currentUnspentBuildPoints = 0;
  
  // Track unsubmitted advancement changes
  UnsubmittedAdvancement? _unsubmittedAdvancement;
  bool _hasUnsubmittedChanges = false;

  @override
  void initState() {
    super.initState();
    currentHP = widget.character.hitPoints['total'];
    _loadSkillSortPreference();
    _loadUnsubmittedAdvancement();

    RulesService.loadCachedRules().then((cached) {
      if (cached == null) {
        print('⚠️ No cached rules. Trying to download...');
        RulesService.fetchAndCacheRules().then((_) {
          RulesService.loadCachedRules().then((downloaded) {
            if (downloaded != null) {
              setState(() {
                rulesJson = json.decode(downloaded);
              });
            } else {
              print('❌ Still failed to load rules.json');
            }
          });
        });
      } else {
        setState(() {
          rulesJson = json.decode(cached);
        });
      }
    });

  }

  // SharedPreferences functions for unsubmitted advancement
  Future<void> _loadUnsubmittedAdvancement() async {
    final prefs = await SharedPreferences.getInstance();
    final advancementJson = prefs.getString('unsubmitted_advancement');
    if (advancementJson != null) {
      try {
        final advancement = UnsubmittedAdvancement.fromJson(json.decode(advancementJson));
        setState(() {
          _unsubmittedAdvancement = advancement;
          _hasUnsubmittedChanges = advancement.affinityChanges.isNotEmpty || advancement.skillChanges.isNotEmpty || advancement.essenceChanges.isNotEmpty;
        });
      } catch (e) {
        print('Error loading unsubmitted advancement: $e');
      }
    }
  }

  Future<void> _saveUnsubmittedAdvancement(UnsubmittedAdvancement advancement) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unsubmitted_advancement', json.encode(advancement.toJson()));
    setState(() {
      _unsubmittedAdvancement = advancement;
      _hasUnsubmittedChanges = advancement.affinityChanges.isNotEmpty || advancement.skillChanges.isNotEmpty || advancement.essenceChanges.isNotEmpty;
    });
  }

  Future<void> _addAffinityChange(AffinityChange change) async {
    final currentAdvancement = _unsubmittedAdvancement ?? UnsubmittedAdvancement();
    final updatedAdvancement = UnsubmittedAdvancement(
      affinityChanges: [...currentAdvancement.affinityChanges, change],
      skillChanges: currentAdvancement.skillChanges,
      essenceChanges: currentAdvancement.essenceChanges,
    );
    await _saveUnsubmittedAdvancement(updatedAdvancement);
  }

  Future<void> _addSkillChange(SkillChange change) async {
    final currentAdvancement = _unsubmittedAdvancement ?? UnsubmittedAdvancement();
    final updatedAdvancement = UnsubmittedAdvancement(
      affinityChanges: currentAdvancement.affinityChanges,
      skillChanges: [...currentAdvancement.skillChanges, change],
      essenceChanges: currentAdvancement.essenceChanges,
    );
    await _saveUnsubmittedAdvancement(updatedAdvancement);
  }

  Future<void> _addEssenceChange(EssenceChange change) async {
    final currentAdvancement = _unsubmittedAdvancement ?? UnsubmittedAdvancement();
    final updatedAdvancement = UnsubmittedAdvancement(
      affinityChanges: currentAdvancement.affinityChanges,
      skillChanges: currentAdvancement.skillChanges,
      essenceChanges: [...currentAdvancement.essenceChanges, change],
    );
    await _saveUnsubmittedAdvancement(updatedAdvancement);
  }

  Future<void> _clearUnsubmittedAdvancement() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('unsubmitted_advancement');
    setState(() {
      _unsubmittedAdvancement = null;
      _hasUnsubmittedChanges = false;
    });
  }

  // Calculate skill cost based on the formula
  int calculateSkillCost(int baseCost, int level) {
    if (level <= 0) return 0;
    if (baseCost <= 0) return 0; // Handle skills with 0 base cost
    
    int totalCost = baseCost;
    
    for (int i = 2; i <= level; i++) {
      totalCost += (baseCost - (i - 1)).clamp(1, baseCost);
    }
    
    return totalCost;
  }

  // Get all affinities including unsubmitted ones in edit mode
  Map<String, AffinityDetail> _getAllAffinities() {
    final affinities = Map<String, AffinityDetail>.from(widget.character.affinities);
    
    if (_isEditMode && _unsubmittedAdvancement != null) {
      // Group unsubmitted changes by affinity name
      final unsubmittedAffinities = <String, Map<String, int>>{};
      
      for (final change in _unsubmittedAdvancement!.affinityChanges) {
        final tierMatch = RegExp(r'Bought in (.+)').firstMatch(change.adjustment);
        if (tierMatch != null) {
          final tier = tierMatch.group(1)!;
          unsubmittedAffinities.putIfAbsent(change.affinityName, () => {});
          unsubmittedAffinities[change.affinityName]![tier] = 
              (unsubmittedAffinities[change.affinityName]![tier] ?? 0) + change.levelChange;
        }
      }
      
      // Add or update affinities with unsubmitted changes
      for (final entry in unsubmittedAffinities.entries) {
        final affinityName = entry.key;
        final tierChanges = entry.value;
        
        if (affinities.containsKey(affinityName)) {
          // Update existing affinity
          final existingAffinity = affinities[affinityName]!;
          final updatedTiers = Map<String, int>.from(existingAffinity.tiers);
          
          for (final tierChange in tierChanges.entries) {
            final tier = tierChange.key;
            final change = tierChange.value;
            updatedTiers[tier] = (updatedTiers[tier] ?? 0) + change;
          }
          
          affinities[affinityName] = AffinityDetail(
            effectLevel: existingAffinity.effectLevel + tierChanges.values.fold(0, (sum, change) => sum + change),
            tiers: updatedTiers,
          );
        } else {
          // Create new affinity
          affinities[affinityName] = AffinityDetail(
            effectLevel: tierChanges.values.fold(0, (sum, change) => sum + change),
            tiers: tierChanges,
          );
        }
      }
    }
    
    return affinities;
  }

  // Get all skills including unsubmitted ones in edit mode
  List<Skill> _getAllSkills() {
    final skills = List<Skill>.from(widget.character.skills);
    
    if (_isEditMode && _unsubmittedAdvancement != null) {
      // Group unsubmitted changes by skill name
      final unsubmittedSkills = <String, int>{};
      final skillTypes = <String, String>{};
      
      for (final change in _unsubmittedAdvancement!.skillChanges) {
        unsubmittedSkills[change.skillName] = 
            (unsubmittedSkills[change.skillName] ?? 0) + change.levelChange;
        skillTypes[change.skillName] = change.skillType;
      }
      
      // Update skills with unsubmitted changes
      for (int i = 0; i < skills.length; i++) {
        final skill = skills[i];
        if (unsubmittedSkills.containsKey(skill.name)) {
          final levelChange = unsubmittedSkills[skill.name]!;
          skills[i] = Skill(
            name: skill.name,
            type: skill.type,
            level: skill.level + levelChange,
            frequency: skill.frequency,
            delivery: skill.delivery,
            verbal: skill.verbal,
            description: skill.description,
          );
        }
      }
      
      // Add completely new skills from unsubmitted advancement
      final originalSkillNames = widget.character.skills.map((s) => s.name).toSet();
      for (final entry in unsubmittedSkills.entries) {
        if (!originalSkillNames.contains(entry.key)) {
          // This is a completely new skill - start at level 0
          skills.add(Skill(
            name: entry.key,
            type: skillTypes[entry.key] ?? 'Unknown',
            level: 0, // Start at level 0 for new skills
            frequency: 'At Will', // Default, will be updated when skill details are loaded
            delivery: 'None',
            verbal: '',
            description: '',
          ));
        }
      }
    }
    
    return skills;
  }

  // Get total build cost from unsubmitted skill changes
  int _getUnsubmittedBuildCost() {
    if (_unsubmittedAdvancement == null) return 0;
    
    int totalCost = 0;
    for (final change in _unsubmittedAdvancement!.skillChanges) {
      totalCost += change.cost;
    }
    return totalCost;
  }

  // Get completely new skills from unsubmitted advancement
  List<Skill> _getNewSkillsFromUnsubmitted() {
    if (_unsubmittedAdvancement == null) return [];
    
    final newSkills = <Skill>[];
    final originalSkillNames = widget.character.skills.map((s) => s.name).toSet();
    
    // Group unsubmitted changes by skill name
    final unsubmittedSkills = <String, int>{};
    final skillTypes = <String, String>{};
    for (final change in _unsubmittedAdvancement!.skillChanges) {
      unsubmittedSkills[change.skillName] = 
          (unsubmittedSkills[change.skillName] ?? 0) + change.levelChange;
      skillTypes[change.skillName] = change.skillType;
    }
    
    // Find skills that don't exist in original character skills
    for (final entry in unsubmittedSkills.entries) {
      if (!originalSkillNames.contains(entry.key)) {
        // Create skill with type from unsubmitted advancement
        newSkills.add(Skill(
          name: entry.key,
          type: skillTypes[entry.key] ?? 'Unknown',
          level: entry.value,
          frequency: 'At Will', // Default, will be updated when skill details are loaded
          delivery: 'None',
          verbal: '',
          description: '',
        ));
      }
    }
    
    return newSkills;
  }

  void _showAvailableAffinities(BuildContext context) async {
    // Get available affinities from rules
    List<Map<String, dynamic>> availableAffinities = [];
    
    try {
      final cachedRules = await RulesService.loadCachedRules();
      if (cachedRules != null) {
        final rules = json.decode(cachedRules);
        final affinities = rules['Affinity'] as List<dynamic>? ?? [];
        
        // Filter out unique affinities (for now, include all non-unique)
        for (final affinity in affinities) {
          if (affinity['Unique'] != true) {
            availableAffinities.add({
              'name': affinity['Name'],
            });
          }
        }
      }
    } catch (e) {
      print('Error loading available affinities: $e');
    }

    // Filter out affinities the character already has
    final existingAffinityNames = widget.character.affinities.keys.toSet();
    availableAffinities = availableAffinities.where((affinity) => 
      !existingAffinityNames.contains(affinity['name'])
    ).toList();

    if (availableAffinities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No new affinities available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Available Affinities'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: availableAffinities.length,
            itemBuilder: (context, index) {
              final affinity = availableAffinities[index];
              return ListTile(
                title: Text(affinity['name']),
                onTap: () {
                  Navigator.pop(context);
                  _addNewAffinity(context, affinity['name']);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _addNewAffinity(BuildContext context, String affinityName) {
    // Create a new affinity with 0 levels in all tiers
    final newAffinity = AffinityDetail(
      effectLevel: 0,
      tiers: {},
    );

    // Update the character's affinities (temporary until we implement proper state management)
    final updatedAffinities = Map<String, AffinityDetail>.from(widget.character.affinities);
    updatedAffinities[affinityName] = newAffinity;

    final updatedCharacter = Character(
      playerName: widget.character.playerName,
      characterName: widget.character.characterName,
      characterNumber: widget.character.characterNumber,
      race: widget.character.race,
      build: widget.character.build,
      affinityPoints: widget.character.affinityPoints,
      hitPoints: widget.character.hitPoints,
      dr: widget.character.dr,
      cultivationTier: widget.character.cultivationTier,
      skills: widget.character.skills,
      affinities: updatedAffinities,
    );

    // Update the widget's character (temporary until we implement proper state management)
    setState(() {
      // This is a temporary solution - in a real app, you'd update the character data properly
      // For now, we'll just show the affinity details dialog
    });

    // Open affinity details dialog for the new affinity
    _showAffinityDetails(
      context,
      affinityName,
      newAffinity,
      availableAffinityPoints: _currentUnspentAffinityPoints,
      onAffinityPointsChanged: (newPoints) {
        setState(() {
          _currentUnspentAffinityPoints = newPoints;
        });
      },
    );
  }

  void _showUnsubmittedChanges(BuildContext context) {
    if (_unsubmittedAdvancement == null) return;

    final buffer = StringBuffer();

    int totalAPCost = 0;
    int totalBuildCost = 0;

    if (_unsubmittedAdvancement!.affinityChanges.isNotEmpty) {
      buffer.writeln('Affinity Changes:');
      for (final change in _unsubmittedAdvancement!.affinityChanges) {
        buffer.writeln('  • ${change.affinityName}: ${change.adjustment} (${change.levelChange > 0 ? '+' : ''}${change.levelChange}) - ${change.cost} AP');
        totalAPCost += change.cost;
      }
      buffer.writeln('');
    }

    if (_unsubmittedAdvancement!.skillChanges.isNotEmpty) {
      buffer.writeln('Skill Changes:');
      for (final change in _unsubmittedAdvancement!.skillChanges) {
        buffer.writeln('  • ${change.skillName} (${change.skillType}): ${change.levelChange > 0 ? '+' : ''}${change.levelChange} - ${change.cost} build');
        totalBuildCost += change.cost;
      }
      buffer.writeln('');
    }

    if (_unsubmittedAdvancement!.essenceChanges.isNotEmpty) {
      buffer.writeln('Essence Changes:');
      for (final change in _unsubmittedAdvancement!.essenceChanges) {
        buffer.writeln('  • Direct Buy: ${change.essenceAdjustment > 0 ? '+' : ''}${change.essenceAdjustment} essence - ${change.cost} build');
        totalBuildCost += change.cost;
      }
      buffer.writeln('');
    }

    // Add cost totals
    if (totalAPCost > 0 || totalBuildCost > 0) {
      buffer.writeln('Total Costs:');
      if (totalAPCost > 0) {
        buffer.writeln('  • AP: $totalAPCost');
      }
      if (totalBuildCost > 0) {
        buffer.writeln('  • Build: $totalBuildCost');
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Unsubmitted Advancement'),
        content: SingleChildScrollView(
          child: Text(buffer.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          if (_unsubmittedAdvancement != null && 
              (_unsubmittedAdvancement!.affinityChanges.isNotEmpty || 
               _unsubmittedAdvancement!.skillChanges.isNotEmpty ||
               _unsubmittedAdvancement!.essenceChanges.isNotEmpty))
            TextButton(
              onPressed: () async {
                await _clearUnsubmittedAdvancement();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Unsubmitted advancement cleared'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              child: Text('Clear'),
            ),
        ],
      ),
    );
  }

  Future<void> _loadSkillSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSort = prefs.getString('skill_sorting');
    if (savedSort != null && _skillSortOptions.contains(savedSort)) {
      setState(() {
        _selectedSkillSort = savedSort;
      });
    }
  }

  int _getDRForTier(String tier) {
    final key = 'dr${tier[0].toUpperCase()}${tier.substring(1).toLowerCase()}';
    final raw = widget.character.dr[key] ?? 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }


  void _showHitPointInfo() {
    final hp = widget.character.hitPoints;
    final buffer = StringBuffer();

    buffer.writeln('Base: ${hp['base']}');
    buffer.writeln('Extra: ${hp['extra']}');

    const tiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    int bodyTotal = 0;
    final tierDetails = <String>[];

    for (final tier in tiers) {
      final key = 'body$tier';
      final dynamic raw = hp[key] ?? 0;
      final int value = raw is int ? raw : (raw as num).toInt();

      if (value > 0) {
        bodyTotal += value;
        tierDetails.add('  • $tier: $value');
      }
    }

    if (bodyTotal > 0) {
      buffer.writeln('Body Total: $bodyTotal');
      tierDetails.forEach(buffer.writeln);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('How Hit Points Are Calculated'),
        content: Text(buffer.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _editCurrentHP() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        int temp = currentHP;
        int tempExtra = widget.character.hitPoints['extra'] ?? 0;
        final maxHP = widget.character.hitPoints['total'];
        final maxDirectBuy = _getMaxDirectBuyForTier(widget.character.cultivationTier);
        final bodyEssence = _getBodyEssenceTotal();
        final bodyEssenceBreakdown = _getBodyEssenceBreakdown();

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Essence Details'),
              content: SizedBox(
                width: 500,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // HP Display with bigger font
                    Text(
                      '$temp / $maxHP',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    
                    // Slider with arrows
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back),
                          onPressed: () {
                            if (temp > 0) {
                              setState(() => temp--);
                            }
                          },
                        ),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: maxHP.toDouble(),
                            divisions: maxHP,
                            value: temp.toDouble(),
                            label: "$temp",
                            onChanged: (value) {
                              setState(() => temp = value.round());
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_forward),
                          onPressed: () {
                            if (temp < maxHP) {
                              setState(() => temp++);
                            }
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    
                    // Cost Breakdown
                    Text('Cost Breakdown:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    
                    // Direct Buy Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isEditMode)
                          IconButton(
                            icon: Icon(Icons.remove, color: Colors.amber, size: 16),
                            onPressed: () {
                              final originalExtra = widget.character.hitPoints['extra'] ?? 0;
                              if (tempExtra > originalExtra) {
                                setState(() => tempExtra--);
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                        SizedBox(width: 8),
                        Text('Direct Buy: $tempExtra', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 8),
                        if (_isEditMode)
                          IconButton(
                            icon: Icon(Icons.add, color: Colors.amber, size: 16),
                            onPressed: () {
                              if (tempExtra < maxDirectBuy) {
                                setState(() => tempExtra++);
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                      ],
                    ),
                    Text('Cost: ${tempExtra * 2} build points (2 per essence)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Max Direct Buy: $maxDirectBuy essence per tier', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    SizedBox(height: 8),
                    
                    // Body Essence Section
                    Text('Essence from Body: $bodyEssence', style: TextStyle(fontSize: 14)),
                    if (bodyEssenceBreakdown.isNotEmpty) ...[
                      SizedBox(height: 4),
                      ...bodyEssenceBreakdown.map((breakdown) => 
                        Text(breakdown, style: TextStyle(fontSize: 12, color: Colors.grey))
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (_isEditMode)
                  TextButton(
                    onPressed: () async {
                      // Calculate essence adjustment
                      final originalExtra = widget.character.hitPoints['extra'] ?? 0;
                      final essenceAdjustment = tempExtra - originalExtra;
                      
                      if (essenceAdjustment != 0) {
                        // Calculate cost
                        final cost = essenceAdjustment * 2;
                        
                        // Add essence change to unsubmitted advancement
                        final essenceChange = EssenceChange(
                          timestamp: DateTime.now().toIso8601String(),
                          essenceAdjustment: essenceAdjustment.toInt(),
                          cost: cost.toInt(),
                        );
                        
                        await _addEssenceChange(essenceChange);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Essence advancement saved for submission'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      
                      Navigator.pop(context);
                    },
                    child: Text('Submit'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, temp),
                  child: Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result != currentHP) {
      setState(() {
        currentHP = result;
      });

      if (currentHP == 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Current HP is 0. Start death timer?'),
        ));
      }
    }
  }

  // Helper methods for essence calculations
  int _getMaxDirectBuyForTier(String tier) {
    const tierMultipliers = {
      'Iron': 1,
      'Silver': 2,
      'Gold': 3,
      'Jade': 4,
      'Saint': 5,
      'Sovereign': 6,
    };
    return 5 * (tierMultipliers[tier] ?? 1);
  }

  int _getBodyEssenceTotal() {
    final hp = widget.character.hitPoints;
    int total = 0;
    
    const tiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    for (final tier in tiers) {
      final key = 'body$tier';
      final dynamic raw = hp[key] ?? 0;
      final int value = raw is int ? raw : (raw as num).toInt();
      total += value;
    }
    
    return total;
  }

  List<String> _getBodyEssenceBreakdown() {
    final hp = widget.character.hitPoints;
    final breakdown = <String>[];
    
    const tiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    for (final tier in tiers) {
      final key = 'body$tier';
      final dynamic raw = hp[key] ?? 0;
      final int value = raw is int ? raw : (raw as num).toInt();
      
      if (value > 0) {
        breakdown.add('  • $tier: $value');
      }
    }
    
    return breakdown;
  }

  void _showBuildInfo(BuildContext context) {
    final build = widget.character.build;
    final double dialogHeight = MediaQuery.of(context).size.height * 0.65;

    final headerStyle = TextStyle(fontWeight: FontWeight.bold);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Build Total Details'),
        content: SizedBox(
          height: dialogHeight,
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Build Total: ${build.total}'),
              Text('Unspent Build: ${build.unspent}'),
              Text('Need to Ascend: ${build.needToAscend}'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                      1: FixedColumnWidth(64),
                      2: FlexColumnWidth(),
                    },
                    border: TableBorder.all(color: Colors.grey),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey[800]),
                        children: [
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Date', style: headerStyle),
                          ),
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Build', style: headerStyle),
                          ),
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Reason', style: headerStyle),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text(build.starting.date),
                          ),
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('${build.starting.amount}'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Starting Build'),
                          ),
                        ],
                      ),
                      ...build.gains.map((gain) {
                        return TableRow(
                          children: [
                            Padding(
                              padding: EdgeInsets.all(6),
                              child: Text(gain.date),
                            ),
                            Padding(
                              padding: EdgeInsets.all(6),
                              child: Text('${gain.amount}'),
                            ),
                            Padding(
                              padding: EdgeInsets.all(6),
                              child: Text('${gain.reason}${gain.note.isNotEmpty ? ' - ${gain.note}' : ''}'),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          )
        ],
      ),
    );
  }

  void _showDRInfo() {
    const tiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    final dr = widget.character.dr;
    final buffer = StringBuffer();

    for (final tier in tiers) {
      final value = dr['dr$tier'] ?? 0;
      buffer.writeln('• $tier: $value');
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Damage Resistance (DR) Breakdown'),
        content: Text(buffer.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAffinityDetails(BuildContext context, String name, AffinityDetail detail, {int? availableAffinityPoints, Function(int)? onAffinityPointsChanged}) async {
    // Get affinity multiplier from rules
    double affinityMultiplier = 1.0;
    try {
      final cachedRules = await RulesService.loadCachedRules();
      if (cachedRules != null) {
        final rules = json.decode(cachedRules);
        final affinities = rules['Affinity'] as List<dynamic>? ?? [];
        final affinity = affinities.firstWhere(
          (a) => a['Name'] == name,
          orElse: () => null,
        );
        if (affinity != null) {
          affinityMultiplier = (affinity['Multiplier'] ?? 1.0).toDouble();
        }
      }
    } catch (e) {
      print('Error loading affinity multiplier: $e');
    }

    // Calculate effective levels for each tier
    final currentTier = widget.character.cultivationTier;
    final tiers = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    final currentTierIndex = tiers.indexOf(currentTier);
    
    // Calculate effective levels (total levels - 2 for each tier above Iron)
    final effectiveLevels = <String, int>{};
    for (int i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      final tierAdjustment = i * 2; // -2 for each tier above Iron
      effectiveLevels[tier] = detail.effectLevel - tierAdjustment;
    }
    
    // Calculate ascension adjustments
    final ascensionAdjustments = <String, int>{};
    for (int i = 1; i <= currentTierIndex; i++) { // Start from Silver (index 1)
      final tier = tiers[i];
      ascensionAdjustments[tier] = -2;
    }

    // Helper function to calculate cost
    int calculateCost(int level) {
      if (level <= 0) return 0;
      final baseCost = (level * (level + 1)) / 2;
      return (baseCost * affinityMultiplier).round();
    }

    // Create a copy of the tiers map for editing
    Map<String, int> editableTiers = Map<String, int>.from(detail.tiers);
    int currentTierLevel = editableTiers[currentTier] ?? 0;
    
    // Track current available affinity points within the dialog
    int currentAvailablePoints = availableAffinityPoints ?? 0;
    
    // Load and apply unsubmitted changes for this affinity
    if (_isEditMode && _unsubmittedAdvancement != null) {
      for (final change in _unsubmittedAdvancement!.affinityChanges) {
        if (change.affinityName == name) {
          // Extract tier from adjustment (e.g., "Bought in Gold" -> "Gold")
          final tierMatch = RegExp(r'Bought in (.+)').firstMatch(change.adjustment);
          if (tierMatch != null) {
            final tier = tierMatch.group(1)!;
            final currentLevel = editableTiers[tier] ?? 0;
            editableTiers[tier] = currentLevel + change.levelChange;
          }
        }
      }
      
      // Calculate total cost of existing unsubmitted changes for this affinity
      int existingCost = 0;
      for (final change in _unsubmittedAdvancement!.affinityChanges) {
        if (change.affinityName == name) {
          existingCost += change.cost;
        }
      }
      currentAvailablePoints += existingCost; // Add back the cost since we're starting fresh
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
        title: Text('$name Affinity Details'),
        contentPadding: EdgeInsets.all(24),
        content: SizedBox(
          width: 500, // Make dialog wider
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Effective Level
              Text(
                'Effective Level',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              
              // Current tier
              Padding(
                padding: EdgeInsets.only(left: 16, top: 2),
                child: Text(
                  '$currentTier: ${detail.effectLevel}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              
              // Tiers below current (add 2 for each tier below)
              ...tiers.take(currentTierIndex).map((tier) {
                final levelsBelow = currentTierIndex - tiers.indexOf(tier);
                final adjustedLevel = detail.effectLevel + (levelsBelow * 2);
                return Padding(
                  padding: EdgeInsets.only(left: 16, top: 2),
                  child: Text(
                    '$tier: $adjustedLevel',
                    style: TextStyle(fontSize: 12),
                  ),
                );
              }),
              SizedBox(height: 16),
              
              // Purchases table
              Text(
                'Purchases by Tier:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Table(
                  border: TableBorder.all(color: Colors.grey),
                  columnWidths: {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey[800]),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Adjustment', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Level', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Cost', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                    ...tiers.take(currentTierIndex + 1).map((tier) {
                      final level = editableTiers[tier] ?? 0;
                      final cost = calculateCost(level);
                      final isCurrentTier = tier == currentTier;
                      return TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Bought in $tier'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: _isEditMode && isCurrentTier
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.remove, color: Colors.amber, size: 16),
                                        onPressed: () {
                                          // Don't allow going below current tier level
                                          if (level > currentTierLevel) {
                                            // Calculate cost difference (current level cost - previous level cost)
                                            final currentLevelCost = calculateCost(level);
                                            final previousLevelCost = calculateCost(level - 1);
                                            final costDifference = currentLevelCost - previousLevelCost;
                                            
                                            setState(() {
                                              editableTiers[tier] = level - 1;
                                              currentAvailablePoints += costDifference;
                                            });
                                            // Update the available points in the parent widget
                                            if (onAffinityPointsChanged != null) {
                                              onAffinityPointsChanged(currentAvailablePoints);
                                            }
                                          }
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(),
                                      ),
                                      SizedBox(width: 8),
                                      Text('$level', textAlign: TextAlign.center),
                                      SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(Icons.add, color: Colors.amber, size: 16),
                                                                                onPressed: () {
                                          // Don't allow going above 6 levels
                                          if (level < 6) {
                                            // Calculate cost difference (new level cost - current level cost)
                                            final currentLevelCost = calculateCost(level);
                                            final nextLevelCost = calculateCost(level + 1);
                                            final costDifference = nextLevelCost - currentLevelCost;
                                            
                                            // Check if we have enough affinity points for the difference
                                            if (currentAvailablePoints >= costDifference) {
                                              setState(() {
                                                editableTiers[tier] = level + 1;
                                                currentAvailablePoints -= costDifference;
                                              });
                                              // Update the available points in the parent widget
                                              if (onAffinityPointsChanged != null) {
                                                onAffinityPointsChanged(currentAvailablePoints);
                                              }
                                            } else {
                                              // Show error message
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Not enough affinity points! Need $costDifference, have $currentAvailablePoints'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(),
                                      ),
                                    ],
                                  )
                                : Text('$level', textAlign: TextAlign.center),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('$cost', textAlign: TextAlign.right),
                          ),
                        ],
                      );
                    }),
                    ...ascensionAdjustments.entries.map((entry) {
                      return TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('${entry.key} Ascension'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('${entry.value}', textAlign: TextAlign.center),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('-', textAlign: TextAlign.right),
                          ),
                        ],
                      );
                    }),
                    // Calculate totals
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey[700]),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            '${tiers.take(currentTierIndex + 1).map((tier) => editableTiers[tier] ?? 0).fold(0, (sum, value) => sum + value) + ascensionAdjustments.values.fold(0, (sum, value) => sum + value)}',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            '${tiers.take(currentTierIndex + 1).map((tier) => calculateCost(editableTiers[tier] ?? 0)).fold(0, (sum, value) => sum + value)}',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                        ),
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
          if (_isEditMode)
            TextButton(
              onPressed: () async {
                // Remove existing unsubmitted changes for this affinity
                if (_unsubmittedAdvancement != null) {
                  final filteredChanges = _unsubmittedAdvancement!.affinityChanges
                      .where((change) => change.affinityName != name)
                      .toList();
                  
                  if (filteredChanges.length != _unsubmittedAdvancement!.affinityChanges.length) {
                    await _saveUnsubmittedAdvancement(UnsubmittedAdvancement(
                      affinityChanges: filteredChanges,
                    ));
                  }
                }
                
                // Collect all changes made to the affinity
                final changes = <AffinityChange>[];
                final originalTiers = detail.tiers;
                
                for (final entry in editableTiers.entries) {
                  final tier = entry.key;
                  final newLevel = entry.value;
                  final originalLevel = originalTiers[tier] ?? 0;
                  final levelChange = newLevel - originalLevel;
                  
                  if (levelChange != 0) {
                    // Calculate the cost difference
                    final originalCost = calculateCost(originalLevel);
                    final newCost = calculateCost(newLevel);
                    final costDifference = newCost - originalCost;
                    
                    changes.add(AffinityChange(
                      timestamp: DateTime.now().toIso8601String(),
                      affinityName: name,
                      adjustment: 'Bought in $tier',
                      cost: costDifference,
                      levelChange: levelChange,
                    ));
                  }
                }
                
                // Store the changes
                if (changes.isNotEmpty) {
                  for (final change in changes) {
                    await _addAffinityChange(change);
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${changes.length} affinity change(s) saved for submission'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                
                Navigator.pop(context);
              },
              child: Text('Submit'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          )
        ],
        ),
      ),
    );
  }

  void _showAffinityPointInfo(BuildContext context) {
    final points = widget.character.affinityPoints;
    final buffer = StringBuffer()
      ..writeln('Affinity Points Total: ${points['affinityPointsTotal']}')
      ..writeln('Affinity Points Max: ${points['affinityPointsMax']}')
      ..writeln('Unspent Affinity Points: ${points['affinityPointUnspend']}')
      ..writeln('')
      ..writeln('Tier Points Total: ${points['affinityTierPointsTotal']}')
      ..writeln('Tier Points Max: ${points['affinityTierPointsMax']}')
      ..writeln('Unspent Tier Points: ${points['affinityTierPointUnspend']}')
      ..writeln('Unslotted Tier Points: ${points['affinityTierPointsUnslotted']}');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Affinity Point Details'),
        content: SingleChildScrollView(child: Text(buffer.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSkillDetails(BuildContext context, Skill skill, {Function(int)? onBuildPointsChanged}) async {
    final details = await getSkillDetailsFromRules(skill.name, skill.type, widget.character.race);
    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No details found for ${skill.name}')),
      );
      return;
    }

    final delivery = skill.delivery ?? details['Delivery'] ?? details['delivery'] ?? 'None';
    final verbal = skill.verbal ?? details['verbal'] ?? '';
    final rules = skill.description ?? details['rules'] ?? '';
    
    // Get base cost from rules for affinity skills
    int baseCost = 1; // Default fallback
    int maxLevel = 6; // Default max level
    if (skill.type != 'Common' && skill.type != widget.character.race) {
      try {
        final cachedRules = await RulesService.loadCachedRules();
        if (cachedRules != null) {
          final rules = json.decode(cachedRules);
          
          // First try to get from Affinity Skills
          final affinitySkills = rules['Affinity Skills'] as List<dynamic>? ?? [];
          final affinitySkill = affinitySkills.firstWhere(
            (s) => s['Name'] == skill.name,
            orElse: () => null,
          );
          
          if (affinitySkill != null) {
            maxLevel = affinitySkill['Level'] ?? 6;
            baseCost = affinitySkill['Build'] ?? 1;
          } else {
            // Fallback to affinity rules for base cost
            final affinities = rules['Affinity'] as List<dynamic>? ?? [];
            final affinity = affinities.firstWhere(
              (a) => a['Name'] == skill.type,
              orElse: () => null,
            );
            if (affinity != null) {
              baseCost = affinity['Build'] ?? 1;
            }
          }
        }
      } catch (e) {
        print('Error loading affinity skill max level: $e');
      }
    } else {
      // For Common and race skills, get max level from skill details
      try {
        final cachedRules = await RulesService.loadCachedRules();
        if (cachedRules != null) {
          final rules = json.decode(cachedRules);
          final skills = rules['Skill'] as List<dynamic>? ?? [];
          final skillRule = skills.firstWhere(
            (s) => s['Name'] == skill.name,
            orElse: () => null,
          );
          if (skillRule != null) {
            maxLevel = skillRule['Level'] ?? 6;
            baseCost = skillRule['Build'] ?? 1;
          }
        }
      } catch (e) {
        print('Error loading skill max level: $e');
      }
    }
    
    List<int> calculateCost(Map<String, dynamic> details, int level) {
      if (!details.containsKey('Build') || !details.containsKey('Level')) {
        return List.filled(level, 1); // fallback
      }

      final base = details['Build'];
      final maxLevel = details['Level'];

      if (base is! int || maxLevel is! int) return List.filled(level, 1);

      return List.generate(
        level,
        (i) => (base - i).clamp(1, base), // avoid negative or zero values
      );
    }

    final cost = calculateCost(details, skill.level);
    final totalCost = cost.fold(0, (sum, c) => sum + c);

    List<bool> usesChecked = List<bool>.filled(skill.level, false);

    // Track editable skill level for edit mode
    int editableSkillLevel = skill.level;
    int currentAvailableBuildPoints = _isEditMode ? _currentUnspentBuildPoints : 0;

    // Load unsubmitted changes for this skill
    if (_isEditMode && _unsubmittedAdvancement != null) {
      for (final change in _unsubmittedAdvancement!.skillChanges) {
        if (change.skillName == skill.name) {
          editableSkillLevel += change.levelChange;
          currentAvailableBuildPoints += change.cost; // Add back the cost since we're starting fresh
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final dialogHeight = screenHeight * 0.65; // 65% of screen height

        return AlertDialog(
          titlePadding: const EdgeInsets.all(16),
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${skill.name} (${skill.type})',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${skill.frequency} • $delivery',
                style: TextStyle(fontSize: 14, color: Colors.grey[300]),
              ),
            ],
          ),
          content: SizedBox(
            height: dialogHeight,
            width: double.maxFinite,
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Uses:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    for (int i = 0; i < skill.level; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: StatefulBuilder(
                          builder: (context, setState) {
                            return Checkbox(
                              value: usesChecked[i],
                              onChanged: (val) {
                                setState(() => usesChecked[i] = val!);
                              },
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
                    length: 3,
                    initialIndex: _isEditMode ? 2 : 0, // Start on Cost tab (index 2) if in edit mode
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Verbal'),
                            Tab(text: 'Rules'),
                            Tab(text: 'Cost'),
                          ],
                          labelColor: Colors.white,
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: Text(verbal, style: TextStyle(fontSize: 16)),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: Text(rules, style: TextStyle(fontSize: 16)),
                              ),
                              _isEditMode
                                ? StatefulBuilder(
                                    builder: (context, setState) {
                                      final currentCost = calculateSkillCost(baseCost, editableSkillLevel);
                                      final nextLevelCost = calculateSkillCost(baseCost, editableSkillLevel + 1);
                                      final previousLevelCost = calculateSkillCost(baseCost, editableSkillLevel - 1);
                                      final costDifference = nextLevelCost - currentCost;
                                      final costRefund = currentCost - previousLevelCost;
                                      
                                      return Column(
                                        children: [
                                          SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                icon: Icon(Icons.remove, color: Colors.amber, size: 20),
                                                onPressed: () {
                                                  if (editableSkillLevel > skill.level) {
                                                    setState(() {
                                                      editableSkillLevel--;
                                                      currentAvailableBuildPoints += costRefund;
                                                    });
                                                    if (onBuildPointsChanged != null) {
                                                      onBuildPointsChanged(currentAvailableBuildPoints);
                                                    }
                                                  }
                                                },
                                              ),
                                              SizedBox(width: 16),
                                              Text(
                                                'Level: $editableSkillLevel',
                                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                              ),
                                              SizedBox(width: 16),
                                              IconButton(
                                                icon: Icon(Icons.add, color: Colors.amber, size: 20),
                                                onPressed: () {
                                                  if (editableSkillLevel >= maxLevel) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Cannot exceed maximum level of $maxLevel'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  } else if (currentAvailableBuildPoints >= costDifference) {
                                                    setState(() {
                                                      editableSkillLevel++;
                                                      currentAvailableBuildPoints -= costDifference;
                                                    });
                                                    if (onBuildPointsChanged != null) {
                                                      onBuildPointsChanged(currentAvailableBuildPoints);
                                                    }
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Not enough build points! Need $costDifference, have $currentAvailableBuildPoints'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            'Base Cost: $baseCost build points',
                                            style: TextStyle(fontSize: 14, color: Colors.grey),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Cost: $currentCost build points',
                                            style: TextStyle(fontSize: 16),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Available: $currentAvailableBuildPoints build points',
                                            style: TextStyle(fontSize: 14, color: Colors.grey),
                                          ),
                                        ],
                                      );
                                    },
                                  )
                                : Center(
                                    child: Text(
                                      'Skill Build Total: $totalCost (${cost.join(" + ")})',
                                      style: TextStyle(fontSize: 16),
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
            if (_isEditMode)
              TextButton(
                onPressed: () async {
                  // Calculate level change
                  final levelChange = editableSkillLevel - skill.level;
                  
                  if (levelChange != 0) {
                    // Calculate cost difference
                    final originalCost = calculateSkillCost(baseCost, skill.level);
                    final newCost = calculateSkillCost(baseCost, editableSkillLevel);
                    final costDifference = newCost - originalCost;
                    
                    // Add skill change to unsubmitted advancement
                    final skillChange = SkillChange(
                      timestamp: DateTime.now().toIso8601String(),
                      skillName: skill.name,
                      skillType: skill.type,
                      levelChange: levelChange,
                      cost: costDifference,
                    );
                    
                    await _addSkillChange(skillChange);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Skill advancement saved for submission'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  
                  Navigator.pop(context);
                },
                child: Text('Submit'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Map<String, List<Skill>> groupSkillsBy(
    List<Skill> skills,
    String sortBy,
    String characterRace,
  ) {
    Map<String, List<Skill>> grouped = {};

    if (sortBy == 'Type') {
      // Define special order for type
      final order = ['Common', characterRace]; // e.g., 'Common', 'Human'
      for (var skill in skills) {
        final key = skill.type;
        grouped.putIfAbsent(key, () => []).add(skill);
      }

      // Sort within each group
      for (var key in grouped.keys) {
        grouped[key]!.sort((a, b) => a.name.compareTo(b.name));
      }

      // Sort outer map by special order first, then alphabetically
      final sorted = Map<String, List<Skill>>.fromEntries(
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
      final frequencyOrder = [
        'Passive',
        'At Will',
        'Encounter',
        'Bell',
        'Daily',
        'Weekend'
      ];

      for (var skill in skills) {
        final freq = skill.frequency.trim();
        grouped.putIfAbsent(freq, () => []).add(skill);
      }

      for (var key in grouped.keys) {
        grouped[key]!.sort((a, b) => a.name.compareTo(b.name));
      }

      final sorted = Map<String, List<Skill>>.fromEntries(
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

    return {
      '': List.from(skills)..sort((a, b) => a.name.compareTo(b.name)),
    };
  }

  Color _getCultivationColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'iron': return Colors.grey;
      case 'silver': return Colors.white;
      case 'gold': return Colors.yellow.shade600;
      case 'jade': return Colors.green.shade400;
      case 'saint': return Colors.red;
      case 'sovereign': return Colors.purple;
      default: return Colors.blueGrey;
    }
  }

  Widget _buildInfoBox({
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onBoxTap,
    bool showPlusButton = false,
    VoidCallback? onPlusPressed,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 16)),
            IconButton(
              icon: Icon(Icons.info_outline, size: 16),
              onPressed: onTap,
              tooltip: 'More info on $label',
            ),
            if (showPlusButton && onPlusPressed != null)
              IconButton(
                icon: Icon(Icons.add, size: 16, color: Colors.amber),
                onPressed: onPlusPressed,
                tooltip: 'Add $label',
              ),
          ],
        ),
        GestureDetector(
          onTap: onBoxTap,  // 👈 support full-box tap if provided
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _StatBox({required String label, required String value, required VoidCallback onTap, bool isEditMode = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 16)),
            SizedBox(width: 4),
            GestureDetector(
              onTap: onTap,
              child: Icon(Icons.info_outline, size: 16, color: Colors.grey[300]),
            ),
          ],
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: isEditMode ? Colors.amber : Colors.white),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    if (rulesJson == null) {
    return Scaffold(
        appBar: AppBar(title: Text('My Character')),
        body: Center(child: CircularProgressIndicator()), // Loading indicator
      );
    }
    final character = widget.character;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('My Character'),
            if (_isEditMode) ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'EDIT MODE',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            if (_hasUnsubmittedChanges) ...[
              SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showUnsubmittedChanges(context),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'UNSUBMITTED ADVANCEMENT',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.save : Icons.edit),
            onPressed: () {
              setState(() {
                if (!_isEditMode) {
                  // Entering edit mode - initialize tracking variables
                  _originalUnspentAffinityPoints = widget.character.unspentAffinityPoints;
                  _originalUnspentBuildPoints = widget.character.build.unspent;
                  
                  // Calculate actual available points by subtracting unsubmitted advancement costs
                  int affinityCostFromUnsubmitted = 0;
                  int buildCostFromUnsubmitted = 0;
                  
                  if (_unsubmittedAdvancement != null) {
                    for (final change in _unsubmittedAdvancement!.affinityChanges) {
                      affinityCostFromUnsubmitted += change.cost;
                    }
                    for (final change in _unsubmittedAdvancement!.skillChanges) {
                      buildCostFromUnsubmitted += change.cost;
                    }
                    for (final change in _unsubmittedAdvancement!.essenceChanges) {
                      buildCostFromUnsubmitted += change.cost;
                    }
                  }
                  
                  _currentUnspentAffinityPoints = _originalUnspentAffinityPoints - affinityCostFromUnsubmitted;
                  _currentUnspentBuildPoints = _originalUnspentBuildPoints - buildCostFromUnsubmitted;
                } else {
                  // Exiting edit mode - save changes (TODO: implement save functionality)
                  print('Saving changes...');
                }
                _isEditMode = !_isEditMode;
              });
            },
            tooltip: _isEditMode ? 'Save Changes' : 'Edit Character',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [


            // Character Header Layout
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  character.characterName,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${character.cultivationTier} tier ${character.race}',
                  style: TextStyle(
                    fontSize: 18,
                    color: _getCultivationColor(character.cultivationTier),
                  ),
                ),
                const SizedBox(height: 16),

                // Row 1: Build + Affinity
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        label: 'Build Total',
                        value: _isEditMode 
                            ? '${character.build.total - _getUnsubmittedBuildCost()} (${_currentUnspentBuildPoints})'
                            : '${character.build.total} (${character.build.unspent})',
                        onTap: () => _showBuildInfo(context),
                        isEditMode: _isEditMode,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        label: 'Affinity Points',
                        value: _isEditMode 
                            ? '${character.totalAffinityPoints} (${_currentUnspentAffinityPoints})'
                            : '${character.totalAffinityPoints} (${character.unspentAffinityPoints})',
                        onTap: () => _showAffinityPointInfo(context),
                        isEditMode: _isEditMode,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 12),

                // Row 2: DR + Essence
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        label: 'DR',
                        value: '${_getDRForTier(character.cultivationTier)}',
                        onTap: _showDRInfo,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        label: 'Essence',
                        value: '$currentHP / ${character.hitPoints['total']}',
                        onTap: _showHitPointInfo,
                        onBoxTap: _editCurrentHP,
                        showPlusButton: _isEditMode,
                        onPlusPressed: () {
                          // TODO: Add essence editing functionality
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Essence editing coming soon!')),
                          );
                        },
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
                Row(
                  children: [
                    Text('Affinities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_isEditMode) ...[
                      SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.add, color: Colors.amber, size: 20),
                        onPressed: () {
                          _showAvailableAffinities(context);
                        },
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            LayoutBuilder(
              builder: (context, constraints) {
                final int columns = 3; // Force 3 across even on narrow screens
                final double spacing = 6.0;
                final double totalSpacing = (columns - 1) * spacing;
                final double itemWidth = (constraints.maxWidth - totalSpacing) / columns;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: (_getAllAffinities().entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key)))
                    .map((entry) {
                      final name = entry.key;
                      final detail = entry.value;

                      return Semantics(
                        label: '$name affinity, level ${detail.effectLevel}',
                        button: true,
                        child: InkWell(
                          onTap: () => _showAffinityDetails(
                            context, 
                            name, 
                            detail,
                            availableAffinityPoints: _isEditMode ? _currentUnspentAffinityPoints : null,
                            onAffinityPointsChanged: _isEditMode ? (newPoints) {
                              setState(() {
                                _currentUnspentAffinityPoints = newPoints;
                              });
                            } : null,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: 48), // 👈 Ensures minimum tap area
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
                                            '$name: ${detail.effectLevel}',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ),
                                      if (_isEditMode)
                                        IconButton(
                                          icon: Icon(Icons.add, color: Colors.amber, size: 16),
                                          onPressed: () => _showAffinityDetails(
                                            context, 
                                            name, 
                                            detail,
                                            availableAffinityPoints: _currentUnspentAffinityPoints,
                                            onAffinityPointsChanged: (newPoints) {
                                              setState(() {
                                                _currentUnspentAffinityPoints = newPoints;
                                              });
                                            },
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
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
            ),


            const Divider(height: 32),

            // Skills Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Skills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_isEditMode) ...[
                      SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.add, color: Colors.amber, size: 20),
                        onPressed: () {
                          _showAvailableAffinitiesForSkills(context);
                        },
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ],
                ),
                DropdownButton<String>(
                  value: _selectedSkillSort,
                  onChanged: (value) async {
                    setState(() {
                      _selectedSkillSort = value!;
                    });

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('skill_sorting', _selectedSkillSort);
                  },
                  items: _skillSortOptions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ],
            ),
            ...groupSkillsBy(_getAllSkills(), _selectedSkillSort, character.race).entries.expand((entry) {
              final groupName = entry.key;
              final skillList = entry.value;

              return [
                if (groupName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      groupName,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ...skillList.map((skill) {
                  final isPassiveOrAtWill = skill.frequency == 'Passive' || skill.frequency == 'At Will';
                  
                  // Check if this skill has unsubmitted changes
                  int unsubmittedLevelChange = 0;
                  bool isNewSkill = false;
                  if (_isEditMode && _unsubmittedAdvancement != null) {
                    for (final change in _unsubmittedAdvancement!.skillChanges) {
                      if (change.skillName == skill.name) {
                        unsubmittedLevelChange += change.levelChange;
                        // Check if this is a completely new skill (not in original character skills)
                        if (!widget.character.skills.any((s) => s.name == skill.name)) {
                          isNewSkill = true;
                        }
                      }
                    }
                  }
                  
                  final displayLevel = skill.level + unsubmittedLevelChange;
                  final hasUnsubmittedChanges = unsubmittedLevelChange != 0 || isNewSkill;
                  
                  return InkWell(
                    onTap: () {
                      if (_isEditMode && isPassiveOrAtWill) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Cannot increase ${skill.frequency} skills'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      } else {
                        _showSkillDetails(context, skill, onBuildPointsChanged: _isEditMode ? (newPoints) {
                          setState(() {
                            _currentUnspentBuildPoints = newPoints;
                          });
                        } : null);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                  color: hasUnsubmittedChanges ? Colors.amber : Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                                children: [
                                  TextSpan(
                                    text: skill.name,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  TextSpan(
                                    text: ' (${skill.type} • Level ',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  TextSpan(
                                    text: '$displayLevel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: hasUnsubmittedChanges ? FontWeight.bold : null,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' • ${skill.frequency})',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isEditMode && !isPassiveOrAtWill)
                            IconButton(
                              icon: Icon(Icons.add, color: Colors.amber, size: 20),
                              onPressed: () {
                                _showSkillDetails(context, skill, onBuildPointsChanged: _isEditMode ? (newPoints) {
                                  setState(() {
                                    _currentUnspentBuildPoints = newPoints;
                                  });
                                } : null);
                              },
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ];
            }),
          ],
        ),
      ),
    );
  }

  void _showAvailableAffinitiesForSkills(BuildContext context) async {
    // Get all affinities the character has (including unsubmitted ones)
    final allAffinities = _getAllAffinities();
    final availableAffinities = allAffinities.keys.toList();
    
    if (availableAffinities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No affinities available for skills')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Select Affinity for New Skill'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: availableAffinities.length,
            itemBuilder: (context, index) {
              final affinityName = availableAffinities[index];
              return ListTile(
                title: Text(affinityName),
                onTap: () {
                  Navigator.pop(context);
                  _showAvailableSkillsForAffinity(context, affinityName);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showAvailableSkillsForAffinity(BuildContext context, String affinityName) async {
    // Get available skills for this affinity
    List<Map<String, dynamic>> availableSkills = [];
    
    try {
      final cachedRules = await RulesService.loadCachedRules();
      if (cachedRules != null) {
        final rules = json.decode(cachedRules);
        final affinitySkills = rules['Affinity Skills'] as List<dynamic>? ?? [];
        
        // Filter skills for this affinity
        for (final skill in affinitySkills) {
          if (skill['Affinity'] == affinityName) {
            availableSkills.add({
              'name': skill['Name'],
              'type': affinityName,
              'frequency': skill['Frequency'] ?? 'At Will',
              'delivery': skill['Delivery'] ?? 'None',
            });
          }
        }
      }
    } catch (e) {
      print('Error loading available skills: $e');
    }

    // Filter out skills the character already has
    final existingSkillNames = _getAllSkills().map((s) => s.name).toSet();
    availableSkills = availableSkills.where((skill) => 
      !existingSkillNames.contains(skill['name'])
    ).toList();

    if (availableSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No new skills available for $affinityName')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Available Skills for $affinityName'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: availableSkills.length,
            itemBuilder: (context, index) {
              final skill = availableSkills[index];
              return ListTile(
                title: Text(skill['name']),
                subtitle: Text('${skill['frequency']} • ${skill['delivery']}'),
                onTap: () {
                  Navigator.pop(context);
                  _addNewSkill(context, skill);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _addNewSkill(BuildContext context, Map<String, dynamic> skillData) {
    // Create a new skill
    final newSkill = Skill(
      name: skillData['name'],
      type: skillData['type'],
      level: 0, // Start at level 0
      frequency: skillData['frequency'],
      delivery: skillData['delivery'],
      verbal: '',
      description: '',
    );

    // Open skill details dialog for the new skill
    _showSkillDetails(context, newSkill, onBuildPointsChanged: _isEditMode ? (newPoints) {
      setState(() {
        _currentUnspentBuildPoints = newPoints;
      });
    } : null);
  }

}

class MonsterCoresPage extends StatelessWidget {
  const MonsterCoresPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Monster Cores')),
      body: Center(child: Text('Monster Cores Coming Soon!')),
    );
  }
}



class DeathTimerPage extends StatefulWidget {
  const DeathTimerPage({super.key});

  @override
  _DeathTimerPageState createState() => _DeathTimerPageState();
}

class _DeathTimerPageState extends State<DeathTimerPage> {
  Timer? _timer;
  int _remainingSeconds = 180; // 3 minutes
  bool _isRunning = false;

  void _startTimer() {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _isRunning = false;
        }
      });
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 180;
      _isRunning = false;
    });
  }

  void _heal() {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 180;
      _isRunning = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Healed! Death count reset.'),
      duration: Duration(seconds: 2),
    ));
  }

  String _getStatusLabel() {
    if (_remainingSeconds > 120) return "Stage 1: Bleeding Out";
    if (_remainingSeconds > 0) return "Stage 2: Unconscious/Dying";
    return "Dead";
  }

  Color _getStatusColor() {
    if (_remainingSeconds > 120) return Colors.red;
    if (_remainingSeconds > 0) return Colors.purple;
    return Colors.grey;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getStatusColor(),
      appBar: AppBar(
        title: Text('Death Timer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _getStatusLabel(),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 48),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: _startTimer,
              child: Text('Start Death Timer'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _heal,
              child: Text('Healed / Life Effect Used'),
            ),
            SizedBox(height: 10),
            TextButton(
              onPressed: _resetTimer,
              child: Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  ProfilePage({super.key});

  Future<bool> fetchCharacterFromFirebase() async {
    try {
      final user = _auth.currentUser;
      final email = user?.email;
      if (email == null) return false;

      final ref = FirebaseStorage.instance.ref().child('users/$email/pc.json');
      final data = await ref.getData();

      if (data != null) {
        final jsonString = utf8.decode(data);
        final jsonMap = json.decode(jsonString);
        cachedCharacter = Character.fromJson(jsonMap);
        print('✅ Character updated');
        return true;
      }
    } catch (e) {
      print('❌ Failed to sync character: $e');
    }
    return false;
  }

  Future<void> signOut(BuildContext context) async {
    await _auth.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
    );
  }
  void checkForAppUpdate(BuildContext context) {
    final serviceWorker = html.window.navigator.serviceWorker;

    if (serviceWorker != null) {
      serviceWorker.getRegistration().then((registration) {
        registration.update(); // Ask the service worker to check for updates

        registration.addEventListener('updatefound', (event) {
          final newWorker = registration.installing;

          newWorker?.addEventListener('statechange', (stateEvent) {
            if (newWorker.state == 'installed') {
              if (html.window.navigator.serviceWorker?.controller != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Update found! Reloading...'),
                ));
                Future.delayed(Duration(seconds: 1), () {
                  html.window.location.reload();
                });
              }
            }
          });
        });

      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No Service Worker detected (not a PWA build?)'),
      ));
    }
  }


  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Signed in as ${user?.email ?? "Unknown"}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final scaffold = ScaffoldMessenger.of(context);

                // 1. Sync character
                final characterSuccess = await fetchCharacterFromFirebase();
                scaffold.showSnackBar(SnackBar(
                  content: Text(characterSuccess
                      ? '✅ Character synced'
                      : '❌ Failed to sync character'),
                ));

                // 2. Sync rules.json
                try {
                  await RulesService.fetchAndCacheRules();
                  scaffold.showSnackBar(SnackBar(
                    content: Text('✅ Rules updated'),
                  ));
                } catch (e) {
                  scaffold.showSnackBar(SnackBar(
                    content: Text('❌ Failed to fetch rules: $e'),
                  ));
                }

                // 3. Check for app update
                checkForAppUpdate(context);
              },
              child: Text('🔄 Sync Everything'),
            ),


            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => signOut(context),
              child: Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }


}
