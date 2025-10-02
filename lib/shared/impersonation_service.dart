import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ImpersonationService {
  static final ValueNotifier<bool> _isImpersonating = ValueNotifier<bool>(false);
  static String? _targetUid;
  static String? _targetEmail;
  static String? _originalUid;
  static String? _originalEmail;
  static VoidCallback? _onImpersonationChange;

  static ValueListenable<bool> get listenable => _isImpersonating;
  static bool get isImpersonating => _isImpersonating.value;
  static String? get targetUid => _targetUid;
  static String? get targetEmail => _targetEmail;

  static void setOnImpersonationChange(VoidCallback? callback) {
    _onImpersonationChange = callback;
  }

  static void start({required String uid, String? email}) {
    // Store original user info
    final currentUser = FirebaseAuth.instance.currentUser;
    _originalUid = currentUser?.uid;
    _originalEmail = currentUser?.email;
    
    _targetUid = uid;
    _targetEmail = email;
    _isImpersonating.value = true;
    print('🎭 ImpersonationService.start called - targetUid: $uid, targetEmail: $email');
    print('🎭 Callback exists: ${_onImpersonationChange != null}');
    _onImpersonationChange?.call();
  }

  static void stop() {
    _targetUid = null;
    _targetEmail = null;
    _originalUid = null;
    _originalEmail = null;
    _isImpersonating.value = false;
    _onImpersonationChange?.call();
  }

  // Get the effective UID (target if impersonating, current user otherwise)
  static String? getEffectiveUid() {
    if (_isImpersonating.value && _targetUid != null) {
      return _targetUid;
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }

  // Get the effective email (target if impersonating, current user otherwise)
  static String? getEffectiveEmail() {
    if (_isImpersonating.value && _targetEmail != null) {
      return _targetEmail;
    }
    return FirebaseAuth.instance.currentUser?.email;
  }
}

