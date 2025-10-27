import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../shared/rules_service.dart';
import '../shared/admin_cache_service.dart';
import '../shared/npc_cache_service.dart';
import '../shared/character_cache_service.dart';
import '../shared/impersonation_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final Stream<User?> _authStateChanges;
  StreamSubscription<User?>? _authSubscription;
  bool _userExplicitlyLoggedOut = false;

  @override
  void initState() {
    super.initState();
    _authStateChanges = _auth.authStateChanges();
    
    // Check if user was explicitly logged out and set up auth listener
    _initializeAuthState();

    _authSubscription = _authStateChanges.listen((user) {
      // Add a small delay to ensure logout flag is properly checked
      Future.delayed(Duration(milliseconds: 50), () {
        _handleAuthStateChange(user);
      });
    });
  }

  Future<void> _initializeAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userExplicitlyLoggedOut = prefs.getBool('user_explicitly_logged_out') ?? false;
      print('🔍 Logout state checked: $_userExplicitlyLoggedOut');
      print('🔍 All SharedPreferences keys: ${prefs.getKeys()}');
      
      // If user was explicitly logged out, force sign out immediately
      if (_userExplicitlyLoggedOut && _auth.currentUser != null) {
        print('🚫 User was explicitly logged out, forcing immediate sign out');
        await _auth.signOut();
        // Clear the logout flag after forcing sign out
        await prefs.remove('user_explicitly_logged_out');
        _userExplicitlyLoggedOut = false;
      }
      
      // Check current auth state after logout flag is loaded
      final currentUser = _auth.currentUser;
      _handleAuthStateChange(currentUser);
    } catch (e) {
      print('Error checking logout state: $e');
    }
  }

  void _handleAuthStateChange(User? user) {
    // Double-check the logout flag from SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      final logoutFlag = prefs.getBool('user_explicitly_logged_out') ?? false;
      print('🔍 Auth state change - user: ${user?.email}, logout flag: $logoutFlag');
      
      if (mounted && user != null && !logoutFlag) {
        print('🚀 User authenticated and not explicitly logged out, navigating to HomePage');
        // User is signed in and hasn't explicitly logged out – navigate to HomePage
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomePage()),
        );
        // Warm the rules cache after navigation (user is signed in)
        // Errors are ignored so login UX is not blocked
        RulesService.fetchAndCacheRules().catchError((_) => null);
      } else if (mounted && user != null && logoutFlag) {
        print('🚫 User authenticated but was explicitly logged out, staying on login page');
        // Force sign out if user is authenticated but was explicitly logged out
        _forceSignOut();
      }
    });
  }

  Future<void> _forceSignOut() async {
    try {
      print('🔄 Forcing sign out due to explicit logout flag');
      await _auth.signOut();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Error forcing sign out: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> signInWithGoogle() async {
    try {
      print('🔑 Starting Google sign-in...');
      
      // Reset the logout flag when user explicitly signs in
      _userExplicitlyLoggedOut = false;
      
      // Clear the logout flag from persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_explicitly_logged_out');
      print('🔓 Logout flag cleared for new sign-in');
      
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      if (kIsWeb) {
        // Force a fresh authentication by clearing any existing session
        try {
          await _auth.signOut();
          await Future.delayed(Duration(milliseconds: 100));
        } catch (e) {
          print('⚠️ Error clearing auth before sign-in: $e');
        }
        
        // Force fresh authentication by adding a custom parameter
        provider.setCustomParameters({'prompt': 'select_account'});
        await _auth.signInWithPopup(provider);
      } else {
        await _auth.signInWithProvider(provider);
      }
      
      print('✅ Google sign-in completed');
    } catch (e, stack) {
      print('Sign-In Error: $e');
      print('Stacktrace: $stack');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sign-In Failed: ${e.toString()}'),
      ));
    }
  }

  Future<void> signOut() async {
    try {
      print('🚪 Starting logout process...');
      
      // Set flag to prevent auto-login after logout
      _userExplicitlyLoggedOut = true;
      
      // Persist the logout flag
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_explicitly_logged_out', true);
      print('🔒 Logout flag set and persisted');
      
      // Verify the flag was actually saved
      final savedFlag = prefs.getBool('user_explicitly_logged_out');
      print('🔍 Verification - saved flag value: $savedFlag');
      print('🔍 All SharedPreferences keys after logout: ${prefs.getKeys()}');
      
      // Stop any active impersonation first
      ImpersonationService.stop();
      
      // Clear all user-specific caches
      await Future.wait([
        AdminCacheService.clearCache(),
        NPCCacheService.clearCache(),
        CharacterCacheService.clearCache(),
        RulesService.clearCache(),
      ]);
      
      // Clear session flags
      await prefs.remove('hasCompletedNewCharacterDialog');
      print('🧹 Cleared new character dialog session flag');
      
      // Sign out from Firebase Auth
      await _auth.signOut();
      print('🔐 Firebase Auth signOut completed');
      
      // Force a small delay to ensure auth state is properly cleared
      await Future.delayed(Duration(milliseconds: 100));
      
      // Verify user is actually signed out
      if (_auth.currentUser != null) {
        print('⚠️ User still authenticated after signOut, forcing signOut again');
        await _auth.signOut();
      }
      
      print('✅ User successfully signed out');
      
      // Force UI refresh to show login button
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Error during signOut: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('Login'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Center(
        child: user == null
            ? ElevatedButton(
                onPressed: signInWithGoogle,
                child: Text('Sign In with Google'),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Signed in as ${user.email}', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: signOut,
                    child: Text('Sign Out'),
                  ),
                ],
              ),
      ),
    );
  }
}
