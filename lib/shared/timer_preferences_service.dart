import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart';
import 'dart:js_interop';

/// Service for managing timer sound and vibration preferences
class TimerPreferencesService {
  static const String _soundEnabledKey = 'timer_sound_enabled';
  static const String _vibrationEnabledKey = 'timer_vibration_enabled';
  
  static bool _hasVibrator = false;
  static bool _vibratorChecked = false;

  /// Check if device has vibration support
  static Future<void> _checkVibrator() async {
    if (_vibratorChecked) return;
    try {
      final hasVibration = await Vibration.hasVibrator();
      _hasVibrator = hasVibration == true;
      _vibratorChecked = true;
    } catch (e) {
      debugPrint('Error checking vibrator: $e');
      _hasVibrator = false;
      _vibratorChecked = true;
    }
  }

  /// Get sound enabled preference
  static Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true; // Default: enabled
  }

  /// Set sound enabled preference
  static Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
  }

  /// Get vibration enabled preference
  static Future<bool> isVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vibrationEnabledKey) ?? true; // Default: enabled
  }

  /// Set vibration enabled preference
  static Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationEnabledKey, enabled);
  }

  /// Play beep sound if enabled (generated programmatically using Web Audio API via JavaScript)
  static Future<void> playBeep({int frequency = 800, int durationMs = 200}) async {
    try {
      final soundEnabled = await isSoundEnabled();
      if (!soundEnabled) return;

      if (kIsWeb) {
        try {
          // Check if the JavaScript function exists before calling it
          if (_isPlayBeepAvailable()) {
            _playBeepJS(frequency, durationMs);
          }
        } catch (e) {
          debugPrint('Error playing beep: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in playBeep: $e');
    }
  }

  /// Trigger vibration if enabled and supported
  static Future<void> vibrate({int duration = 200}) async {
    try {
      await _checkVibrator();
      
      final vibrationEnabled = await isVibrationEnabled();
      if (!vibrationEnabled || !_hasVibrator) return;

      // Note: Vibration may not work on desktop browsers (Chrome/Firefox/Safari on Windows/Mac/Linux)
      // Only works on mobile browsers
      if (kIsWeb && kDebugMode) {
        debugPrint('⚠️ Vibration requested on web - may only work on mobile browsers');
      }
      
      await Vibration.vibrate(duration: duration);
    } catch (e) {
      debugPrint('Error triggering vibration: $e');
    }
  }

  /// Play beep and vibrate (convenience method)
  static Future<void> alertUser() async {
    await Future.wait([
      playBeep(),
      vibrate(),
    ]);
  }

  /// Check if vibration is supported on this device
  static Future<bool> hasVibratorSupport() async {
    await _checkVibrator();
    return _hasVibrator;
  }
}

/// Call JavaScript function to play beep sound
@JS('playBeepSound')
external void _playBeepJS(int frequency, int durationMs);

/// Check if the JavaScript function is available
@JS('playBeepSound')
external JSAny? get _playBeepJSGetter;

bool _isPlayBeepAvailable() {
  try {
    return _playBeepJSGetter != null;
  } catch (e) {
    return false;
  }
}
