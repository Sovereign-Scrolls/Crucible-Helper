import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class AdminCacheService {
  static const String _adminStatusKey = 'is_super_admin';
  static const String _adminStatusUserKey = 'admin_status_user_uid';
  static const String _adminStatusTimestampKey = 'admin_status_timestamp';
  
  // Cache validity duration (e.g., 5 minutes)
  static const Duration _cacheValidityDuration = Duration(minutes: 5);

  /// Get cached admin status immediately, then verify in background
  /// Returns a Future that completes with the verified status
  static Future<bool> getAdminStatus({
    required Function(bool) onStatusUpdate,
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      onStatusUpdate(false);
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    
    // Check if we have cached data for this user
    final cachedUserUid = prefs.getString(_adminStatusUserKey);
    final cachedStatus = prefs.getBool(_adminStatusKey) ?? false;
    final cachedTimestamp = prefs.getInt(_adminStatusTimestampKey) ?? 0;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final cacheAge = Duration(milliseconds: now - cachedTimestamp);
    
    bool shouldUseCache = !forceRefresh && 
                         cachedUserUid == user.uid && 
                         cacheAge < _cacheValidityDuration;
    
    // If we have valid cached data, return it immediately
    if (shouldUseCache) {
      print('🚀 Using cached admin status: $cachedStatus (age: ${cacheAge.inMinutes}m)');
      onStatusUpdate(cachedStatus);
      
      // Still verify in background for next time
      _verifyAdminStatusInBackground(user, onStatusUpdate);
      
      return cachedStatus;
    }
    
    // No valid cache, need to fetch fresh data
    print('🔄 Fetching fresh admin status (cache age: ${cacheAge.inMinutes}m, force: $forceRefresh)');
    return await _fetchAndCacheAdminStatus(user, onStatusUpdate);
  }

  /// Verify admin status in background without blocking UI
  static void _verifyAdminStatusInBackground(User user, Function(bool) onStatusUpdate) {
    _fetchAndCacheAdminStatus(user, onStatusUpdate).catchError((error) {
      print('❌ Background admin verification failed: $error');
      // Don't update UI on background verification failure
      return false;
    });
  }

  /// Fetch admin status from server and cache the result
  static Future<bool> _fetchAndCacheAdminStatus(User user, Function(bool) onStatusUpdate) async {
    try {
      final idToken = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse(AppConfig.checkSuperAdminUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'uid': user.uid}),
      );

      bool isAdmin = false;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        isAdmin = data['isSuperAdmin'] ?? false;
        
        print('✅ Admin status verified: $isAdmin');
        
        // Cache the result
        await _cacheAdminStatus(user.uid, isAdmin);
      } else {
        print('❌ Admin check failed with status: ${response.statusCode}');
      }

      // Update UI
      onStatusUpdate(isAdmin);
      return isAdmin;
      
    } catch (error) {
      print('❌ Error checking admin status: $error');
      onStatusUpdate(false);
      return false;
    }
  }

  /// Cache admin status for the given user
  static Future<void> _cacheAdminStatus(String userUid, bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    await Future.wait([
      prefs.setString(_adminStatusUserKey, userUid),
      prefs.setBool(_adminStatusKey, isAdmin),
      prefs.setInt(_adminStatusTimestampKey, timestamp),
    ]);
    
    print('💾 Cached admin status: $isAdmin for user $userUid');
  }

  /// Clear cached admin status (e.g., on logout)
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_adminStatusKey),
      prefs.remove(_adminStatusUserKey),
      prefs.remove(_adminStatusTimestampKey),
    ]);
    print('🗑️ Admin status cache cleared');
  }

  /// Force refresh admin status (ignores cache)
  static Future<bool> forceRefresh({required Function(bool) onStatusUpdate}) async {
    return await getAdminStatus(onStatusUpdate: onStatusUpdate, forceRefresh: true);
  }
}
