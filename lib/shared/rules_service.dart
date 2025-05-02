import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';

class RulesService {
  static const _rulesKey = 'rules_json';

  /// Downloads and caches the rules JSON from Firebase
  static Future<void> fetchAndCacheRules() async {
    final ref = FirebaseStorage.instance.ref().child('rules.json');
    final data = await ref.getData();

    if (data == null) {
      throw Exception('Failed to fetch rules.json');
    }

    final jsonString = String.fromCharCodes(data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rulesKey, jsonString);
  }

  /// Loads the cached rules JSON from local storage
  static Future<String?> loadCachedRules() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rulesKey);
  }
}