import 'package:firebase_storage/firebase_storage.dart';

/// Centralized service for caching QR code download URLs to prevent multiple downloads
class QRCodeCacheService {
  static final Map<String, String?> _qrCodeCache = {};
  static final Map<String, bool> _qrCodeLoading = {};

  /// Get cached QR code URL for an email, or load it if not cached
  static Future<String?> getQRCodeUrl(String email) async {
    // Return cached result if available
    if (_qrCodeCache.containsKey(email)) {
      print('✅ QR code retrieved from cache for: $email');
      return _qrCodeCache[email];
    }

    // Prevent multiple simultaneous loads for the same email
    if (_qrCodeLoading[email] == true) {
      print('⏳ QR code already loading for: $email, waiting...');
      // Wait for the loading to complete
      while (_qrCodeLoading[email] == true) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      // Return the cached result after loading completes
      return _qrCodeCache[email];
    }

    // Load the QR code
    _qrCodeLoading[email] = true;
    try {
      print('🔍 Loading QR code for: $email');
      final qrRef = FirebaseStorage.instance.ref().child('users/$email/qr.png');
      
      // Check if the file exists
      try {
        final metadata = await qrRef.getMetadata();
        print('✅ QR code file exists: ${metadata.name}');
        
        // Get the download URL
        final downloadUrl = await qrRef.getDownloadURL();
        print('✅ QR code download URL loaded: ${downloadUrl.substring(0, 50)}...');
        
        // Cache the result
        _qrCodeCache[email] = downloadUrl;
        return downloadUrl;
      } catch (e) {
        print('❌ QR code file does not exist for: $email');
        _qrCodeCache[email] = null;
        return null;
      }
    } catch (e) {
      print('❌ Error loading QR code for $email: $e');
      _qrCodeCache[email] = null;
      return null;
    } finally {
      _qrCodeLoading[email] = false;
    }
  }

  /// Clear the cache for a specific email (useful when QR code is regenerated)
  static void clearCache(String email) {
    _qrCodeCache.remove(email);
    _qrCodeLoading.remove(email);
    print('🗑️ QR code cache cleared for: $email');
  }

  /// Clear all cached QR codes
  static void clearAllCache() {
    _qrCodeCache.clear();
    _qrCodeLoading.clear();
    print('🗑️ All QR code cache cleared');
  }

  /// Check if QR code is cached for an email
  static bool isCached(String email) {
    return _qrCodeCache.containsKey(email);
  }
}
