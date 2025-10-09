# Timer Sound & Vibration Implementation Summary

## What Was Implemented

### 1. **New Package Added**
- `vibration: ^2.0.0` - For vibration support (works on mobile browsers)

### 2. **Timer Preferences Service** (`lib/shared/timer_preferences_service.dart`)
A new service that manages:
- Sound enable/disable preferences (saved in SharedPreferences)
- Vibration enable/disable preferences (saved in SharedPreferences)
- `playBeep()` - **Generates beep sound programmatically using Web Audio API** (no audio files needed!)
- `vibrate()` - Triggers vibration when enabled (mobile browsers only)
- `alertUser()` - Convenience method that does both

**Sound Generation:**
- Uses the browser's Web Audio API via JavaScript (`web/audio_beep.js`)
- Default: 800 Hz sine wave for 200ms at 30% volume
- No audio files required - works out of the box!
- Customizable frequency and duration: `playBeep(frequency: 1000, durationMs: 300)`
- Pure JavaScript implementation - no complex Dart/JS interop issues

### 3. **New "Regenerations" Timer** (`lib/pages/death_timer_page.dart`)
Added a new timer type with:
- **1-Minute Repeating Timer**: Counts down 1 minute, then resets
- **5-Minute Total Timer**: Counts down full 5 minutes
- Both timers run simultaneously
- Beep/vibration + visual flash at the end of every minute
- Both stop at the end of 5 minutes

### 4. **Sound & Vibration Integration**
All timers now have sound and vibration alerts:
- **Death Timer**: Alert when transitioning from Stage 1 to Stage 2, and when character dies
- **Exhaustion Timer**: Alert when completed
- **Imprison Timer**: Alert when completed  
- **Regenerations Timer**: Alert every minute + at completion

### 5. **Settings UI in Profile Page** (`lib/pages/new_sheet_page.dart`)
Added a "Timer Settings" section with two toggles:
- **Sound Toggle**: Enable/disable beep sounds
- **Vibration Toggle**: Enable/disable vibration (note: only works on mobile browsers)

Settings are persistent across sessions and apply to all timers.

## Usage

### For Users:
1. Go to the character sheet page
2. Scroll down to the "Timer Settings" section (below weapon stats)
3. Toggle sound and/or vibration on/off
4. Navigate to Timers page (Death Timer page)
5. Switch to the "Regenerations" tab to use the new timer

### For Developers:
To use the preferences service elsewhere:
```dart
import '../shared/timer_preferences_service.dart';

// Play beep and vibrate
await TimerPreferencesService.alertUser();

// Or individually
await TimerPreferencesService.playBeep(); // Default 800 Hz, 200ms
await TimerPreferencesService.playBeep(frequency: 1000, durationMs: 300); // Custom
await TimerPreferencesService.vibrate();

// Check settings
bool soundOn = await TimerPreferencesService.isSoundEnabled();
bool vibrationOn = await TimerPreferencesService.isVibrationEnabled();
```

## Important Notes

### No Audio Files Required! 🎉
The implementation uses the **Web Audio API** to generate beep tones programmatically via JavaScript. This means:
- ✅ No audio files needed
- ✅ Works immediately out of the box
- ✅ Customizable pitch (frequency) and duration
- ✅ Consistent across all browsers
- ✅ Very small code footprint
- ✅ Simple JavaScript implementation (see `web/audio_beep.js`)

### Vibration Limitations
- **Desktop Browsers (Chrome/Firefox/Safari on Windows/Mac/Linux)**: Vibration DOES NOT work
- **Mobile Browsers (Chrome on Android, Safari on iOS)**: Vibration WORKS
- Vibration also requires a user gesture (e.g., button click) due to browser security

### Browser Permissions
Some browsers may require user interaction before playing audio. The first beep might fail until the user interacts with the page (e.g., clicks a button).

## Testing

To test the implementation:
1. Run: `flutter run -d chrome --web-port=8080`
2. Navigate to character sheet and test the Timer Settings toggles
3. Go to Timers page and test each timer
4. Verify sound plays when timers complete
5. Verify visual flash appears
6. Test on mobile browser to verify vibration

## Files Modified/Created

- `pubspec.yaml` - Added vibration package
- `lib/shared/timer_preferences_service.dart` - NEW: Preferences management with Web Audio API
- `lib/pages/death_timer_page.dart` - Added Regenerations timer + sound/vibration
- `lib/pages/new_sheet_page.dart` - Added Timer Settings UI
- `web/audio_beep.js` - NEW: JavaScript Web Audio API implementation
- `web/index.html` - Added script tag for audio_beep.js

## Technical Details: Web Audio API

The beep sound is generated using the Web Audio API via a JavaScript helper file:

**JavaScript (`web/audio_beep.js`):**
```javascript
window.playBeepSound = function(frequency, durationMs) {
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  const audioContext = new AudioContext();
  const oscillator = audioContext.createOscillator();
  const gainNode = audioContext.createGain();
  
  oscillator.frequency.value = frequency || 800;
  oscillator.type = 'sine';
  gainNode.gain.value = 0.3;
  
  oscillator.connect(gainNode);
  gainNode.connect(audioContext.destination);
  oscillator.start();
  
  setTimeout(() => oscillator.stop(), durationMs || 200);
};
```

**Dart (`lib/shared/timer_preferences_service.dart`):**
```dart
@JS('playBeepSound')
external void _playBeepJS(int frequency, int durationMs);

static Future<void> playBeep({int frequency = 800, int durationMs = 200}) async {
  final soundEnabled = await isSoundEnabled();
  if (soundEnabled && kIsWeb) {
    _playBeepJS(frequency, durationMs);
  }
}
```

## Future Enhancements

Potential improvements:
1. ✅ ~~Use programmatic sound generation~~ (Done!)
2. ✅ ~~No audio files required~~ (Done!)
3. Add UI to customize beep frequency (pitch)
4. Add UI to customize beep duration
5. Add volume control slider
6. Add different beep patterns (multiple beeps, ascending tones, etc.)
7. Add visual animations (more elaborate flashing)
8. Add timer notifications when app is in background
9. Add haptic feedback patterns (different vibration patterns)
10. Add option to use different waveforms (sine, square, triangle, sawtooth)
