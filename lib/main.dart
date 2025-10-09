import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'shared/rules_service.dart';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'models/character.dart'; 
import 'pages/login_page.dart';
import 'pages/events_page.dart';
import 'pages/rules_page.dart';
import 'pages/death_timer_page.dart';
import 'pages/admin_page.dart';
import 'pages/new_sheet_page.dart';
import 'shared/character_cache_service.dart';
import 'config/app_config.dart';
import 'shared/impersonation_service.dart';
import 'shared/admin_cache_service.dart';
import 'shared/timer_preferences_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

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
  await Hive.initFlutter();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Route Flutter framework errors to terminal
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('❌ [FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      print(details.stack);
    }
  };

  // Add console command to reset check-in state for debugging (web only)
  if (kIsWeb) {
    html.window.console.log('🔧 Debug commands available:');
    html.window.console.log('  - resetCheckInState() - Reset stuck check-in state');
    html.window.console.log('🔄 Adding resetCheckInState function to window...');
    html.window.console.log('🔄 Type "resetCheckInState()" in console to reset check-in state');
    html.window.console.log('🔄 Function added successfully');
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
      navigatorObservers: [routeObserver],
      home: ImpersonationWrapper(child: LoginPage()), // Start at the login page
    );
  }
}

class ImpersonationWrapper extends StatelessWidget {
  final Widget child;
  
  const ImpersonationWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ImpersonationService.listenable,
      builder: (context, isImpersonating, _) {
        if (!isImpersonating) {
          return child;
        }
        
        return Scaffold(
          body: Column(
            children: [
              // Global impersonation banner
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.withOpacity(0.9),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'IMPERSONATING: ${ImpersonationService.targetEmail ?? ImpersonationService.targetUid}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        ImpersonationService.stop();
                        // Navigate back to home page to refresh
                        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'STOP IMPERSONATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Main content
              Expanded(child: child),
            ],
          ),
        );
      },
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
  List<Event> activeEvents = [];
  bool isLoadingEvents = true;
  Map<String, bool> eventRegistrationStatus = {};
  Map<String, bool> eventCheckInStatus = {};
  Map<String, bool> isLoadingRegistrationStatus = {};
  bool _isSuperAdmin = false;
  
  // Individual loading states for different components
  final Map<String, bool> _loadingStates = {
    'character': true,
    'events': true,
    'userStructure': true,
    'adminStatus': true,
    'impersonation': false,
  };
  
  // Impersonation state
  bool _isImpersonating = false;

  @override
  void initState() {
    super.initState();
    // Initialize impersonation status immediately
    _isImpersonating = ImpersonationService.isImpersonating;
    _initializeApp();
  }

  /// Check if a specific component is loaded
  bool isComponentLoaded(String component) {
    return !(_loadingStates[component] ?? true);
  }

  /// Get loading state for events (used by EventsPage)
  bool get isEventsLoading => _loadingStates['events'] ?? true;
  
  /// Get loading state for admin status (used by EventsPage)
  bool get isAdminStatusLoading => _loadingStates['adminStatus'] ?? true;
  
  /// Get loading state for impersonation
  bool get isImpersonationLoading => _loadingStates['impersonation'] ?? false;

  /// Mark a loading operation as complete
  void _markLoadingComplete(String operation) {
    setState(() {
      _loadingStates[operation] = false;
    });
    print('✅ Completed loading: $operation');
  }

  /// Initialize all app components
  Future<void> _initializeApp() async {
    print('🚀 Starting app initialization...');
    
    // Start all initialization tasks
    _fetchCharacterWithLoading();
    _fetchActiveEventsWithLoading();
    _initializeUserStructureWithLoading();
    _checkSuperAdminPermissionsWithLoading();
    
    // Refresh cache from DB if last_sync is newer (non-blocking)
    CharacterCacheService.refreshIfStale().catchError((_) => false);
    
    // Set up impersonation callback to refresh character data
    ImpersonationService.setOnImpersonationChange(() {
      print('🎭 Impersonation callback triggered - mounted: $mounted');
      if (mounted) {
        print('🎭 Calling fetchCharacter from callback');
        setState(() {
          _isImpersonating = ImpersonationService.isImpersonating;
        });
        fetchCharacter();
      }
    });
    
    // Listen to impersonation status changes
    ImpersonationService.listenable.addListener(() {
      if (mounted) {
        final wasImpersonating = _isImpersonating;
        final nowImpersonating = ImpersonationService.isImpersonating;
        
        setState(() {
          _isImpersonating = nowImpersonating;
        });
        
        // If we stopped impersonating, refresh the character data
        if (wasImpersonating && !nowImpersonating) {
          print('🔄 HomePage: Impersonation stopped, refreshing character data...');
          fetchCharacter();
        }
      }
    });
  }

  /// Wrapper for fetchCharacter that tracks loading state
  Future<void> _fetchCharacterWithLoading() async {
    try {
      await fetchCharacter();
    } finally {
      _markLoadingComplete('character');
    }
  }

  /// Wrapper for fetchActiveEvents that tracks loading state
  Future<void> _fetchActiveEventsWithLoading() async {
    try {
      await fetchActiveEvents();
    } finally {
      _markLoadingComplete('events');
    }
  }

  /// Wrapper for _initializeUserStructure that tracks loading state
  Future<void> _initializeUserStructureWithLoading() async {
    try {
      await _initializeUserStructure();
    } finally {
      _markLoadingComplete('userStructure');
    }
  }

  /// Wrapper for _checkSuperAdminPermissions that tracks loading state
  Future<void> _checkSuperAdminPermissionsWithLoading() async {
    try {
      await _checkSuperAdminPermissions();
    } finally {
      _markLoadingComplete('adminStatus');
    }
  }

  Future<void> fetchCharacter() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final effectiveUid = ImpersonationService.getEffectiveUid();
      final email = ImpersonationService.getEffectiveEmail() ?? user?.email;
      
      print('🔄 fetchCharacter called - isImpersonating: ${ImpersonationService.isImpersonating}, effectiveUid: $effectiveUid, email: $email');
      
      if (email == null) {
        throw Exception("User email is null");
      }

      // If impersonating, load from Firestore via API instead of Storage
      if (ImpersonationService.isImpersonating && effectiveUid != null) {
        print('🎭 Loading character from API for impersonation');
        await _loadCharacterFromAPI(effectiveUid);
        return;
      }

      // Normal flow: load from Firebase Storage
      final ref = FirebaseStorage.instance.ref().child('users/$email/pc.json');
      final data = await ref.getData();
      if (data != null) {
        final jsonString = utf8.decode(data);
        final jsonMap = json.decode(jsonString);
        final fetchedCharacter = Character.fromJson(jsonMap);
        setState(() {
          character = fetchedCharacter;
        });
        
        // Set the global cachedCharacter so other pages can access it
        cachedCharacter = fetchedCharacter;
        print('✅ Character cached globally from HomePage');
        
        // Also try to download QR code (don't fail if it doesn't exist)
        _downloadQRCode(email);
      } else {
        // No character data found - check if they have data in Firestore and trigger calculation
        print('📋 No character data found in Storage, checking Firestore...');
        await _checkAndCalculateCharacterIfNeeded(user?.uid ?? '', email);
      }
    } catch (e) {
      print('Error fetching character JSON: $e');
    }
  }

  /// Check if user has character data in Firestore and trigger calculation if needed
  Future<void> _checkAndCalculateCharacterIfNeeded(String uid, String email) async {
    try {
      print('🔍 Checking if user has character data in Firestore...');
      
      // Check if user has any characters in Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final idToken = await user.getIdToken();
      final response = await http.get(
        Uri.parse(AppConfig.getCharactersUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true && responseData['characters'] != null) {
          final characters = responseData['characters'] as List;
          if (characters.isNotEmpty) {
            print('📊 Found ${characters.length} character(s) in Firestore, triggering calculation...');
            
            // Get the first character and trigger calculation
            final characterData = characters.first;
            final characterId = characterData['id'] as String;
            
            // Extract character number from characterId (format: uid_characterNumber)
            final parts = characterId.split('_');
            if (parts.length >= 2) {
              final characterNumber = parts[1];
              print('🎯 Triggering calculate character for character number: $characterNumber');
              
              // Call calculate character function
              await _callCalculateCharacterFunctionForLogin(uid, characterNumber);
            }
          } else {
            print('📭 No characters found in Firestore for user');
          }
        } else {
          print('⚠️ Failed to get characters from API: ${responseData['error']}');
        }
      } else {
        print('⚠️ Failed to check characters: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error checking character data: $e');
    }
  }

  /// Call calculate character function for login initialization
  Future<void> _callCalculateCharacterFunctionForLogin(String uid, String characterNumber) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ User not authenticated for calculate character');
        return;
      }

      final idToken = await user.getIdToken();
      print('🔄 Calling calculate character for UID: $uid, character: $characterNumber');

      final response = await http.post(
        Uri.parse(AppConfig.calculateCharacterUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'playerUid': uid,
          'characterNumber': characterNumber,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          print('✅ Character calculation completed successfully');
          // After successful calculation, try to fetch the character again
          await fetchCharacter();
        } else {
          print('⚠️ Character calculation failed: ${responseData['error']}');
        }
      } else {
        print('❌ Calculate character HTTP error: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
      }
    } catch (e) {
      print('❌ Error calling calculate character: $e');
    }
  }

  Future<void> _loadCharacterFromAPI(String targetUid) async {
    try {
      print('🎭 _loadCharacterFromAPI called for targetUid: $targetUid');
      
      // Set loading state for impersonation
      setState(() {
        _loadingStates['impersonation'] = true;
      });
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🎭 No user found, returning');
        setState(() {
          _loadingStates['impersonation'] = false;
        });
        return;
      }

      final idToken = await user.getIdToken();
      final baseUrl = AppConfig.getCharactersUrl;
      final url = '$baseUrl?impersonateUid=$targetUid';
      print('🎭 Making API call to: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );
      
      print('🎭 API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          final characters = responseData['characters'] as List<dynamic>;
          if (characters.isNotEmpty) {
            // Load the first character (or we could let user choose)
            final characterData = characters.first;
            final characterId = characterData['id'] as String;
            
            // Load the full character data from Firestore
            await _loadCharacterDetails(characterId);
            
            // Download PC.json in background (non-blocking for better UX)
            // Only download if we don't already have character data loaded
            final targetEmail = ImpersonationService.getEffectiveEmail();
            if (targetEmail != null && cachedCharacter == null) {
              print('🔄 Starting background PC.json sync for $targetEmail');
              _downloadPCJsonForImpersonation(targetEmail).catchError((error) {
                print('⚠️ Background PC.json sync failed: $error');
                // Don't block the UI for this
              });
            } else if (cachedCharacter != null) {
              print('✅ Character already loaded, skipping PC.json download');
            }
          }
        }
      }
    } catch (e) {
      print('Error loading character from API: $e');
    }
  }

  Future<void> _loadCharacterDetails(String characterId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      final response = await http.get(
        Uri.parse('${AppConfig.getCharacterByIdUrl}?characterId=$characterId'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          final characterJson = responseData['character'];
          final fetchedCharacter = Character.fromJson(characterJson);
          setState(() {
            character = fetchedCharacter;
          });
          
          // Set the global cachedCharacter so other pages can access it
          cachedCharacter = fetchedCharacter;
          print('✅ Character loaded from Firestore via API');
        }
      }
      
      // Mark impersonation loading as complete
      setState(() {
        _loadingStates['impersonation'] = false;
      });
    } catch (e) {
      print('Error loading character details: $e');
      
      // Mark impersonation loading as complete even on error
      setState(() {
        _loadingStates['impersonation'] = false;
      });
    }
  }

  Future<void> _downloadPCJsonForImpersonation(String targetEmail) async {
    try {
      print('🔄 Starting background PC.json sync for $targetEmail');
      
      // For impersonation, we need to use a backend function to download the PC.json
      // since the admin doesn't have direct access to the target user's Storage
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      
      // Add timeout to prevent hanging
      final response = await http.get(
        Uri.parse('${AppConfig.syncCharacterToFirestoreUrl}?email=${Uri.encodeQueryComponent(targetEmail)}'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          print('✅ PC.json synced to Firestore for impersonation');
        } else {
          print('⚠️ PC.json sync returned error: ${responseData['error']}');
        }
      } else {
        print('⚠️ PC.json sync failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Background PC.json sync failed: $e');
      // This is non-blocking, so we don't rethrow the error
    }
  }

  Future<String?> _downloadQRCode(String email) async {
    try {
      final qrRef = FirebaseStorage.instance.ref().child('users/$email/qr.png');
      final data = await qrRef.getData();
      if (data != null) {
        print('✅ QR code downloaded');
        return 'https://storage.googleapis.com/crucible-helper-storage/users/$email/qr.png';
      }
    } catch (e) {
      print('⚠️ QR code not available: $e');
    }
    return null;
  }

  Future<void> _initializeUserStructure() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ User not authenticated, skipping user structure initialization');
        return;
      }

      print('🚀 Initializing user structure after login...');
      final idToken = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse(AppConfig.initializeUserStructureUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          print('✅ User structure initialized successfully');
          print('📋 Summary: ${responseData['summary']}');
          print('🎯 Character number: ${responseData['characterNumber']}');
          print('📍 Path: ${responseData['path']}');
        } else {
          print('❌ User structure initialization failed: ${responseData['error']}');
        }
      } else {
        print('❌ User structure initialization HTTP error: ${response.statusCode}');
      }
    } catch (error) {
      print('❌ Error initializing user structure: $error');
    }
  }

  Future<void> fetchActiveEvents() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          isLoadingEvents = false;
        });
        return;
      }

      final idToken = await user.getIdToken();
      
      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getEvents'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          final eventsList = data['events'] as List;
          final allEvents = eventsList.map((eventData) {
            return Event.fromFirestore(eventData, eventData['id']);
          }).toList();

          // Filter for active events (registration activated and in the future)
          final now = DateTime.now();
          final active = allEvents.where((event) {
            return event.registrationActivated && 
                   event.startDateTime.isAfter(now);
          }).toList();

          setState(() {
            activeEvents = active;
            isLoadingEvents = false;
          });

          // Check registration status for each active event
          for (final event in active) {
            checkEventRegistrationStatus(event.id);
          }
        } else {
          setState(() {
            isLoadingEvents = false;
          });
        }
      } else {
        setState(() {
          isLoadingEvents = false;
        });
      }
    } catch (error) {
      print('Error fetching active events: $error');
      setState(() {
        isLoadingEvents = false;
      });
    }
  }

  Future<void> checkEventRegistrationStatus(String eventId) async {
    try {
      setState(() {
        isLoadingRegistrationStatus[eventId] = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/getUserEventRegistration?eventId=$eventId'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isRegistered = data['ok'] == true && data['registration'] != null;
        
        setState(() {
          eventRegistrationStatus[eventId] = isRegistered;
          isLoadingRegistrationStatus[eventId] = false;
        });

        // If registered, check check-in status
        if (isRegistered) {
          checkEventCheckInStatus(eventId);
        }
      } else {
        setState(() {
          eventRegistrationStatus[eventId] = false;
          isLoadingRegistrationStatus[eventId] = false;
        });
      }
    } catch (error) {
      print('Error checking registration status for event $eventId: $error');
      setState(() {
        eventRegistrationStatus[eventId] = false;
        isLoadingRegistrationStatus[eventId] = false;
      });
    }
  }

  Future<void> checkEventCheckInStatus(String eventId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-crucible-helper.cloudfunctions.net/checkPlayerRegistration'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'eventId': eventId,
          'playerUid': user.uid,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isCheckedIn = data['ok'] == true && data['isCheckedIn'] == true;
        
        setState(() {
          eventCheckInStatus[eventId] = isCheckedIn;
        });
      } else {
        setState(() {
          eventCheckInStatus[eventId] = false;
        });
      }
    } catch (error) {
      print('Error checking check-in status for event $eventId: $error');
      setState(() {
        eventCheckInStatus[eventId] = false;
      });
    }
  }

  Future<void> _checkSuperAdminPermissions() async {
    // Use cached admin status service for immediate UI update
    await AdminCacheService.getAdminStatus(
      onStatusUpdate: (isAdmin) {
        if (mounted) {
          setState(() {
            _isSuperAdmin = isAdmin;
          });
        }
      },
    );
  }

  /// Build loading screen with progress indicators

  /// Build impersonation banner
  Widget _buildImpersonationBanner() {
    if (!_isImpersonating) return SizedBox.shrink();
    
    final targetEmail = ImpersonationService.targetEmail ?? 'Unknown User';
    final targetUid = ImpersonationService.targetUid ?? '';
    
    return Container(
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
                  targetEmail,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
                if (targetUid.isNotEmpty)
                  Text(
                    'UID: ${targetUid.substring(0, 8)}...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                      fontFamily: 'monospace',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    
    final isWide = MediaQuery.of(context).size.width >= 900;
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
      floatingActionButton: isWide ? null : FloatingActionButton.large(
        tooltip: 'Character',
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
        child: Icon(Icons.person),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isWide ? null : BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.grey[900],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                IconButton(
                  tooltip: 'Scan',
                  icon: Icon(Icons.qr_code_scanner),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QRScannerPage())),
                ),
                IconButton(
                  tooltip: 'Timers',
                  icon: Icon(Icons.timer),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeathTimerPage())),
                ),
              ]),
              Row(children: [
                IconButton(
                  tooltip: 'Events',
                  icon: Icon(Icons.calendar_today),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventsPage(
                    isEventsLoading: isEventsLoading,
                    isAdminStatusLoading: isAdminStatusLoading,
                  ))),
                ),
                IconButton(
                  tooltip: 'Rules',
                  icon: Icon(Icons.menu_book),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RulesPage())),
                ),
                if (_isSuperAdmin)
                  IconButton(
                    tooltip: 'Admin',
                    icon: Icon(Icons.admin_panel_settings, color: Colors.amber),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPage())),
                  ),
              ]),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Impersonation banner (always at top)
            _buildImpersonationBanner(),
            // Main content
            Expanded(
              child: isWide
                  ? Row(
                      children: [
                  NavigationRail(
                    backgroundColor: Colors.black,
                    selectedIndex: null,
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.person),
                        label: Text('Character'),
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
                    ),
                    destinations: [
                      NavigationRailDestination(icon: Icon(Icons.qr_code_scanner), label: Text('Scan')),
                      NavigationRailDestination(icon: Icon(Icons.timer), label: Text('Timers')),
                      NavigationRailDestination(icon: Icon(Icons.calendar_today), label: Text('Events')),
                      NavigationRailDestination(icon: Icon(Icons.menu_book), label: Text('Rules')),
                      if (_isSuperAdmin)
                        NavigationRailDestination(
                          icon: Icon(Icons.admin_panel_settings, color: Colors.amber), 
                          label: Text('Admin', style: TextStyle(color: Colors.amber))
                        ),
                    ],
                    onDestinationSelected: (idx) {
                      switch (idx) {
                        case 0:
                          Navigator.push(context, MaterialPageRoute(builder: (_) => QRScannerPage()));
                          break;
                        case 1:
                          Navigator.push(context, MaterialPageRoute(builder: (_) => DeathTimerPage()));
                          break;
                        case 2:
                          Navigator.push(context, MaterialPageRoute(builder: (_) => EventsPage(
                            isEventsLoading: isEventsLoading,
                            isAdminStatusLoading: isAdminStatusLoading,
                          )));
                          break;
                        case 3:
                          Navigator.push(context, MaterialPageRoute(builder: (_) => RulesPage()));
                          break;
                        case 4:
                          if (_isSuperAdmin) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPage()));
                          }
                          break;
                      }
                    },
                  ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildHomeCenterContent()),
                      ],
                    )
                  : _buildHomeCenterContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCenterContent() {
    // Show loading screen if impersonation is loading
    if (isImpersonationLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
            SizedBox(height: 20),
            Text(
              'Loading character data...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (activeEvents.isNotEmpty) _buildActiveEventsSection(),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double screenHeight = constraints.maxHeight;
                double logoSize = screenHeight * 0.25;
                if (logoSize > 200) {
                  logoSize = 200;
                }
                return Image.asset(
                  'assets/logo.png',
                  height: logoSize,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveEventsSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Events',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 160, // Increased height to accommodate status indicators
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: activeEvents.length,
              itemBuilder: (context, index) {
                final event = activeEvents[index];
                final isLoadingStatus = isLoadingRegistrationStatus[event.id] ?? true;
                final isRegistered = eventRegistrationStatus[event.id] ?? false;
                final isCheckedIn = eventCheckInStatus[event.id] ?? false;
                
                return Container(
                  width: 280,
                  margin: EdgeInsets.only(right: 12),
                  child: Card(
                    color: Colors.grey[900],
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EventsPage(
                            isEventsLoading: isEventsLoading,
                            isAdminStatusLoading: isAdminStatusLoading,
                          )),
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.all(10), // Reduced padding
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (event.registrationActivated && event.registrationDetails != null &&
                                      ((event.registrationDetails!['eventName'] ?? '').toString().isNotEmpty))
                                  ? event.registrationDetails!['eventName']
                                  : event.typeName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 3), // Reduced spacing
                            Text(
                              event.dateRange,
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 3), // Reduced spacing
                            Text(
                              event.location,
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Spacer(),
                            // Registration status
                            if (!isLoadingStatus) ...[
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3), // Reduced padding
                                decoration: BoxDecoration(
                                  color: isRegistered 
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isRegistered ? Colors.green : Colors.blue,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isRegistered ? Icons.check_circle : Icons.event_available,
                                      color: isRegistered ? Colors.green : Colors.blue,
                                      size: 12,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      isRegistered ? 'Registered' : 'Register Now',
                                      style: TextStyle(
                                        color: isRegistered ? Colors.green : Colors.blue,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Check-in status (only show if registered)
                              if (isRegistered) ...[
                                SizedBox(height: 3), // Reduced spacing
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3), // Reduced padding
                                  decoration: BoxDecoration(
                                    color: isCheckedIn 
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isCheckedIn ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isCheckedIn ? Icons.check_circle : Icons.pending,
                                        color: isCheckedIn ? Colors.green : Colors.orange,
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        isCheckedIn ? 'Checked In' : 'Not Checked In',
                                        style: TextStyle(
                                          color: isCheckedIn ? Colors.green : Colors.orange,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ] else ...[
                              // Loading indicator
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Loading...',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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

// QR Code Scanner Landing Page
class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkSuperAdminPermissions();
  }

  Future<void> _checkSuperAdminPermissions() async {
    // Use cached admin status service for immediate UI update
    await AdminCacheService.getAdminStatus(
      onStatusUpdate: (isAdmin) {
        if (mounted) {
          setState(() {
            isSuperAdmin = isAdmin;
          });
        }
      },
    );
  }

  void _openCameraScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CameraScannerPage(
          onQRCodeScanned: _handleQRCodeResult,
          isSuperAdmin: isSuperAdmin,
        ),
      ),
    );
  }

  void _handleQRCodeResult(String qrData) {
    // Close the camera scanner
    Navigator.pop(context);
    
    // Process the QR code on this page (main scan screen)
    _processQRCode(qrData);
  }

  // Process QR code data
  void _processQRCode(String qrData) {
    try {
      // Try to parse as JSON first
      final data = json.decode(qrData);
      
      // Check if it's a Crucible Helper character QR code (new format)
      if (data['game'] == 'Crucible' && data['playerName'] != null) {
        _showCharacterQRResult(data);
        return;
      }
      
      // Check if it's a Monster Core QR code
      if (data['game'] == 'Crucible' && data['label'] == 'Monster Core') {
        _showMonsterCoreQRResult(data);
        return;
      }
      
      // Check if it's the old format
      if (data['app'] == 'Crucible Helper' && data['playerName'] != null) {
        _showCharacterQRResult(data);
        return;
      }
      
      // If it's JSON but not a character QR code, show unrecognized message
      _showUnrecognizedQRCode();
      
    } catch (e) {
      // If it's not JSON, show unrecognized message
      _showUnrecognizedQRCode();
    }
  }

  void _showMonsterCoreQRResult(Map<String, dynamic> data) async {
    // Check if widget is still mounted
    if (!mounted) return;
    
    try {
      final tier = data['tier'] ?? 'Unknown';
      final coreId = data['id'] ?? 'Unknown';
      
      // Debug: Print the QR data for troubleshooting
      print('🔍 Monster Core QR data: $data');
                      print('🔍 Core ID: $coreId');
      
                      // Show loading dialog while checking core status
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Checking Core Status'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Looking up core status...'),
                          SizedBox(height: 8),
                          Text('Tier: $tier', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                );
                
                // Get current status from Firebase database
                bool coreIsActive = false;
                Map<String, dynamic>? coreData;
                
                try {
                  final user = _auth.currentUser;
                  if (user == null) {
                    if (mounted && Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    print('🔍 User not authenticated');
                    _showError('User not authenticated');
                    return;
                  }
                  
                  final idToken = await user.getIdToken();
        final response = await http.get(
          Uri.parse('${AppConfig.getMonsterCoreUrl}?coreId=$coreId'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
        );
        
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['ok'] == true) {
            coreData = responseData['core'];
            coreIsActive = coreData?['isActive'] ?? false;
            print('🔍 Firebase core data: $coreData');
            print('🔍 Firebase isActive: $coreIsActive');
            
            // Track the scan
            try {
              final scanResponse = await http.post(
                Uri.parse(AppConfig.trackMonsterCoreScanUrl),
                headers: {
                  'Authorization': 'Bearer $idToken',
                  'Content-Type': 'application/json',
                },
                body: json.encode({
                  'coreId': coreId,
                  'scanResult': coreIsActive ? 'active' : 'inactive',
                }),
              );
              
              if (scanResponse.statusCode == 200) {
                print('📊 Scan tracked successfully');
              } else {
                print('📊 Failed to track scan: ${scanResponse.statusCode}');
              }
            } catch (e) {
              print('📊 Error tracking scan: $e');
              // Don't fail the scan if tracking fails
            }
          } else {
            print('🔍 Firebase error: ${responseData['error']}');
            _showError('Error retrieving core data: ${responseData['error']}');
            return;
          }
        } else {
          print('🔍 HTTP error: ${response.statusCode}');
          _showError('Error connecting to server');
          return;
        }
      } catch (e) {
        // Close loading dialog
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        print('🔍 Error checking Firebase: $e');
        _showError('Error checking core status');
        return;
      }
      
      print('🔍 Final coreIsActive determination: $coreIsActive');

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show modal with core information
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Monster Core'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                                 // Core status
                 Row(
                   children: [
                     Icon(
                       coreIsActive ? Icons.check_circle : Icons.warning,
                       color: coreIsActive ? Colors.green : Colors.orange,
                       size: 24,
                     ),
                     SizedBox(width: 8),
                     Text(
                       coreIsActive ? 'Active' : 'Inactive',
                       style: TextStyle(
                         fontSize: 16,
                         fontWeight: FontWeight.bold,
                         color: coreIsActive ? Colors.green : Colors.orange,
                       ),
                     ),
                   ],
                 ),
                SizedBox(height: 16),
                
                // Core details
                Text('Tier: $tier', style: TextStyle(fontSize: 16)),
                                          Text('Number: $coreId', style: TextStyle(fontSize: 16)),
                SizedBox(height: 16),
                
                                 // Status message
                 if (!coreIsActive) ...[
                   Container(
                     padding: EdgeInsets.all(12),
                     decoration: BoxDecoration(
                       color: Colors.orange.withOpacity(0.1),
                       border: Border.all(color: Colors.orange),
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: Text(
                       'Please turn in this core.',
                       style: TextStyle(
                         fontSize: 14,
                         color: Colors.orange,
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                   ),
                 ] else ...[
                  // Active core options
                  Text(
                    'What would you like to do with this core?',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  
                  // Option buttons
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showConsumeForBuildOption(data);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Consume for Build'),
                    ),
                  ),
                  SizedBox(height: 8),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showSlotForAffinityOption(data);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Slot for Affinity Points'),
                    ),
                  ),
                  SizedBox(height: 8),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showStoreCoreOption(data);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Store Core'),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
            ],
          );
        },
      );
      
    } catch (e) {
      print('Error showing monster core QR result: $e');
      _showUnrecognizedQRCode();
    }
  }

  void _showConsumeForBuildOption(Map<String, dynamic> coreData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Consume for Build'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.build, color: Colors.blue, size: 48),
              SizedBox(height: 16),
              Text(
                'This will add 1 Build point to your character.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Core: ${coreData['tier']} Tier',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processConsumption(coreData, 'build');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _showSlotForAffinityOption(Map<String, dynamic> coreData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Slot for Affinity Points'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, color: Colors.purple, size: 48),
              SizedBox(height: 16),
              Text(
                'This will add 1 Affinity Point to your character.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Core: ${coreData['tier']} Tier',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processConsumption(coreData, 'affinity');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _showStoreCoreOption(Map<String, dynamic> coreData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Store Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory, color: Colors.green, size: 48),
              SizedBox(height: 16),
              Text(
                'This will store the core in your character\'s inventory for later use or trading.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Core: ${coreData['tier']} Tier',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _selectCharacterForStorage(coreData);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text('Store Core'),
            ),
          ],
        );
      },
    );
  }

  void _selectCharacterForStorage(Map<String, dynamic> coreData) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Loading Characters...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Getting your characters...'),
              ],
            ),
          );
        },
      );

      // Get user's characters
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('User not authenticated');
        return;
      }

      final idToken = await user.getIdToken();
      final effectiveUid = ImpersonationService.getEffectiveUid();
      final baseUrl = AppConfig.getCharactersUrl;
      final url = effectiveUid != null && effectiveUid != user.uid 
          ? '$baseUrl?impersonateUid=$effectiveUid'
          : baseUrl;
      
      final charactersResponse = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (charactersResponse.statusCode == 200) {
        final charactersData = json.decode(charactersResponse.body);
        if (charactersData['ok'] == true) {
          final characters = charactersData['characters'] as List<dynamic>;
          
          if (characters.isEmpty) {
            final debug = charactersData['debug'];
            final debugInfo = debug != null 
                ? 'Searched for UID: ${debug['searchedForUid']}, Player exists: ${debug['playerExists']}, Characters count: ${debug['charactersCount']}, Message: ${debug['message']}'
                : 'No debug info';
            print('🔍 Character loading debug info: $debugInfo');
            _showError('No characters found. Debug: $debugInfo');
            return;
          }

          // Go straight to storing the core
          _storeCore(coreData);
        } else {
          _showError('Error loading characters: ${charactersData['error']}');
        }
      } else {
        _showError('Error loading characters: HTTP ${charactersResponse.statusCode}');
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error loading characters: $error');
      _showError('Error loading characters: $error');
    }
  }

  void _storeCore(Map<String, dynamic> coreData) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Storing Core...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Storing core in character inventory...'),
              ],
            ),
          );
        },
      );

      final user = _auth.currentUser;
      if (user == null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('User not authenticated');
        return;
      }

      final idToken = await user.getIdToken();
      final coreId = coreData['id'];

      // Call the storeMonsterCore Firebase function
      final response = await http.post(
        Uri.parse(AppConfig.storeMonsterCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'coreId': coreId,
          'characterNumber': cachedCharacter?.characterNumber.toString() ?? 'main',
        }),
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('🔍 Store core response: $responseData');
        if (responseData['ok'] == true) {
          _showStorageSuccess(responseData);
        } else {
          print('❌ Store core error: ${responseData['error']}');
          _showError('Error: ${responseData['error']}');
        }
      } else {
        final errorBody = response.body;
        print('❌ Store core HTTP error ${response.statusCode}: $errorBody');
        _showError('Error storing core: HTTP ${response.statusCode}');
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error storing core: $error');
      _showError('Error storing core: $error');
    }
  }





  void _showStorageSuccess(Map<String, dynamic> responseData) {
    final action = responseData['action'] ?? 'stored';
    final newCount = responseData['newCount'] ?? 1;
    final message = responseData['message'] ?? 'Core stored successfully';
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Core Stored Successfully'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                                          Text(
                        'You now have $newCount ${responseData['tier'] ?? 'Iron'} core${newCount == 1 ? '' : 's'} in storage',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _processConsumption(Map<String, dynamic> coreData, String action) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Processing...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing your ${action == 'build' ? 'build' : 'affinity'} consumption...'),
              ],
            ),
          );
        },
      );

      // Get user authentication
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('User not authenticated');
        return;
      }

      final idToken = await user.getIdToken();
      final coreId = coreData['id'];

      // Call the consumeMonsterCore Firebase function
      final response = await http.post(
        Uri.parse(AppConfig.consumeMonsterCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'coreId': coreId,
          'consumptionType': action,
        }),
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          _showSuccess('${action == 'build' ? 'Build' : 'Affinity'} consumption processed successfully!');
        } else {
          _showError('Error: ${responseData['error']}');
        }
      } else {
        _showError('Error processing consumption: HTTP ${response.statusCode}');
      }
    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        _showError('Error processing consumption: $error');
      }
    }
  }

  void _showCharacterQRResult(Map<String, dynamic> data) {
    // Character QR code processing
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Character QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person, color: Colors.blue, size: 48),
              SizedBox(height: 16),
              Text('Character QR code detected'),
              Text('Player: ${data['playerName']}'),
              if (data['characterName'] != null)
                Text('Character: ${data['characterName']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showUnrecognizedQRCode() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Unrecognized QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code, color: Colors.grey, size: 48),
              SizedBox(height: 16),
              Text(
                'This QR code is not recognized.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Please scan a valid Monster Core or Character QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showMonsterCorePrintoutDialog() {
    int numberOfPages = 1;
    String selectedTier = 'Silver';
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Generate Monster Cores'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Generate PDF sheets of monster core cards'),
                  SizedBox(height: 20),
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Number of Pages',
                      hintText: '1-100',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    initialValue: '1',
                    onChanged: (value) {
                      numberOfPages = int.tryParse(value) ?? 1;
                    },
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Tier',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: selectedTier,
                    items: [
                      'Iron',
                      'Silver', 
                      'Gold',
                      'Jade',
                      'Saint',
                      'Sovereign'
                    ].map((String tier) {
                      return DropdownMenuItem<String>(
                        value: tier,
                        child: Text(tier),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedTier = newValue ?? 'Silver';
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _generateMonsterCorePrintout(numberOfPages, selectedTier);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('Generate PDF'),
            ),
          ],
        );
      },
    );
  }

  void _showReactivateMonsterCoreDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reactivate Monster Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh,
                size: 48,
                color: Colors.orange,
              ),
              SizedBox(height: 16),
              Text(
                'This feature allows you to reactivate monster cores.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'When you scan a QR code, the core will be reset to defaults and become active again.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openReactivateScanner();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('Start Scanning'),
            ),
          ],
        );
      },
    );
  }

  void _openReactivateScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ReactivateScannerPage(
          onQRCodeScanned: _handleReactivateQRCode,
        ),
      ),
    );
  }

  void _handleReactivateQRCode(String qrData) {
    // Close the scanner
    Navigator.pop(context);
    
    // Process the QR code for reactivation
    _processReactivateQRCode(qrData);
  }

  void _processReactivateQRCode(String qrData) async {
    try {
      // Try to parse as JSON first
      final data = json.decode(qrData);
      
      // Check if it's a Monster Core QR code
      if (data['game'] == 'Crucible' && data['label'] == 'Monster Core') {
        final coreId = data['id'] ?? 'Unknown';
        
        if (coreId == 'Unknown') {
          _showError('Invalid monster core QR code - missing ID');
          return;
        }
        
        // Call reactivation function
        _reactivateMonsterCore(coreId);
        return;
      }
      
      // If it's not a monster core, show error
      _showError('This QR code is not a monster core. Please scan a valid monster core QR code.');
      
    } catch (e) {
      // If it's not JSON or parsing fails, show error
      _showError('Invalid QR code format. Please scan a valid monster core QR code.');
    }
  }

  void _reactivateMonsterCore(String coreId) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Reactivating Core...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Reactivating monster core...'),
                SizedBox(height: 8),
                Text('Core ID: $coreId', style: TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          );
        },
      );

      // Get user authentication
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('User not authenticated');
        return;
      }

      final idToken = await user.getIdToken();

      // Call the reactivateMonsterCore Firebase function
      final response = await http.post(
        Uri.parse(AppConfig.reactivateMonsterCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'coreId': coreId,
        }),
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          _showReactivateSuccess(responseData['message']);
        } else {
          _showError('Error: ${responseData['error']}');
        }
      } else if (response.statusCode == 400) {
        // Handle client errors (like already active core)
        final responseData = json.decode(response.body);
        if (responseData['error'] == 'Core is already active') {
          _showReactivateAlreadyActive();
        } else {
          _showError('Error: ${responseData['error']}');
        }
      } else {
        _showError('Error reactivating core: HTTP ${response.statusCode}');
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error reactivating monster core: $error');
      _showError('Error reactivating core: $error');
    }
  }

  void _showReactivateSuccess(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Core Reactivated'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              SizedBox(height: 16),
              Text(
                'Would you like to scan another core?',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Done'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openReactivateScanner();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('Scan Another'),
            ),
          ],
        );
      },
    );
  }

  void _showReactivateAlreadyActive() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info, color: Colors.blue),
              SizedBox(width: 8),
              Text('Core Already Active'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This monster core is already active and does not need reactivation.'),
              SizedBox(height: 16),
              Text(
                'Would you like to scan another core?',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Done'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openReactivateScanner();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('Scan Another'),
            ),
          ],
        );
      },
    );
  }

  void _generateMonsterCorePrintout(int numberOfPages, String tier) async {
    print('🔄 Starting monster core printout generation...');
    print('📊 Parameters: Pages=$numberOfPages, Tier=$tier');
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Generating PDF...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Creating monster core printout...'),
                SizedBox(height: 8),
                Text('Pages: $numberOfPages, Tier: $tier'),
              ],
            ),
          );
        },
      );

      print('🔐 Checking user authentication...');
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('User not authenticated');
        return;
      }
      print('✅ User authenticated: ${user.email}');

      print('🎫 Getting ID token...');
      final idToken = await user.getIdToken();
      print('✅ ID token obtained');

      print('🌐 Making HTTP request to Firebase function...');
      final url = AppConfig.generateMonsterCorePrintoutUrl;
      print('📡 URL: $url');
      
      final requestBody = {
        'numberOfPages': numberOfPages,
        'tier': tier,
      };
      print('📦 Request body: $requestBody');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response content type: ${response.headers['content-type']}');
      print('📥 Response body length: ${response.body.length}');

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        // Check if response is PDF or JSON
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/pdf') || response.body.startsWith('%PDF')) {
          print('✅ PDF generation successful - PDF data received');
          
          // Download the PDF
          try {
            final bytes = response.bodyBytes;
            final fileName = 'monster_cores_${tier.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.pdf';
            
            // For web, trigger download
            if (kIsWeb) {
              final blob = html.Blob([bytes]);
              final url = html.Url.createObjectUrlFromBlob(blob);
              final anchor = html.AnchorElement(href: url)
                ..setAttribute('download', fileName)
                ..click();
              html.Url.revokeObjectUrl(url);
              print('✅ PDF download triggered for web');
            } else {
              // For mobile, save to downloads folder
              try {
                final directory = await getApplicationDocumentsDirectory();
                final file = File('${directory.path}/$fileName');
                await file.writeAsBytes(bytes);
                print('✅ PDF saved to: ${file.path}');
              } catch (e) {
                print('❌ Error saving PDF to mobile: $e');
                // Fallback: just show success message
              }
            }
            
            _showSuccess('Monster core printout generated and downloaded successfully!');
          } catch (downloadError) {
            print('❌ Error downloading PDF: $downloadError');
            _showError('PDF generated but download failed: $downloadError');
          }
        } else {
          // Try to parse as JSON for error messages
          try {
            final responseData = json.decode(response.body);
            print('📋 Response data: $responseData');
            
            if (responseData['ok'] == true) {
              print('✅ PDF generation successful');
              _showSuccess('Monster core printout generated successfully! Check your downloads.');
            } else {
              print('❌ Firebase function error: ${responseData['error']}');
              _showError('Error generating printout: ${responseData['error']}');
            }
          } catch (jsonError) {
            print('❌ Could not parse response as JSON: $jsonError');
            _showError('Error: Unexpected response format from server');
          }
        }
      } else {
        print('❌ HTTP error: ${response.statusCode}');
        _showError('Error generating printout: HTTP ${response.statusCode}');
      }
    } catch (error, stackTrace) {
      print('💥 Exception caught: $error');
      print('📚 Stack trace: $stackTrace');
      
      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showError('Error generating printout: $error');
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    print('❌ ERROR in QR Scanner: $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('QR Scanner'),
        backgroundColor: Colors.black,
        actions: [
          if (isSuperAdmin)
            IconButton(
              icon: Icon(Icons.print),
              onPressed: _showMonsterCorePrintoutDialog,
              tooltip: 'Generate Monster Core Printout',
            ),
          if (isSuperAdmin)
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _showReactivateMonsterCoreDialog,
              tooltip: 'Reactivate Monster Core',
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 120,
              color: Colors.white,
            ),
            SizedBox(height: 40),
            Text(
              'QR Code Scanner',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Scan Monster Cores and Character QR codes',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 60),
            ElevatedButton(
              onPressed: _openCameraScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Start Scanning',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reactivate Scanner Page (for monster core reactivation)
class _ReactivateScannerPage extends StatefulWidget {
  final Function(String) onQRCodeScanned;

  const _ReactivateScannerPage({
    required this.onQRCodeScanned,
  });

  @override
  _ReactivateScannerPageState createState() => _ReactivateScannerPageState();
}

class _ReactivateScannerPageState extends State<_ReactivateScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  String? lastScannedCode;
  DateTime? lastScanTime;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        _handleQRCodeScan(scanData.code!);
      }
    });
  }

  void _handleQRCodeScan(String qrCode) {
    final now = DateTime.now();
    
    // Debounce: Ignore scans of the same code within 2 seconds
    if (lastScannedCode == qrCode && 
        lastScanTime != null && 
        now.difference(lastScanTime!).inSeconds < 2) {
      return;
    }
    
    // Update last scan info
    lastScannedCode = qrCode;
    lastScanTime = now;
    
    // Call the callback to pass the QR code back to the main page
    widget.onQRCodeScanned(qrCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Reactivate Scanner'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on),
            onPressed: () async {
              await controller?.toggleFlash();
            },
          ),
          IconButton(
            icon: Icon(Icons.flip_camera_ios),
            onPressed: () async {
              await controller?.flipCamera();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Point camera at Monster Core QR code',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Scan to reactivate the core',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Camera Scanner Page (actual camera interface)
class _CameraScannerPage extends StatefulWidget {
  final Function(String) onQRCodeScanned;
  final bool isSuperAdmin;

  const _CameraScannerPage({
    required this.onQRCodeScanned,
    required this.isSuperAdmin,
  });

  @override
  _CameraScannerPageState createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<_CameraScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  String? lastScannedCode;
  DateTime? lastScanTime;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        _handleQRCodeScan(scanData.code!);
      }
    });
  }

  void _handleQRCodeScan(String qrCode) {
    final now = DateTime.now();
    
    // Debounce: Ignore scans of the same code within 2 seconds
    if (lastScannedCode == qrCode && 
        lastScanTime != null && 
        now.difference(lastScanTime!).inSeconds < 2) {
      return;
    }
    
    // Update last scan info
    lastScannedCode = qrCode;
    lastScanTime = now;
    
    // Call the callback to pass the QR code back to the main page
    widget.onQRCodeScanned(qrCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scanning'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on),
            onPressed: () async {
              await controller?.toggleFlash();
            },
          ),
          IconButton(
            icon: Icon(Icons.flip_camera_ios),
            onPressed: () async {
              await controller?.flipCamera();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Text(
                  'Point camera at QR code',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Trade Scanner Page
class _TradeScannerPage extends StatefulWidget {
  final Function(String) onQRCodeScanned;

  const _TradeScannerPage({required this.onQRCodeScanned});

  @override
  _TradeScannerPageState createState() => _TradeScannerPageState();
}

class _TradeScannerPageState extends State<_TradeScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      _onQRCodeScanned(scanData.code ?? '');
    });
  }

  void _onQRCodeScanned(String qrCode) {
    // Vibrate on scan
    HapticFeedback.lightImpact();
    
    // Stop the scanner
    controller?.pauseCamera();
    
    // Call the callback to pass the QR code back to the character page
    widget.onQRCodeScanned(qrCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Trade Scanner'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on),
            onPressed: () async {
              await controller?.toggleFlash();
            },
          ),
          IconButton(
            icon: Icon(Icons.flip_camera_ios),
            onPressed: () async {
              await controller?.flipCamera();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Scan a player\'s profile QR code to trade your core',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: Colors.purple,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 250,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Character Sheet Page
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
  bool _isSuperAdmin = false;
  
  // Impersonation state
  bool _isImpersonating = false;
  
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
    final dynamic rawTotalHp = widget.character.hitPoints['total'];
    currentHP = rawTotalHp is num ? rawTotalHp.toInt() : 0;
    _loadSkillSortPreference();
    _loadUnsubmittedAdvancement();
    _checkSuperAdminPermissions();
    
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
        
        // If we stopped impersonating, navigate back to home to refresh
        if (wasImpersonating && !nowImpersonating) {
          print('🔄 ProfilePage: Impersonation stopped, navigating to home...');
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    });

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

  Future<void> _checkSuperAdminPermissions() async {
    // Use cached admin status service for immediate UI update
    await AdminCacheService.getAdminStatus(
      onStatusUpdate: (isAdmin) {
        if (mounted) {
          setState(() {
            _isSuperAdmin = isAdmin;
          });
        }
      },
    );
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

  Future<void> _saveSubmissionTimestamp(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_submission_timestamp', timestamp);
  }

  Future<String?> _getLastSubmissionTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_submission_timestamp');
  }

  // Submit unsubmitted advancement to Google App Script
  Future<void> _submitAdvancementToGoogleAppScript(BuildContext context) async {
    print('DEBUG: Starting submission process...');
    print('DEBUG: _unsubmittedAdvancement = $_unsubmittedAdvancement');
    
    if (_unsubmittedAdvancement == null || 
        (_unsubmittedAdvancement!.affinityChanges.isEmpty && 
         _unsubmittedAdvancement!.skillChanges.isEmpty && 
         _unsubmittedAdvancement!.essenceChanges.isEmpty)) {
      print('DEBUG: No unsubmitted changes to submit');
      return;
    }
    
    print('DEBUG: Found unsubmitted changes - proceeding with submission');

    try {
      // Get current user and ID token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Get ID token
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get authentication token');
      }

      // Prepare the payload
      final payload = {
        'idToken': idToken,
        ..._unsubmittedAdvancement!.toJson(),
      };

      // Submit to Google App Script
      final response = await _submitToGoogleAppScript(payload);

      print('DEBUG: Submission response: $response');
      
      if (response['ok'] == true) {
        print('DEBUG: Submission successful - clearing unsubmitted changes');
        // Success - record submission timestamp and clear the unsubmitted advancement
        final submissionTimestamp = DateTime.now().toIso8601String();
        await _saveSubmissionTimestamp(submissionTimestamp);
        await _clearUnsubmittedAdvancement();
        
        // Show success message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Advancement submitted successfully! Please wait for your character data to be updated.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Error - show error message
        final errorMessage = response['message'] ?? 'Unknown error occurred';
        print('DEBUG: Submission failed: $errorMessage');
        throw Exception('Submission failed: $errorMessage');
      }

    } catch (e) {
      print('Error submitting advancement: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to submit advancement: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Submit payload to Firebase Function (proxy to Google Apps Script)
  Future<Map<String, dynamic>> _submitToGoogleAppScript(Map<String, dynamic> payload) async {
    // Use Firebase Function as proxy to Google Apps Script
    final String functionUrl = 'https://us-central1-crucible-helper.cloudfunctions.net/advancementIntake';
    
    try {
      print('Submitting payload to: $functionUrl');
      print('Payload: ${json.encode(payload)}');
      
      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Error in _submitToGoogleAppScript: $e');
      rethrow;
    }
  }

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
      final characterNumber = widget.character.characterNumber.toString() ?? 'main';
      
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

  String _getTierNumber(String collectionName) {
    switch (collectionName) {
      case 'coreIron': return '1';
      case 'coreSilver': return '2';
      case 'coreGold': return '3';
      case 'coreJade': return '4';
      case 'coreSaint': return '5';
      case 'coreSovereign': return '6';
      default: return '1';
    }
  }

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
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: coresByTier.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No stored cores found'),
                        SizedBox(height: 8),
                        Text(
                          'Scan monster cores and select "Store Core" to build your inventory.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: _buildCoresByTierList(coresByTier),
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

  List<Widget> _buildCoresByTierList(Map<String, dynamic> coresByTier) {
    final List<Widget> widgets = [];
    
    // Sort tiers by tier level (Iron=1, Silver=2, etc.)
    final tierOrder = ['Iron', 'Silver', 'Gold', 'Jade', 'Saint', 'Sovereign'];
    final tierLevels = {
      'Iron': 1,
      'Silver': 2, 
      'Gold': 3,
      'Jade': 4,
      'Saint': 5,
      'Sovereign': 6
    };

    for (final tierName in tierOrder) {
      final cores = coresByTier[tierName] as List<dynamic>?;
      
      if (cores != null && cores.isNotEmpty) {
        final tierLevel = tierLevels[tierName] ?? 1;
        
        // Tier header
        widgets.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              '$tierName Tier (${cores.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _getTierColor(tierLevel),
              ),
            ),
          ),
        );

        // Core card
        widgets.add(
          Card(
            child: ListTile(
              leading: Icon(
                Icons.circle,
                color: _getTierColor(tierLevel),
                size: 32,
              ),
              title: Text('$tierName Monster Cores'),
              subtitle: Text('${cores.length} cores available'),
              trailing: Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).pop();
                _showTierCores(tierName, cores, tierLevel);
              },
            ),
          ),
        );
      }
    }

    if (widgets.isEmpty) {
      widgets.add(
        Center(
          child: Text('No cores stored yet'),
        ),
      );
    }

    return widgets;
  }

  Color _getTierColor(int tier) {
    switch (tier) {
      case 1: return Colors.grey;      // Iron
      case 2: return Colors.white;     // Silver
      case 3: return Colors.yellow;    // Gold
      case 4: return Colors.green;     // Jade
      case 5: return Colors.purple;    // Saint
      case 6: return Colors.orange;    // Sovereign
      default: return Colors.white;
    }
  }

  // Helper function to check if a core tier can be used by the character
  bool _canUseCoreTier(String coreTier, String characterTier) {
    final tierOrder = ['Iron', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Mythic'];
    final coreTierIndex = tierOrder.indexOf(coreTier);
    final characterTierIndex = tierOrder.indexOf(characterTier);
    
    // Character can use same tier or higher tier cores
    // Cannot use lower tier cores directly
    return coreTierIndex >= characterTierIndex;
  }

  // Helper function to get tier conversion info
  String _getTierConversionInfo(String coreTier, String characterTier) {
    final tierOrder = ['Iron', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Mythic'];
    final coreTierIndex = tierOrder.indexOf(coreTier);
    final characterTierIndex = tierOrder.indexOf(characterTier);
    
    if (coreTierIndex < characterTierIndex) {
      final tierDifference = characterTierIndex - coreTierIndex;
      final requiredCount = (10 * tierDifference).toString();
      return 'You need $requiredCount $coreTier cores to equal 1 $characterTier core, or use a $characterTier core instead.';
    }
    return '';
  }

  void _showConsumeCoreDialog(String tierName, int coreCount) {
    final characterTier = widget.character.cultivationTier;
    final canUse = _canUseCoreTier(tierName, characterTier);
    final conversionInfo = _getTierConversionInfo(tierName, characterTier);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Consume $tierName Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canUse) ...[
                Text('Consuming a core is only for build points.'),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _consumeCore(tierName, 'build');
                  },
                  child: Text('Consume for Build Points'),
                ),
              ] else ...[
                Icon(Icons.block, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  'Cannot Consume $tierName Core',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'You are $characterTier tier and cannot consume $tierName cores directly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    conversionInfo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(canUse ? 'Cancel' : 'OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _consumeCore(String tierName, String usageType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User not authenticated')),
        );
        return;
      }

      // Show loading feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Text('Consuming $tierName core...'),
            ],
          ),
          duration: Duration(seconds: 30), // Long duration in case of delays
        ),
      );

      final characterNumber = widget.character.characterNumber.toString() ?? 'main';
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(AppConfig.useStoredCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'characterNumber': characterNumber,
          'tier': tierName,
          'usageType': usageType,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$tierName core consumed successfully for $usageType!'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh the stored cores display
          _showStoredCores();
        } else {
          String errorMessage = responseData['error'] ?? 'Unknown error occurred';
          
          // Check if it's a tier validation error and show a helpful message
          if (errorMessage.contains('Cannot consume') && errorMessage.contains('cores to equal')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tier Mismatch', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(errorMessage, style: TextStyle(fontSize: 12)),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 8),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $errorMessage'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error consuming core: HTTP ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      print('Error consuming core: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error consuming core: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSlotCoreDialog(String tierName, int coreCount) {
    final characterTier = widget.character.cultivationTier;
    final canUse = _canUseCoreTier(tierName, characterTier);
    final conversionInfo = _getTierConversionInfo(tierName, characterTier);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Slot $tierName Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canUse) ...[
                Text('What would you like to slot this core for?'),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _slotCore(tierName, 'affinity');
                  },
                  child: Text('Affinity Points'),
                ),
              ] else ...[
                Icon(Icons.block, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  'Cannot Slot $tierName Core',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'You are $characterTier tier and cannot slot $tierName cores directly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    conversionInfo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(canUse ? 'Cancel' : 'OK'),
            ),
          ],
        );
      },
    );
  }

    Future<void> _slotCore(String tierName, String usageType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User not authenticated')),
        );
        return;
      }

      // Show loading feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Text('Slotting $tierName core...'),
            ],
          ),
          duration: Duration(seconds: 30), // Long duration in case of delays
        ),
      );

      final characterNumber = widget.character.characterNumber.toString() ?? 'main';
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(AppConfig.useStoredCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'characterNumber': characterNumber,
          'tier': tierName,
          'usageType': usageType,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$tierName core slotted successfully for $usageType!'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh the stored cores display
          _showStoredCores();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${responseData['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error slotting core: HTTP ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      print('Error slotting core: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error slotting core: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTradeCoreDialog(String tierName, int coreCount) {
    final characterTier = widget.character.cultivationTier;
    final canUse = _canUseCoreTier(tierName, characterTier);
    final conversionInfo = _getTierConversionInfo(tierName, characterTier);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Trade $tierName Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canUse) ...[
                Text('You have $coreCount $tierName core(s) available to trade.'),
                SizedBox(height: 16),
                Text('To trade this core:'),
                SizedBox(height: 8),
                Text('1. Scan the QR code of the player you want to trade with'),
                Text('2. Select their character'),
                Text('3. Confirm the trade'),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _startTradeFlow(tierName, coreCount);
                  },
                  icon: Icon(Icons.qr_code_scanner),
                  label: Text('Start Trade'),
                ),
              ] else ...[
                Icon(Icons.block, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  'Cannot Trade $tierName Core',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'You are $characterTier tier and cannot trade $tierName cores directly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    conversionInfo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(canUse ? 'Cancel' : 'OK'),
            ),
          ],
        );
      },
    );
  }

  void _showTierCores(String tierName, List<dynamic> cores, int tier) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.circle, color: _getTierColor(tier)),
              SizedBox(width: 8),
              Text('$tierName Cores'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Text(
                  'You have ${cores.length} $tierName core${cores.length == 1 ? '' : 's'} available',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      // Consume Core Option
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.auto_fix_high, color: Colors.orange),
                          title: Text('Consume Core'),
                          subtitle: Text('Use core for cultivation or crafting'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showConsumeCoreDialog(tierName, cores.length);
                          },
                        ),
                      ),
                      // Slot Core Option
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.settings, color: Colors.blue),
                          title: Text('Slot Core'),
                          subtitle: Text('Equip core in equipment or skills'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showSlotCoreDialog(tierName, cores.length);
                          },
                        ),
                      ),
                      // Trade Core Option
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.swap_horiz, color: Colors.green),
                          title: Text('Trade Core'),
                          subtitle: Text('Trade with another player'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showTradeCoreDialog(tierName, cores.length);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Back'),
            ),
          ],
        );
      },
    );
  }

  void _startTradeFlow(String tierName, int coreCount) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => TradeQRScannerPage(
          tierName: tierName,
          coreCount: coreCount,
          fromCharacter: widget.character,
        ),
      ),
    );
    
    // Handle the scanned data if we got a result
    if (result != null) {
      _processTradeQRData(result, tierName, coreCount);
    }
  }

  void _processTradeQRData(Map<String, dynamic> qrData, String tierName, int coreCount) async {
    try {
      // Show loading modal
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Loading player characters...'),
              ],
            ),
          );
        },
      );

      // Handle profile QR code format (from generateQRCode function)
      if (qrData.containsKey('game') && qrData['game'] == 'Crucible' && qrData.containsKey('playerUid')) {
        final String uid = qrData['playerUid'];
        if (uid.isEmpty) {
          Navigator.of(context).pop(); // Close loading dialog
          _showError('QR code has empty player ID. Please scan a valid player QR code.');
          return;
        }
        
        // Fetch the player's characters from the backend
        _fetchPlayerCharactersForTrade(uid, qrData['playerName'] ?? 'Unknown Player', tierName, coreCount);
        return;
      }
      
      // Handle old format with direct character data
      if (qrData.containsKey('uid') && qrData.containsKey('characters')) {
        final String uid = qrData['uid'];
        if (uid.isEmpty) {
          Navigator.of(context).pop(); // Close loading dialog
          _showError('QR code has empty player ID. Please scan a valid player QR code.');
          return;
        }
        
        // Check if trying to trade with yourself
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.uid == uid) {
          Navigator.of(context).pop(); // Close loading dialog
          _showError('You cannot trade cores with yourself. Please scan another player\'s QR code.');
          return;
        }
        
        Navigator.of(context).pop(); // Close loading dialog
        _showCharacterSelectionForTrade(qrData, tierName, coreCount);
        return;
      }
      
      Navigator.of(context).pop(); // Close loading dialog
      _showError('This QR code is not a valid player profile. Please scan a player QR code from the Profile page.');
    } catch (e) {
      print('QR Code processing error: $e');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close loading dialog
      }
      _showError('Invalid QR code format. Please scan a valid player QR code.\n\nError: ${e.toString()}');
    }
  }

  void _fetchPlayerCharactersForTrade(String playerUid, String playerName, String tierName, int coreCount) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.of(context).pop(); // Close loading dialog
        _showError('You must be logged in to trade cores.');
        return;
      }

      // Check if trying to trade with yourself
      if (user.uid == playerUid) {
        Navigator.of(context).pop(); // Close loading dialog
        _showError('You cannot trade cores with yourself. Please scan another player\'s QR code.');
        return;
      }

      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(AppConfig.getPlayerCharactersUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({
          'targetPlayerUid': playerUid,
        }),
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          final characters = responseData['characters'] ?? [];
          if (characters.isEmpty) {
            _showError('This player has no characters available for trading.');
            return;
          }
          
          // Show character selection with fetched data
          _showCharacterSelectionForTrade({
            'uid': playerUid,
            'characters': characters,
            'playerName': playerName,
          }, tierName, coreCount);
        } else {
          _showError(responseData['error'] ?? 'Failed to fetch player characters');
        }
      } else {
        final errorData = json.decode(response.body);
        _showError(errorData['error'] ?? 'Failed to fetch player characters');
      }
    } catch (e) {
      print('Error fetching player characters: $e');
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error fetching player characters: ${e.toString()}');
    }
  }

  void _showCharacterSelectionForTrade(Map<String, dynamic> playerData, String tierName, int coreCount) {
    final String targetPlayerUid = playerData['uid'];
    final List<dynamic> characters = playerData['characters'] ?? [];

    if (characters.isEmpty) {
      _showError('This player has no characters available for trading.');
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Target Character'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: characters.map<Widget>((character) {
              return ListTile(
                title: Text('Character ${character['characterNumber']}'),
                subtitle: Text(character['characterName'] ?? 'Unknown'),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmTrade(tierName, coreCount, targetPlayerUid, character['characterNumber'].toString());
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _confirmTrade(String tierName, int coreCount, String targetPlayerUid, String targetCharacterNumber) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text('Confirm Trade', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trade Details:', style: TextStyle(color: Colors.white)),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From: ${widget.character.characterName} (Character ${widget.character.characterNumber})', style: TextStyle(color: Colors.white)),
                    Text('To: Unknown (Character $targetCharacterNumber)', style: TextStyle(color: Colors.white)),
                    Text('Item: 1 $tierName Core', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text('Are you sure you want to proceed with this trade?', style: TextStyle(color: Colors.white)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _executeTradeFromCharacterSheet(targetPlayerUid, targetCharacterNumber, tierName);
              },
              child: Text('Confirm Trade', style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  void _executeTradeFromCharacterSheet(String targetPlayerUid, String targetCharacterNumber, String tierName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('You must be logged in to trade cores.');
        return;
      }

      final idToken = await user.getIdToken();
      final requestBody = {
        'tier': tierName,
        'fromCharacterNumber': widget.character.characterNumber.toString(),
        'toPlayerUid': targetPlayerUid,
        'toCharacterNumber': targetCharacterNumber,
      };
      
      print('🔄 Sending trade request: $requestBody');
      
      final response = await http.post(
        Uri.parse(AppConfig.tradeMonsterCoreUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          _showTradeSuccess(responseData);
        } else {
          _showError(responseData['error'] ?? 'Trade failed');
        }
      } else {
        print('❌ Trade HTTP error ${response.statusCode}: ${response.body}');
        try {
          final errorData = json.decode(response.body);
          _showError(errorData['error'] ?? 'Trade failed with status ${response.statusCode}');
        } catch (jsonError) {
          _showError('Trade failed with status ${response.statusCode}. Response: ${response.body}');
        }
      }
    } catch (e) {
      print('❌ Trade execution error: $e');
      _showError('Error executing trade: $e');
    }
  }

  void _showTradeSuccess(Map<String, dynamic> responseData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Trade Successful'),
            ],
          ),
          content: Text(responseData['message'] ?? 'Core traded successfully!'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Refresh the stored cores display
                setState(() {});
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showCoreOptions(Map<String, dynamic> core, String tierName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Core #${core['uniqueNumber']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                color: _getTierColor(core['tier']),
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                '$tierName Tier Monster Core',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('What would you like to do with this core?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _useStoredCore(core);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('Use Core'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _tradeStoredCore(core);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: Text('Trade Core'),
            ),
          ],
        );
      },
    );
  }

  void _useStoredCore(Map<String, dynamic> core) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Use Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.build, color: Colors.blue, size: 48),
              SizedBox(height: 16),
              Text(
                'How would you like to use this core?',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _processStoredCoreUsage(core, 'build');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Consume for Build'),
                ),
              ),
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _processStoredCoreUsage(core, 'affinity');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Slot for Affinity Points'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _processStoredCoreUsage(Map<String, dynamic> core, String usageType) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Using Core...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing core usage...'),
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
      final response = await http.post(
        Uri.parse(AppConfig.useStoredCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'characterId': widget.character.id,
          'coreId': core['coreId'],
          'usageType': usageType,
        }),
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(responseData['message']),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${responseData['error']}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error using core: HTTP ${response.statusCode}')),
        );
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error using stored core: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error using core: $error')),
      );
    }
  }

  void _tradeStoredCore(Map<String, dynamic> core) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Trade Core'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, color: Colors.purple, size: 48),
              SizedBox(height: 16),
              Text(
                'Scan another player\'s QR code to trade this core to them.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startTradeScanner(core);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: Text('Start Scanning'),
            ),
          ],
        );
      },
    );
  }

  void _showError(String message) {
    print('❌ ERROR in Character Sheet: $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _startTradeScanner(Map<String, dynamic> core) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TradeScannerPage(
          onQRCodeScanned: (qrData) => _handleTradeQRCode(qrData, core),
        ),
      ),
    );
  }

  void _handleTradeQRCode(String qrData, Map<String, dynamic> core) {
    // Close the scanner
    Navigator.of(context).pop();
    
    // Process the QR code
    _processTradeQRCode(qrData, core);
  }

  void _processTradeQRCode(String qrData, Map<String, dynamic> core) async {
    try {
      // Parse the QR data to extract user information
      // User profile QR codes should contain email or player UID
      String? targetPlayerUid;
      String? targetPlayerEmail;
      
      // Try to parse as JSON first (in case it's a structured QR code)
      try {
        final qrJson = json.decode(qrData);
        targetPlayerUid = qrJson['uid'];
        targetPlayerEmail = qrJson['email'];
      } catch (e) {
        // If not JSON, treat as plain email
        if (qrData.contains('@')) {
          targetPlayerEmail = qrData.trim();
        } else {
          _showError('Invalid QR code. Please scan a user profile QR code.');
          return;
        }
      }

      // Show loading while we fetch target player's characters
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Finding Player...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Looking up player characters...'),
              ],
            ),
          );
        },
      );

      // Get the target player's characters
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('User not authenticated');
        return;
      }

      final idToken = await user.getIdToken();
      
      // Call a Firebase function to get target player's characters
      final response = await http.post(
        Uri.parse(AppConfig.getPlayerCharactersUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'targetPlayerEmail': targetPlayerEmail,
          'targetPlayerUid': targetPlayerUid,
        }),
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          final targetCharacters = responseData['characters'] as List<dynamic>;
          final targetPlayerUidResponse = responseData['playerUid'] as String;
          
          if (targetCharacters.isEmpty) {
            _showError('Target player has no characters available for trading.');
            return;
          }

          _showTargetCharacterSelection(core, targetCharacters, targetPlayerUidResponse);
        } else {
          _showError('Error finding player: ${responseData['error']}');
        }
      } else {
        _showError('Error finding player: HTTP ${response.statusCode}');
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error processing trade QR code: $error');
      _showError('Error processing QR code: $error');
    }
  }

  void _showTargetCharacterSelection(Map<String, dynamic> core, List<dynamic> targetCharacters, String targetPlayerUid) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Target Character'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Which character should receive Core #${core['uniqueNumber']}?',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: targetCharacters.length,
                    itemBuilder: (context, index) {
                      final character = targetCharacters[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.person, color: Colors.purple),
                          title: Text(character['playerName'] ?? 'Unknown'),
                          subtitle: Text('Player #${character['playerNumber'] ?? 'Unknown'}'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _executeTrade(core, targetPlayerUid, character['id']);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _executeTrade(Map<String, dynamic> core, String targetPlayerUid, String targetCharacterId) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Trading Core...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing trade...'),
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
        _showError('User not authenticated');
        return;
      }

      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(AppConfig.tradeStoredCoreUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'fromCharacterId': widget.character.id,
          'toPlayerUid': targetPlayerUid,
          'toCharacterId': targetCharacterId,
          'coreId': core['coreId'],
        }),
      );

      // Close loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true) {
          _showTradeSuccess(responseData['message'] ?? 'Trade completed successfully!');
        } else {
          _showError('Error: ${responseData['error']}');
        }
      } else {
        _showError('Error executing trade: HTTP ${response.statusCode}');
      }

    } catch (error) {
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      print('Error executing trade: $error');
      _showError('Error executing trade: $error');
    }
  }


  Future<void> _callCalculateCharacterFunction() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ User not authenticated for calculate character');
        return;
      }

      final idToken = await user.getIdToken();
      final character = widget.character;
      
      // Use effective UID (impersonated user if impersonating, otherwise current user)
      final playerUid = ImpersonationService.getEffectiveUid() ?? user.uid;
      print('🔄 Calling calculate character for UID: $playerUid (impersonating: ${ImpersonationService.isImpersonating})');
      print('🔍 CLIENT DEBUG - Character cultivation tier: ${character.cultivationTier}');
      print('🔍 CLIENT DEBUG - Character number: ${character.characterNumber}');

      final response = await http.post(
        Uri.parse(AppConfig.calculateCharacterUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'playerUid': playerUid,
          'characterNumber': character.characterNumber.toString(),
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('🔍 CLIENT DEBUG - Calculate character response: $responseData');
        if (responseData['ok'] == true) {
          print('✅ Character calculations updated');
          print('📊 Advancement errors: ${responseData['advancementErrors'] ?? 'unknown'}');
          print('📊 Hit point rows detected: ${responseData['detectedHitPointRows'] ?? 'unknown'}');
          print('📊 Essence calculated: ${responseData['essenceCalculated'] ?? 'unknown'}');
          
          // Display ascension information if available
          if (responseData['ascensionInfo'] != null) {
            final ascensionInfo = responseData['ascensionInfo'];
            print('🔍 ASCENSION INFO FROM SERVER:');
            print('🔍   Cultivation Tier: ${ascensionInfo['cultivationTier']}');
            print('🔍   Tier Index: ${ascensionInfo['tierIndex']}');
            print('🔍   Ascension Count: ${ascensionInfo['ascensionCount']} (Tier Index - 1)');
            print('🔍   Ascension Adjustment: ${ascensionInfo['ascensionAdjustment']} (Count * 2)');
            print('🔍   Cultivation Tier Order: ${ascensionInfo['cultivationTierOrder']}');
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Character calculations updated (${responseData['advancementErrors'] ?? 0} errors)'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          print('❌ Calculate character failed: ${responseData['error']}');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Calculate character failed: ${responseData['error']}'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        print('❌ Calculate character HTTP error: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Calculate character HTTP error: ${response.statusCode}'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error calling calculate character: $e');
    }
  }

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
              Text('Checking for updates...'),
            ],
          ),
          duration: Duration(seconds: 2),
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
      
      Character? newCharacter;
      
      // If impersonating, use API to get character data (can't access Storage directly)
      if (ImpersonationService.isImpersonating) {
        final effectiveUid = ImpersonationService.getEffectiveUid();
        if (effectiveUid != null) {
          print('🎭 Loading impersonated character via API for sync');
          newCharacter = await _loadCharacterForSync(effectiveUid);
        }
      } else {
        // Normal flow: load from Firebase Storage
        final ref = FirebaseStorage.instance.ref().child('users/$effectiveEmail/pc.json');
        final data = await ref.getData();
        
        if (data != null) {
          final jsonString = utf8.decode(data);
          final jsonMap = json.decode(jsonString);
          newCharacter = Character.fromJson(jsonMap);
        }
      }
      
      if (newCharacter != null) {
        
        // Always trigger calculateCharacter function on refresh
        await _callCalculateCharacterFunction();
        
        // Check if the character data has actually changed
        if (newCharacter.generatedAt != widget.character.generatedAt) {
          // Character data has been updated - refresh the page
          if (context.mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CharacterSheetPage(character: newCharacter!),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Character data updated!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // No changes
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('ℹ️ Character data is up to date'),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ No character data found')),
          );
        }
      }
    } catch (e) {
      print('Error syncing character data: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to sync character data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Character?> _loadCharacterForSync(String targetUid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ No user found for sync');
        return null;
      }

      // Get character list first
      final idToken = await user.getIdToken();
      final response = await http.get(
        Uri.parse('${AppConfig.getCharactersUrl}?impersonateUid=$targetUid'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['ok'] == true && responseData['characters'] != null) {
          final characters = responseData['characters'] as List;
          if (characters.isNotEmpty) {
            // Get the character ID and load full details
            final characterData = characters[0];
            final characterId = characterData['id'] as String;
            
            // Load full character details
            final detailResponse = await http.get(
              Uri.parse('${AppConfig.getCharacterByIdUrl}?characterId=$characterId'),
              headers: {
                'Authorization': 'Bearer $idToken',
                'Content-Type': 'application/json',
              },
            );

            if (detailResponse.statusCode == 200) {
              final detailData = json.decode(detailResponse.body);
              if (detailData['ok'] == true) {
                final characterJson = detailData['character'];
                return Character.fromJson(characterJson);
              }
            }
          }
        }
      }
      
      print('❌ Failed to load character for sync - Status: ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ Error loading character for sync: $e');
      return null;
    }
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

  Color _getCultivationColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'spirit':
        return Colors.green;
      case 'foundation':
        return Colors.blue;
      case 'core':
        return Colors.purple;
      case 'soul':
        return Colors.orange;
      case 'transcendent':
        return Colors.red;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rulesJson == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Character Sheet')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final character = widget.character;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final bool isOtherCharacter = character.playerUid != null && character.playerUid != currentUid;

    return Scaffold(
      backgroundColor: isOtherCharacter ? Colors.grey[900] : Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Character Sheet'),
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
            if (_hasUnsubmittedChanges && !_isEditMode) ...[
              SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showUnsubmittedChanges(context),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.upload,
                    color: Colors.blue,
                    size: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'submit':
                  await _submitAdvancementToGoogleAppScript(context);
                  break;
                case 'cores':
                  _showStoredCores();
                  break;
                case 'sync':
                  _syncCharacterData();
                  break;
                case 'new_sheet':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => NewSheetPage()));
                  break;
                case 'edit':
                  if (!_isEditMode) {
                    // Check if we can enter edit mode
                    final lastSubmissionTimestamp = await _getLastSubmissionTimestamp();
                    final characterGeneratedAt = widget.character.generatedAt;
                    
                    if (lastSubmissionTimestamp != null && characterGeneratedAt != null) {
                      final submissionTime = DateTime.parse(lastSubmissionTimestamp);
                      final characterTime = DateTime.parse(characterGeneratedAt);
                      
                      if (characterTime.isBefore(submissionTime)) {
                        // Character data is older than last submission - show warning
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('Pending Processing'),
                                content: Text('Your character advancement has been submitted and is being processed. Please wait for your character data to be updated before making new changes.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: Text('OK'),
                                  ),
                                ],
                              );
                            },
                          );
                        }
                        return;
                      }
                    }
                    
                    // Enter edit mode
                    setState(() {
                      _isEditMode = true;
                      _originalUnspentAffinityPoints = character.unspentAffinityPoints;
                      _originalUnspentBuildPoints = character.build.unspent;
                      _currentUnspentAffinityPoints = character.unspentAffinityPoints;
                      _currentUnspentBuildPoints = character.build.unspent;
                    });
                  } else {
                    // Exit edit mode
                    setState(() {
                      _isEditMode = false;
                    });
                  }
                  break;
              }
            },
            itemBuilder: (context) {
              print('DEBUG: _hasUnsubmittedChanges = $_hasUnsubmittedChanges, _isEditMode = $_isEditMode');
              return [
                if (_hasUnsubmittedChanges && !_isEditMode)
                  PopupMenuItem(
                    value: 'submit',
                    child: Row(
                      children: [
                        Icon(Icons.upload, size: 20, color: Colors.green),
                        SizedBox(width: 12),
                        Text('Submit Advancement', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'cores',
                  child: Row(
                    children: [
                      Icon(Icons.inventory, size: 20),
                      SizedBox(width: 12),
                      Text('Stored Cores'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sync',
                  child: Row(
                    children: [
                      Icon(Icons.sync, size: 20),
                      SizedBox(width: 12),
                      Text('Sync Character Data'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'new_sheet',
                  child: Row(
                    children: [
                      Icon(Icons.description, size: 20),
                      SizedBox(width: 12),
                      Text('New Sheet (from DB)'),
                    ],
                  ),
                ),
                if (_isSuperAdmin)
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(_isEditMode ? Icons.save : Icons.edit, size: 20),
                      SizedBox(width: 12),
                      Text(_isEditMode ? 'Exit Edit Mode' : 'Enter Edit Mode'),
                    ],
                  ),
                ),
              ];
            },
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
            child: SingleChildScrollView(
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
                            ? '${character.build.total} (${character.build.unspent})'
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
                            ? '${character.totalAffinityPoints} (${character.unspentAffinityPoints})'
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
                        onTap: () => _showDRInfo(context),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        label: 'Essence',
                        value: '$currentHP / ${character.hitPoints['total']}',
                        onTap: () => _editCurrentHP(),
                        onBoxTap: _editCurrentHP,
                        showPlusButton: _isEditMode,
                        onPlusPressed: () {
                          _editCurrentHP();
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
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          icon: Icon(Icons.add, color: Colors.amber, size: 20),
                          onPressed: () {
                            _showAvailableAffinities(context);
                          },
                          padding: EdgeInsets.all(8),
                          constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                        ),
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
                  children: (character.affinities.entries.toList()
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
                            availableAffinityPoints: _isEditMode ? character.unspentAffinityPoints : null,
                            onAffinityPointsChanged: _isEditMode ? (newPoints) {
                              setState(() {
                                // Handle affinity points change
                              });
                            } : null,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: 48),
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
                                        SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: IconButton(
                                            icon: Icon(Icons.add, color: Colors.amber, size: 16),
                                            onPressed: () => _showAffinityDetails(
                                              context, 
                                              name, 
                                              detail,
                                              availableAffinityPoints: character.unspentAffinityPoints,
                                              onAffinityPointsChanged: (newPoints) {
                                                setState(() {
                                                  // Handle affinity points change
                                                });
                                              },
                                            ),
                                            padding: EdgeInsets.all(4),
                                            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
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
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          icon: Icon(Icons.add, color: Colors.amber, size: 20),
                          onPressed: () {
                            _showAvailableAffinitiesForSkills(context);
                          },
                          padding: EdgeInsets.all(8),
                          constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                        ),
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
                    _saveSkillSortPreference(value!);
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
                      _showSkillDetails(context, skill, onBuildPointsChanged: _isEditMode ? (newPoints) {
                        setState(() {
                          _currentUnspentBuildPoints = newPoints;
                        });
                      } : null);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: (Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: hasUnsubmittedChanges ? Colors.amber : Colors.white,
                                  decoration: TextDecoration.none,
                                )) ?? const TextStyle(color: Colors.white, decoration: TextDecoration.none),
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
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: IconButton(
                                icon: Icon(Icons.add, color: Colors.amber, size: 20),
                                onPressed: () {
                                  _showSkillDetails(context, skill, onBuildPointsChanged: _isEditMode ? (newPoints) {
                                    setState(() {
                                      _currentUnspentBuildPoints = newPoints;
                                    });
                                } : null);
                                },
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
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
            ),
          ],
        ),
    );
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

  Future<void> _loadSkillSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final sortPreference = prefs.getString('skill_sort_preference');
    if (sortPreference != null) {
      setState(() {
        _selectedSkillSort = sortPreference;
      });
    }
  }

  Future<void> _saveSkillSortPreference(String preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skill_sort_preference', preference);
  }

  void _showUnsubmittedChanges(BuildContext context) {
    if (_unsubmittedAdvancement == null) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Unsubmitted Changes'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_unsubmittedAdvancement!.affinityChanges.isNotEmpty) ...[
                  Text('Affinity Changes:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._unsubmittedAdvancement!.affinityChanges.map((change) => 
                    Text('• ${change.affinityName}: ${change.adjustment} (${change.levelChange > 0 ? '+' : ''}${change.levelChange})')
                  ),
                  SizedBox(height: 8),
                ],
                if (_unsubmittedAdvancement!.skillChanges.isNotEmpty) ...[
                  Text('Skill Changes:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._unsubmittedAdvancement!.skillChanges.map((change) => 
                    Text('• ${change.skillName}: ${change.levelChange > 0 ? '+' : ''}${change.levelChange} level')
                  ),
                  SizedBox(height: 8),
                ],
                if (_unsubmittedAdvancement!.essenceChanges.isNotEmpty) ...[
                  Text('Essence Changes:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._unsubmittedAdvancement!.essenceChanges.map((change) => 
                    Text('• Essence: ${change.essenceAdjustment > 0 ? '+' : ''}${change.essenceAdjustment}')
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearUnsubmittedAdvancement();
              },
              child: Text('Clear Changes'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _submitAdvancementToGoogleAppScript(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text('Submit Changes'),
            ),
          ],
        );
      },
    );
  }

  // Helper methods

  Widget _StatBox({required String label, required String value, required VoidCallback onTap, bool isEditMode = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Text(label, style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
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
        ),
      ],
    );
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
            border: Border.all(color: Colors.white),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onBoxTap,
                child: Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (showPlusButton && onPlusPressed != null) ...[
                SizedBox(width: 8),
                GestureDetector(
                  onTap: onPlusPressed,
                  child: Icon(Icons.add, color: Colors.amber, size: 16),
                ),
              ],
            ],
          ),
        ),
      ],
    );
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


  void _showAffinityPointInfo(BuildContext context) {
    final affinityPoints = widget.character.affinityPoints;
    final buffer = StringBuffer();
    
    // Show regular AP amount
    final apAmount = affinityPoints['amount'] ?? widget.character.totalAffinityPoints;
    buffer.writeln('Affinity Points: $apAmount');
    
    // Show Perfect Cultivation Points
    final perfectCultivation = widget.character.perfectCultivationPoints;
    if (perfectCultivation > 0) {
      buffer.writeln('Perfect Cultivation Points: $perfectCultivation');
    }
    
    buffer.writeln('');
    buffer.writeln('Total Affinity Points: ${widget.character.totalAffinityPoints}');
    buffer.writeln('Unspent: ${widget.character.unspentAffinityPoints}');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Affinity Points Breakdown'),
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

  void _showDRInfo(BuildContext context) {
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

  void _showHitPointInfo(BuildContext context) {
    final hitPoints = widget.character.hitPoints;
    final buffer = StringBuffer();
    
    buffer.writeln('Total HP: ${hitPoints['total']}');
    buffer.writeln('Current HP: $currentHP');
    buffer.writeln('');
    
    if (hitPoints.containsKey('hitPointsByTier')) {
      final byTier = hitPoints['hitPointsByTier'] as Map<String, dynamic>?;
      if (byTier != null) {
        buffer.writeln('By Tier:');
        byTier.forEach((tier, points) {
          buffer.writeln('• $tier: $points');
        });
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hit Points Breakdown'),
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
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              icon: Icon(Icons.remove, color: Colors.amber, size: 20),
                              onPressed: () {
                                final originalExtra = widget.character.hitPoints['extra'] ?? 0;
                                if (tempExtra > originalExtra) {
                                  setState(() => tempExtra--);
                                }
                              },
                              padding: EdgeInsets.all(8),
                              constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                            ),
                          ),
                        SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: Text(
                            'Direct Buy: $tempExtra', 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(width: 12),
                        if (_isEditMode)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              icon: Icon(Icons.add, color: Colors.amber, size: 20),
                              onPressed: () {
                                if (tempExtra < maxDirectBuy) {
                                  setState(() => tempExtra++);
                                }
                              },
                              padding: EdgeInsets.all(8),
                              constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                            ),
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

  int _getDRForTier(String tier) {
    final key = 'dr${tier[0].toUpperCase()}${tier.substring(1).toLowerCase()}';
    final raw = widget.character.dr[key] ?? 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
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

  void _showAvailableAffinities(BuildContext context) async {
    // Get available affinities from rules
    List<String> availableAffinities = [];
    
    try {
      final cachedRules = await RulesService.loadCachedRules();
      if (cachedRules != null) {
        final rules = json.decode(cachedRules);
        final affinities = rules['Affinity'] as List<dynamic>? ?? [];
        
        // Get all affinity names
        for (final affinity in affinities) {
          availableAffinities.add(affinity['Name']);
        }
      }
    } catch (e) {
      print('Error loading available affinities: $e');
    }

    // Filter out affinities the character already has
    final existingAffinityNames = widget.character.affinities.keys.toSet();
    availableAffinities = availableAffinities.where((name) => 
      !existingAffinityNames.contains(name)
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
              final affinityName = availableAffinities[index];
              return ListTile(
                title: Text(affinityName),
                onTap: () {
                  Navigator.pop(context);
                  _addNewAffinity(context, affinityName);
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
    // Create a new affinity with level 0
    final newAffinity = AffinityDetail(
      effectLevel: 0,
      tiers: {'Iron': 0},
    );

    // Open affinity details dialog for the new affinity
    _showAffinityDetails(context, affinityName, newAffinity, 
      availableAffinityPoints: widget.character.unspentAffinityPoints,
      onAffinityPointsChanged: (newPoints) {
        setState(() {
          // Handle affinity points change
        });
      },
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
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
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
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Icon(Icons.remove, color: Colors.amber, size: 16),
                                          ),
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          '$level', 
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(width: 2),
                                        GestureDetector(
                                          onTap: () {
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
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Icon(Icons.add, color: Colors.amber, size: 16),
                                          ),
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

  void _showAvailableAffinitiesForSkills(BuildContext context) async {
    // Get all affinities the character has (including unsubmitted ones)
    final allAffinities = {'Common', widget.character.race, ...widget.character.affinities.keys}
        .toList();
    
    if (allAffinities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No affinities available for skills')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Select Affinity for New Skill'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: allAffinities.length,
            itemBuilder: (context, index) {
              final affinityName = allAffinities[index];
              return ListTile(
                title: Text(affinityName),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _showAvailableSkillsForAffinity(context, affinityName);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
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
        if (affinityName == 'Common') {
          // Include Common Skills
          final commonSkills = rules['Common Skills'] as List<dynamic>? ?? [];
          for (final skill in commonSkills) {
            availableSkills.add({
              'name': skill['Name'],
              'type': 'Common',
              'frequency': skill['Frequency'] ?? 'At Will',
              'delivery': skill['Delivery'] ?? 'None',
            });
          }
        } else if (affinityName == widget.character.race) {
          // Include Race Skills for the character's race
          final races = rules['Races'] as List<dynamic>? ?? [];
          final race = races.firstWhere(
            (r) => r['Name'] == widget.character.race,
            orElse: () => null,
          );
          if (race != null) {
            final raceSkills = race['Race Skills'] as List<dynamic>? ?? [];
            for (final skill in raceSkills) {
              availableSkills.add({
                'name': skill['Name'],
                'type': widget.character.race,
                'frequency': skill['Frequency'] ?? 'At Will',
                'delivery': skill['Delivery'] ?? 'None',
              });
            }
          }
        } else {
          // Default: Affinity Skills
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
      }
    } catch (e) {
      print('Error loading available skills: $e');
    }

    // Filter out skills the character already has
    final existingSkillNames = widget.character.skills.map((s) => s.name).toSet();
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
      builder: (dialogContext) => AlertDialog(
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
                  Navigator.of(dialogContext).pop();
                  _addNewSkill(context, skill);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
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
        // Handle build points change
      });
    } : null);
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
                  child: Builder(
                    builder: (context) {
                      // Determine if we should show the Verbal tab
                      final hasVerbals = verbal.isNotEmpty;
                      final tabCount = hasVerbals ? 3 : 2;
                      final initialIndex = _isEditMode ? (hasVerbals ? 2 : 1) : (hasVerbals ? 0 : 0);
                      
                      return DefaultTabController(
                        length: tabCount,
                        initialIndex: initialIndex,
                        child: Column(
                          children: [
                            TabBar(
                              tabs: hasVerbals 
                                ? [
                                    Tab(text: 'Verbal'),
                                    Tab(text: 'Rules'),
                                    Tab(text: 'Cost'),
                                  ]
                                : [
                                    Tab(text: 'Rules'),
                                    Tab(text: 'Cost'),
                                  ],
                              labelColor: Colors.white,
                            ),
                            Expanded(
                              child: TabBarView(
                                children: hasVerbals
                                  ? [
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
                                                  Container(
                                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        SizedBox(
                                                          width: 48,
                                                          height: 48,
                                                          child: IconButton(
                                                            icon: Icon(Icons.remove, color: Colors.amber, size: 24),
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
                                                            padding: EdgeInsets.all(12),
                                                            constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                                          ),
                                                        ),
                                                        SizedBox(width: 20),
                                                        SizedBox(
                                                          width: 80,
                                                          child: Text(
                                                            'Level: $editableSkillLevel',
                                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                        SizedBox(width: 20),
                                                        SizedBox(
                                                          width: 48,
                                                          height: 48,
                                                          child: IconButton(
                                                            icon: Icon(
                                                              Icons.add, 
                                                              color: (skill.frequency == 'At Will' || skill.frequency == 'Passive') 
                                                                  ? Colors.grey 
                                                                  : Colors.amber, 
                                                              size: 24
                                                            ),
                                                            onPressed: () {
                                                              // Check if this is an At Will or Passive skill
                                                              if (skill.frequency == 'At Will' || skill.frequency == 'Passive') {
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Cannot increase ${skill.frequency} skills'),
                                                                    backgroundColor: Colors.orange,
                                                                  ),
                                                                );
                                                              } else if (editableSkillLevel >= maxLevel) {
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Cannot exceed maximum level of $maxLevel'),
                                                                    backgroundColor: Colors.red,
                                                                  ),
                                                                );
                                                              } else if (currentAvailableBuildPoints >= costDifference) {
                                                                setState(() {
                                                                  editableSkillLevel++;
                                                                  currentAvailableBuildPoints -= costDifference.toInt();
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
                                                            padding: EdgeInsets.all(12),
                                                            constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
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
                                  ]
                                  : [
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
                                                  Container(
                                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        SizedBox(
                                                          width: 48,
                                                          height: 48,
                                                          child: IconButton(
                                                            icon: Icon(Icons.remove, color: Colors.amber, size: 24),
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
                                                            padding: EdgeInsets.all(12),
                                                            constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                                          ),
                                                        ),
                                                        SizedBox(width: 20),
                                                        SizedBox(
                                                          width: 80,
                                                          child: Text(
                                                            'Level: $editableSkillLevel',
                                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                        SizedBox(width: 20),
                                                        SizedBox(
                                                          width: 48,
                                                          height: 48,
                                                          child: IconButton(
                                                            icon: Icon(
                                                              Icons.add, 
                                                              color: (skill.frequency == 'At Will' || skill.frequency == 'Passive') 
                                                                  ? Colors.grey 
                                                                  : Colors.amber, 
                                                              size: 24
                                                            ),
                                                            onPressed: () {
                                                              // Check if this is an At Will or Passive skill
                                                              if (skill.frequency == 'At Will' || skill.frequency == 'Passive') {
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Cannot increase ${skill.frequency} skills'),
                                                                    backgroundColor: Colors.orange,
                                                                  ),
                                                                );
                                                              } else if (editableSkillLevel >= maxLevel) {
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Cannot exceed maximum level of $maxLevel'),
                                                                    backgroundColor: Colors.red,
                                                                  ),
                                                                );
                                                              } else if (currentAvailableBuildPoints >= costDifference) {
                                                                setState(() {
                                                                  editableSkillLevel++;
                                                                  currentAvailableBuildPoints -= costDifference.toInt();
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
                                                            padding: EdgeInsets.all(12),
                                                            constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
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
                    );
                  },
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

  // Helper function to get skill details from rules
  Future<Map<String, dynamic>?> getSkillDetailsFromRules(String skillName, String skillType, String characterRace) async {
    try {
      final cachedRules = await RulesService.loadCachedRules();
      if (cachedRules != null) {
        final rules = json.decode(cachedRules);
        
        // Search Common Skills
        if (skillType == 'Common') {
          final skills = rules['Common Skills'] as List<dynamic>? ?? [];
          final skill = skills.firstWhere(
            (s) => s['Name'] == skillName,
            orElse: () => null,
          );
          if (skill != null) {
            return Map<String, dynamic>.from(skill);
          }
        }
        
        // Search Race Skills
        final races = rules['Races'] as List<dynamic>? ?? [];
        final race = races.firstWhere(
          (r) => r['Name'] == characterRace,
          orElse: () => null,
        );
        
        if (race != null && race['Race Skills'] != null) {
          final skills = race['Race Skills'] as List<dynamic>;
          final skill = skills.firstWhere(
            (s) => s['Name'] == skillName,
            orElse: () => null,
          );
          if (skill != null) {
            return Map<String, dynamic>.from(skill);
          }
        }
        
        // Try to find in Affinity Skills
        final affinitySkills = rules['Affinity Skills'] as List<dynamic>? ?? [];
        final affinitySkill = affinitySkills.firstWhere(
          (s) => s['Name'] == skillName && s['Affinity'] == skillType,
          orElse: () => null,
        );
        
        if (affinitySkill != null) {
          return Map<String, dynamic>.from(affinitySkill);
        }
        
        // Try to find in regular Skills
        final skills = rules['Skill'] as List<dynamic>? ?? [];
        final skill = skills.firstWhere(
          (s) => s['Name'] == skillName,
          orElse: () => null,
        );
        
        if (skill != null) {
          return Map<String, dynamic>.from(skill);
        }
      }
    } catch (e) {
      print('Error loading skill details: $e');
    }
    
    return null;
  }
}

// Removed old placeholder DeathTimerPage; real implementation is in pages/death_timer_page.dart

// QR Code Display Widget
class _QRCodeDisplay extends StatefulWidget {
  final String email;
  
  const _QRCodeDisplay({required this.email});
  
  @override
  _QRCodeDisplayState createState() => _QRCodeDisplayState();
}

class _QRCodeDisplayState extends State<_QRCodeDisplay> {
  String? qrCodeUrl;
  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _loadQRCode();
  }

  Future<void> _loadQRCode() async {
    try {
      print('🔍 Attempting to load QR code for: ${widget.email}');
      final qrRef = FirebaseStorage.instance.ref().child('users/${widget.email}/qr.png');
      
      // First check if the file exists
      try {
        final metadata = await qrRef.getMetadata();
        print('✅ QR code file exists: ${metadata.name}');
      } catch (e) {
        print('❌ QR code file does not exist: $e');
        setState(() {
          hasError = true;
          isLoading = false;
        });
        return;
      }
      
      final data = await qrRef.getData();
      if (data != null) {
        print('✅ QR code data loaded successfully (${data.length} bytes)');
        
        // Get the download URL instead of using the direct URL
        final downloadUrl = await qrRef.getDownloadURL();
        print('✅ QR code download URL: $downloadUrl');
        
        setState(() {
          qrCodeUrl = downloadUrl;
          isLoading = false;
        });
      } else {
        print('❌ QR code data is null');
        setState(() {
          hasError = true;
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading QR code: $e');
      setState(() {
        hasError = true;
        isLoading = false;
      });
    }
  }

  void _showQRCode(BuildContext context) {
    if (qrCodeUrl == null) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('QR Code'),
          content: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                qrCodeUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    print('✅ Enlarged image loaded successfully');
                    return child;
                  }
                  print('🔄 Enlarged image loading: ${loadingProgress.expectedTotalBytes != null ? (loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! * 100).round() : 0}%');
                  return Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  print('❌ Enlarged image error: $error');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code, size: 64, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'QR Code not available',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                },
              ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: isLoading ? null : () => _showQRCode(context),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isLoading
                  ? Center(child: CircularProgressIndicator())
                  : hasError
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code, size: 32, color: Colors.grey),
                              SizedBox(height: 4),
                              Text(
                                'QR Code not available',
                                style: TextStyle(color: Colors.grey, fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 4),
                              IconButton(
                                icon: Icon(Icons.refresh, size: 16, color: Colors.blue),
                                onPressed: () {
                                  setState(() {
                                    isLoading = true;
                                    hasError = false;
                                  });
                                  _loadQRCode();
                                },
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                            ],
                          ),
                        )
                      : Image.network(
                          qrCodeUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              print('✅ Image loaded successfully');
                              return child;
                            }
                            print('🔄 Image loading: ${loadingProgress.expectedTotalBytes != null ? (loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! * 100).round() : 0}%');
                            return Center(child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) {
                            print('❌ Image error: $error');
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code, size: 32, color: Colors.grey),
                                  SizedBox(height: 4),
                                  Text(
                                    'QR Code not available',
                                    style: TextStyle(color: Colors.grey, fontSize: 10),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 4),
                                  IconButton(
                                    icon: Icon(Icons.refresh, size: 16, color: Colors.blue),
                                    onPressed: () {
                                      setState(() {
                                        isLoading = true;
                                        hasError = false;
                                      });
                                      _loadQRCode();
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          hasError ? 'Click refresh to retry' : 'Click to enlarge',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Character? character;
  bool isLoading = true;
  bool discordLinked = false;
  String? discordDisplay;
  String? discordLinkCode;
  String? discordInviteUrl;
  String? _discordChannelName;
  static const String _prefsDiscordLinkedKey = 'discord_linked';
  static const String _prefsDiscordDisplayKey = 'discord_display';
  
  // Impersonation state
  bool _isImpersonating = false;
  
  // Timer settings
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  Future<void> _disconnectDiscord() async {
    // Show loading while disconnecting
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Disconnecting...'),
          ],
        ),
      ),
    );
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      final resp = await http.post(
        Uri.parse(AppConfig.disconnectDiscordUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );
      // Close loading dialog if open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (resp.statusCode == 200) {
        setState(() {
          discordLinked = false;
          discordDisplay = null;
          discordLinkCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Discord disconnected')));
      } else {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to disconnect')));
      }
    } catch (_) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error disconnecting')));
    }
  }
  
  Future<void> _loadTimerSettings() async {
    final soundEnabled = await TimerPreferencesService.isSoundEnabled();
    final vibrationEnabled = await TimerPreferencesService.isVibrationEnabled();
    if (mounted) {
      setState(() {
        _soundEnabled = soundEnabled;
        _vibrationEnabled = vibrationEnabled;
      });
    }
  }
  
  Future<void> _toggleSound(bool value) async {
    await TimerPreferencesService.setSoundEnabled(value);
    setState(() {
      _soundEnabled = value;
    });
  }
  
  Future<void> _toggleVibration(bool value) async {
    await TimerPreferencesService.setVibrationEnabled(value);
    setState(() {
      _vibrationEnabled = value;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadCachedDiscordLinkState();
    fetchCharacterFromFirebase();
    _refreshDiscordLinkStatus();
    _loadTimerSettings();
    
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
        
        // If we stopped impersonating, refresh character data
        if (wasImpersonating && !nowImpersonating) {
          print('🔄 ProfilePage (Discord): Impersonation stopped, refreshing character data...');
          fetchCharacterFromFirebase();
        }
      }
    });
  }

  Future<void> _loadCachedDiscordLinkState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedLinked = prefs.getBool(_prefsDiscordLinkedKey);
      final cachedDisplay = prefs.getString(_prefsDiscordDisplayKey);
      if (cachedLinked != null) {
        setState(() {
          discordLinked = cachedLinked;
          discordDisplay = cachedDisplay;
        });
      }
    } catch (_) {}
  }

  Future<bool> fetchCharacterFromFirebase() async {
    try {
      final user = _auth.currentUser;
      final effectiveEmail = ImpersonationService.getEffectiveEmail() ?? user?.email;
      if (effectiveEmail == null) return false;

      final ref = FirebaseStorage.instance.ref().child('users/$effectiveEmail/pc.json');
      final data = await ref.getData();

      if (data != null) {
        final jsonString = utf8.decode(data);
        final jsonMap = json.decode(jsonString);
        final fetchedCharacter = Character.fromJson(jsonMap);
        setState(() {
          character = fetchedCharacter;
          isLoading = false;
        });
        cachedCharacter = fetchedCharacter;
        print('✅ Character updated');
        
        // Also try to download QR code (don't fail if it doesn't exist)
        _downloadQRCode(effectiveEmail);
        
        return true;
      }
    } catch (e) {
      print('❌ Failed to sync character: $e');
    }
    setState(() {
      isLoading = false;
    });
    return false;
  }

  Future<void> _refreshDiscordLinkStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final tokenMaybe = await user.getIdToken();
      final idToken = tokenMaybe ?? '';
      final resp = await http.get(Uri.parse(AppConfig.getDiscordLinkStatusUrl), headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      });
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        final linked = body['linked'] == true;
        final newDisplay = (linked && body['data'] != null)
            ? (body['data']['globalName'] ?? body['data']['username'] ?? 'Discord User')
            : null;
        setState(() {
          discordLinked = linked;
          discordDisplay = newDisplay;
        });
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_prefsDiscordLinkedKey, linked);
          if (newDisplay != null) {
            await prefs.setString(_prefsDiscordDisplayKey, newDisplay);
          } else {
            await prefs.remove(_prefsDiscordDisplayKey);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _connectDiscord() async {
    // Show loading while backend prepares channel and code
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Preparing link...'),
          ],
        ),
      ),
    );
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      final resp = await http.post(
        Uri.parse(AppConfig.createDiscordLinkCodeUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );
      // Close loading dialog if open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        setState(() { 
          discordLinkCode = body['code']; 
          discordInviteUrl = (body['inviteUrl'] is String && (body['inviteUrl'] ?? '').toString().isNotEmpty)
            ? body['inviteUrl']
            : null;
          // Store channel name if present
          final cn = body['channelName'];
          if (cn is String && cn.isNotEmpty) {
            _discordChannelName = cn;
          }
          // Optimistically set linked UI state if we previously knew it was linked
          // (No change here; we just keep the cached state until verification updates it.)
        });
        if (discordLinkCode != null) {
          _showDiscordLinkModal();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to prepare link.')));
      }
    } catch (_) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error preparing link.')));
    }
  }

  Future<bool> _verifyDiscordLink() async {
    // Show loading while verifying
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Verifying...'),
          ],
        ),
      ),
    );
    try {
      final user = _auth.currentUser;
      if (user == null || discordLinkCode == null) return false;
      final idToken = await user.getIdToken();
      final resp = await http.post(
        Uri.parse(AppConfig.verifyDiscordLinkByChannelUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({ 'code': discordLinkCode }),
      );
      if (resp.statusCode == 200) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _refreshDiscordLinkStatus();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Discord linked')));
        return true;
      } else {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Code not found yet. Post the code in the channel and try again.')));
        return false;
      }
    } catch (_) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error verifying. Please try again.')));
      return false;
    }
  }

  void _showDiscordLinkModal() {
    final code = discordLinkCode ?? '';
    final channelName = _discordChannelName ?? '#bot-verification';
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.link),
              SizedBox(width: 8),
              Text('Link Discord'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Follow these steps:'),
              SizedBox(height: 8),
              Text('1) Join our Discord server${discordInviteUrl != null ? ' using the invite link.' : '.'}'),
              if (discordInviteUrl != null) ...[
                SizedBox(height: 6),
                ElevatedButton(
                  onPressed: () {
                    try { html.window.open(discordInviteUrl!, '_blank'); } catch (_) {}
                  },
                  child: Text('Open Discord Invite'),
                ),
              ],
              SizedBox(height: 12),
              Text('2) In the verification channel $channelName, send this code:'),
              SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: 16)),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Code copied')));
                      }
                    },
                    child: Text('Copy Code'),
                  ),
                  SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      try { html.window.open('https://discord.com/app', '_blank'); } catch (_) {}
                    },
                    child: Text('Open Discord'),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text('3) Return here and press Verify.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await _verifyDiscordLink();
                if (mounted && ok) {
                  Navigator.of(ctx).pop();
                }
              },
              child: Text('Verify'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _downloadQRCode(String email) async {
    try {
      final qrRef = FirebaseStorage.instance.ref().child('users/$email/qr.png');
      final data = await qrRef.getData();
      if (data != null) {
        print('✅ QR code downloaded');
        return 'https://storage.googleapis.com/crucible-helper-storage/users/$email/qr.png';
      }
    } catch (e) {
      print('⚠️ QR code not available: $e');
    }
    return null;
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
    final effectiveEmail = ImpersonationService.getEffectiveEmail() ?? user?.email;

    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
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
            child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Signed in as ${effectiveEmail ?? "Unknown"}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            
            // Character Info Section
            if (isLoading)
              CircularProgressIndicator()
            else if (character != null) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'Character Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Player: ${character!.playerName}'),
                    Text('Character: ${character!.characterName}'),
                    Text('Number: ${character!.characterNumber}'),
                    Text('Tier: ${character!.cultivationTier}'),
                    Text('Race: ${character!.race}'),
                  ],
                ),
              ),
              SizedBox(height: 20),
              
              // QR Code Display
              _QRCodeDisplay(email: effectiveEmail ?? ''),
              SizedBox(height: 20),
            ] else ...[
              Text('No character data available', style: TextStyle(color: Colors.grey)),
              SizedBox(height: 20),
            ],
            SizedBox(height: 12),
            // Discord link status and button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link, color: discordLinked ? Colors.green : Colors.grey),
                SizedBox(width: 8),
                Text(discordLinked ? (discordDisplay ?? 'Discord linked') : 'Discord not linked'),
                SizedBox(width: 12),
                if (!discordLinked) ...[
                  ElevatedButton(
                    onPressed: _connectDiscord,
                    child: Text(discordLinkCode == null ? 'Link Discord' : 'Link Discord'),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: _disconnectDiscord,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: Text('Disconnect Discord'),
                  ),
                ],
                if (!discordLinked && discordLinkCode != null) ...[
                  SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _verifyDiscordLink,
                    child: Text('Verify'),
                  ),
                ]
              ],
            ),
            
            SizedBox(height: 20),
            
            // Timer Settings
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade700, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Timer Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(
                      'Sound',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                    subtitle: Text(
                      'Beep when timers complete',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    value: _soundEnabled,
                    onChanged: _toggleSound,
                    activeColor: Colors.cyan,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  SwitchListTile(
                    title: Text(
                      'Vibration',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                    subtitle: Text(
                      'Vibrate on mobile browsers',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    value: _vibrationEnabled,
                    onChanged: _toggleVibration,
                    activeColor: Colors.cyan,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: () async {
                final scaffold = ScaffoldMessenger.of(context);
                final user = _auth.currentUser;
                final email = user?.email;

                // 1. Sync character
                final characterSuccess = await fetchCharacterFromFirebase();
                scaffold.showSnackBar(SnackBar(
                  content: Text(characterSuccess
                      ? '✅ Character synced'
                      : '❌ Failed to sync character'),
                ));

                // 2. Sync QR code
                if (email != null) {
                  try {
                    await _downloadQRCode(email);
                    scaffold.showSnackBar(SnackBar(
                      content: Text('✅ QR code synced'),
                    ));
                  } catch (e) {
                    scaffold.showSnackBar(SnackBar(
                      content: Text('⚠️ QR code not available'),
                    ));
                  }
                }

                // 3. Sync rules.json
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

                // 4. Check for app update
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
          ),
        ],
      ),
    );
  }
}

class TradeQRScannerPage extends StatefulWidget {
  final String tierName;
  final int coreCount;
  final Character fromCharacter;

  const TradeQRScannerPage({
    super.key,
    required this.tierName,
    required this.coreCount,
    required this.fromCharacter,
  });

  @override
  _TradeQRScannerPageState createState() => _TradeQRScannerPageState();
}

class _TradeQRScannerPageState extends State<TradeQRScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool isScanning = true;
  String? scannedData;

  @override
  void initState() {
    super.initState();
    print('TradeQRScannerPage initialized');
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    print('QR View created successfully');
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      print('QR Scanner detected data: ${scanData.code}');
      if (scanData.code != null && scanData.code!.isNotEmpty) {
        print('Processing QR code: ${scanData.code}');
        _handleQRCodeScan(scanData.code!);
      }
    });
  }

  void _handleQRCodeScan(String code) {
    if (!isScanning) return; // Prevent multiple scans
    
    // Prevent processing the same QR code multiple times
    if (scannedData == code) return;
    
    setState(() {
      isScanning = false;
      scannedData = code;
    });
    
    // Stop the camera immediately after scan (skip on web due to UnimplementedError)
    try {
      controller?.pauseCamera();
    } catch (e) {
      print('Camera pause not supported on this platform: $e');
    }
    
    _processScannedData(code);
  }

  void _processScannedData(String data) {
    try {
      // Check if the data looks like JSON
      if (!data.trim().startsWith('{') || !data.trim().endsWith('}')) {
        if (mounted) {
          _showError('This doesn\'t appear to be a valid player QR code. Please scan a player QR code.');
        }
        return;
      }

      // Parse the QR code data
      final Map<String, dynamic> playerData = json.decode(data);
      
      // Validate the QR code format
      if (playerData.containsKey('game') && playerData['game'] == 'Crucible' && playerData.containsKey('playerUid')) {
        // Profile QR code format - return the data
        Navigator.of(context).pop(playerData);
        return;
      }
      
      if (playerData.containsKey('uid') && playerData.containsKey('characters')) {
        // Old format with direct character data - return the data
        Navigator.of(context).pop(playerData);
        return;
      }
      
      if (mounted) {
        _showError('This QR code is not a valid player profile. Please scan a player QR code from the Profile page.');
      }
    } catch (e) {
      print('QR Code parsing error: $e');
      if (mounted) {
        _showError('Invalid QR code format. Please scan a valid player QR code.\n\nError: ${e.toString()}');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Scan Error'),
            ],
          ),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetScanner();
              },
              child: Text('Try Again'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to character sheet
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _resetScanner() {
    print('Resetting QR scanner...');
    setState(() {
      isScanning = true;
      scannedData = null;
    });
    // Restart the camera if needed (skip on web due to UnimplementedError)
    try {
      controller?.resumeCamera();
    } catch (e) {
      print('Camera resume not supported on this platform: $e');
    }
    print('QR scanner reset complete');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trade ${widget.tierName} Core'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: Colors.blue,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 300,
              ),
            ),
          ),
          Container(
            height: 100,
            padding: EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_scanner,
                  size: 24,
                  color: Colors.blue,
                ),
                SizedBox(height: 4),
                Text(
                  'Scan player QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                if (scannedData != null) ...[
                  SizedBox(height: 2),
                  Text(
                    'Processing...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ] else if (isScanning) ...[
                  SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: _resetScanner,
                    icon: Icon(Icons.refresh, size: 14),
                    label: Text('Reset', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}



