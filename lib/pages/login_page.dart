import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import '../main.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: '999937639575-nmo32r5cua8g8iuhc33tnia1iickqsit.apps.googleusercontent.com',
        scopes: ['email'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return; // User canceled
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      // 🚀 Navigate to home or character screen after login:
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    } catch (e, stack) {
      print('Sign-In Error: $e');
      print('Stacktrace: $stack');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sign-In Failed: ${e.toString()}'),
      ));
    }
  }


  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
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
