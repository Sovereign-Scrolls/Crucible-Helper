import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'shared/rules_service.dart';



import 'models/character.dart'; 
import 'pages/login_page.dart';
import 'utils/skill_lookup.dart';


import 'dart:html' as html;

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
  const CrucibleHelperApp({Key? key}) : super(key: key);

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
                    icon: Icons.settings,
                    label: 'Profile',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage()));
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
  const CharacterSheetPage({required this.character});

  @override
  State<CharacterSheetPage> createState() => _CharacterSheetPageState();
}

class _CharacterSheetPageState extends State<CharacterSheetPage> {
  late int currentHP;
  String _selectedSkillSort = 'Alphabetical';
  final List<String> _skillSortOptions = ['Alphabetical', 'Type', 'Frequency'];
  Map<String, dynamic>? rulesJson;

  @override
  void initState() {
    super.initState();
    currentHP = widget.character.hitPoints['total'];

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

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Adjust Current HP'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    min: 0,
                    max: widget.character.hitPoints['total'].toDouble(),
                    divisions: widget.character.hitPoints['total'],
                    value: temp.toDouble(),
                    label: "$temp",
                    onChanged: (value) {
                      setState(() => temp = value.round());
                    },
                  ),
                  Text('$temp / ${widget.character.hitPoints['total']}'),
                ],
              ),
              actions: [
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

  void _showBuildInfo(BuildContext context) {
    final build = widget.character.build;
    final buffer = StringBuffer();

    buffer.writeln('Starting Build: ${build.starting.amount} (${build.starting.date})\n');

    if (build.gains.isNotEmpty) {
      buffer.writeln('Gains:');
      for (var gain in build.gains) {
        buffer.writeln('• +${gain.amount} on ${gain.date}');
        if (gain.reason.isNotEmpty) buffer.writeln('  Reason: ${gain.reason}');
        if (gain.note.isNotEmpty) buffer.writeln('  Note: ${gain.note}');
        buffer.writeln('');
      }
    }

    final calculatedTotal = build.starting.amount +
        build.gains.fold<int>(0, (sum, g) => sum + g.amount);
    buffer.writeln('Calculated Total: $calculatedTotal');
    buffer.writeln('Recorded Total: ${build.total}');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Build Total Details'),
        content: SingleChildScrollView(child: Text(buffer.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          )
        ],
      ),
    );
  }

  void _showAffinityDetails(BuildContext context, String name, AffinityDetail detail) {
    final buffer = StringBuffer();
    detail.tiers.forEach((tier, value) {
      buffer.writeln('$tier: $value');
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$name Affinity Details'),
        content: Text(buffer.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          )
        ],
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

  void _showSkillDetails(BuildContext context, Skill skill) async {
    final details = await getSkillDetailsFromRules(skill.name, skill.type);

    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No details found for ${skill.name}')),
      );
      return;
    }

    final hasVerbal = details['verbal'] != null && details['verbal']!.isNotEmpty;
    final tabs = <Tab>[Tab(text: 'Rules')];
    final views = <Widget>[
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(details['rules'] ?? 'No rules found.'),
      ),
    ];

    if (hasVerbal) {
      tabs.insert(0, Tab(text: 'Verbal'));
      views.insert(0, Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(details['verbal']!),
      ));
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(skill.name),
        content: SizedBox(
          width: double.maxFinite,
          child: DefaultTabController(
            length: tabs.length,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TabBar(
                  labelColor: Theme.of(context).colorScheme.secondary,
                  tabs: tabs,
                ),
                SizedBox(height: 150, child: TabBarView(children: views)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Skill> _sortedSkills(List<Skill> skills) {
    switch (_selectedSkillSort) {
      case 'Type':
        return List.from(skills)..sort((a, b) => a.type.compareTo(b.type));
      case 'Frequency':
        return List.from(skills)..sort((a, b) => a.frequency.compareTo(b.frequency));
      case 'Alphabetical':
      default:
        return List.from(skills)..sort((a, b) => a.name.compareTo(b.name));
    }
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
      appBar: AppBar(title: Text('My Character')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                character.characterName,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // Race / Cultivation / Build Total + HP box
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Race, Cultivation, Build
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Race: ${character.race}', style: TextStyle(fontSize: 18)),
                      Text(
                        'Cultivation: ${character.cultivationTier}',
                        style: TextStyle(
                          fontSize: 18,
                          color: _getCultivationColor(character.cultivationTier),
                        ),
                      ),
                      Row(
                        children: [
                          Text('Build Total: ${character.build.total}', style: TextStyle(fontSize: 18)),
                          SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _showBuildInfo(context),
                            child: Icon(Icons.info_outline, size: 18, color: Colors.grey[300]),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('Affinity Points: ${character.affinityPoints['affinityPointsTotal']}', style: TextStyle(fontSize: 18)),
                          SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _showAffinityPointInfo(context),
                            child: Icon(Icons.info_outline, size: 18, color: Colors.grey[300]),
                          ),
                        ],
                      ),

                    ],
                  ),
                ),

                // Right: Hit Points Box
                GestureDetector(
                  onTap: _editCurrentHP,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Hit Points', style: TextStyle(fontSize: 16)),
                          IconButton(
                            icon: Icon(Icons.info_outline, size: 16),
                            onPressed: _showHitPointInfo,
                          ),
                        ],
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$currentHP / ${character.hitPoints['total']}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 32),
            // Affinities Section
            ExpansionTile(
              title: Text('Affinities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              children: widget.character.affinities.entries.map((entry) {
                final name = entry.key;
                final detail = entry.value;

                return ListTile(
                  title: Row(
                    children: [
                      Text('$name: ${detail.effectLevel}'),
                      SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _showAffinityDetails(context, name, detail),
                        child: Icon(Icons.info_outline, size: 18, color: Colors.grey[300]),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 32),

            // Skills Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Skills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _selectedSkillSort,
                  onChanged: (value) {
                    setState(() {
                      _selectedSkillSort = value!;
                    });
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
            ListView(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              children: _sortedSkills(character.skills).map((skill) {
                return InkWell(
                  onTap: () {
                    if (rulesJson != null) {
                      _showSkillDetails(context, skill);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Rules not loaded yet.')),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white, decoration: TextDecoration.none),
                        children: [
                          TextSpan(
                            text: skill.name,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          TextSpan(
                            text: ' (${skill.type} • Level ${skill.level} • ${skill.frequency})',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class MonsterCoresPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Monster Cores')),
      body: Center(child: Text('Monster Cores Coming Soon!')),
    );
  }
}

class DeathTimerPage extends StatefulWidget {
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
        registration?.update(); // Ask the service worker to check for updates

        registration?.addEventListener('updatefound', (event) {
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
                bool success = await fetchCharacterFromFirebase();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Character synced successfully!'
                        : 'Failed to sync character.'),
                  ),
                );
              },
              child: Text('🔄 Sync Character'),
            ),
            ElevatedButton(
              onPressed: () => checkForAppUpdate(context),
              child: Text('🛠 Check for App Update'),
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