import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NPCCacheService {
  static const String _cacheKey = 'npcs_cache';
  static const String _lastUpdatedKey = 'npcs_last_updated';

  /// Get cached NPCs data
  static Future<Map<String, dynamic>?> getCachedNPCs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        return json.decode(cachedData);
      }
    } catch (e) {
      print('Error getting cached NPCs: $e');
    }
    return null;
  }

  /// Cache NPCs data
  static Future<void> cacheNPCs(Map<String, dynamic> npcsData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(npcsData));
    } catch (e) {
      print('Error caching NPCs: $e');
    }
  }

  /// Get last updated timestamp from cache
  static Future<String?> getCachedLastUpdated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUpdatedKey);
    } catch (e) {
      print('Error getting cached last updated: $e');
      return null;
    }
  }

  /// Cache last updated timestamp
  static Future<void> cacheLastUpdated(String timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastUpdatedKey, timestamp);
    } catch (e) {
      print('Error caching last updated: $e');
    }
  }

  /// Check if NPCs need to be refreshed
  static Future<bool> needsRefresh() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;

      final idToken = await user.getIdToken();
      
      // Get server's last updated timestamp
      final response = await http.get(
        Uri.parse(AppConfig.getNPCsLastUpdatedUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final serverLastUpdated = responseData['lastUpdated'];
        
        if (serverLastUpdated == null) {
          // No NPCs exist yet, cache is valid
          return false;
        }

        // Get cached timestamp
        final cachedLastUpdated = await getCachedLastUpdated();
        
        if (cachedLastUpdated == null) {
          // No cached data, need to refresh
          return true;
        }

        // Compare timestamps
        return serverLastUpdated.toString() != cachedLastUpdated;
      }
    } catch (e) {
      print('Error checking NPCs refresh: $e');
    }
    
    // If we can't check, assume we need to refresh
    return true;
  }

  /// Load NPCs from server and cache them
  static Future<Map<String, dynamic>?> loadAndCacheNPCs() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final idToken = await user.getIdToken();
      
      // Load both types
      final cultivatorsResponse = await http.get(
        Uri.parse('${AppConfig.listNPCsUrl}?type=Cultivator'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      final monstersResponse = await http.get(
        Uri.parse('${AppConfig.listNPCsUrl}?type=Monster'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (cultivatorsResponse.statusCode == 200 && monstersResponse.statusCode == 200) {
        final cultivatorsData = json.decode(cultivatorsResponse.body);
        final monstersData = json.decode(monstersResponse.body);
        
        final npcsData = {
          'cultivators': cultivatorsData['npcs'] ?? [],
          'monsters': monstersData['npcs'] ?? [],
          'lastUpdated': DateTime.now().toIso8601String(),
        };

        // Cache the data
        await cacheNPCs(npcsData);
        await cacheLastUpdated(npcsData['lastUpdated']);

        return npcsData;
      }
    } catch (e) {
      print('Error loading and caching NPCs: $e');
    }
    
    return null;
  }

  /// Clear NPCs cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_lastUpdatedKey);
    } catch (e) {
      print('Error clearing NPCs cache: $e');
    }
  }

  /// Get NPCs (from cache or server)
  static Future<Map<String, dynamic>?> getNPCs() async {
    // First check if we need to refresh
    final needsRefresh = await NPCCacheService.needsRefresh();
    
    if (!needsRefresh) {
      // Try to get from cache
      final cachedData = await getCachedNPCs();
      if (cachedData != null) {
        return cachedData;
      }
    }

    // Load from server and cache
    return await loadAndCacheNPCs();
  }
}
