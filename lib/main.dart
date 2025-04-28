import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';

import 'models/character.dart'; 
import 'pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

class CharacterSheetPage extends StatelessWidget {
  final Character character;

  CharacterSheetPage({required this.character});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Character')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Player: ${character.playerName}', style: TextStyle(fontSize: 20)),
          SizedBox(height: 8),
          Text('Character: ${character.characterName}', style: TextStyle(fontSize: 20)),
          SizedBox(height: 8),
          Text('Race: ${character.race}', style: TextStyle(fontSize: 20)),
          SizedBox(height: 8),
          Text('Free Affinity: ${character.freeAffinity}', style: TextStyle(fontSize: 20)),
          SizedBox(height: 8),
          Text('Build Total: ${character.buildTotal}', style: TextStyle(fontSize: 20)),
          SizedBox(height: 8),
          Text('Extra HP: ${character.extraHitPoints}', style: TextStyle(fontSize: 20)),
          SizedBox(height: 8),
          if (character.cultivationTier)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Chip(label: Text('Cultivation Tier', style: TextStyle(fontWeight: FontWeight.bold))),
            ),
          Divider(height: 32),
          ExpansionTile(
            title: Text('Skills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            children: character.skills.map((skill) {
              return ListTile(
                title: Text(skill.name),
                subtitle: Text('${skill.type} • Level ${skill.level} • ${skill.frequency}'),
              );
            }).toList(),
          ),
          Divider(height: 32),
          ExpansionTile(
            title: Text('Tiers & Affinities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            children: character.tiers.entries.map((tierEntry) {
              return ExpansionTile(
                title: Text(tierEntry.key),
                children: tierEntry.value.map((affinity) {
                  return ListTile(
                    title: Text(affinity.name),
                    subtitle: Text('Level ${affinity.level}'),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ],
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
      if (email == null) {
        throw Exception("User email is null");
      }

      final ref = FirebaseStorage.instance.ref().child('users/$email/pc.json');
      final data = await ref.getData();

      if (data != null) {
        final jsonString = utf8.decode(data);

        // Save the jsonString into local storage for offline use (optional, future)
        // For now, just print it or keep in memory if needed

        print('Character synced successfully!');
        return true;
      }
    } catch (e) {
      print('Failed to fetch character: $e');
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
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Character synced successfully!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to sync character. Please check your connection.')),
                  );
                }
              },
              child: Text('🔄 Sync Character'),
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
