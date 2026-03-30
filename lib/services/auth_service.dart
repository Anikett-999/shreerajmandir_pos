import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { waiter, admin, cashier, kitchen, none }

const String kitchenFallbackRestaurantId = 'rest_001';

class AuthProfileResolution {
  const AuthProfileResolution({
    required this.role,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantCode,
    required this.shouldUnlock,
    this.errorMessage,
  });

  final UserRole role;
  final String? restaurantId;
  final String? restaurantName;
  final String? restaurantCode;
  final bool shouldUnlock;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

UserRole userRoleFromString(String roleStr) {
  switch (roleStr.trim().toLowerCase()) {
    case 'admin':
      return UserRole.admin;
    case 'cashier':
      return UserRole.cashier;
    case 'kitchen':
    case 'chef':
      return UserRole.kitchen;
    case 'waiter':
      return UserRole.waiter;
    default:
      return UserRole.waiter;
  }
}

String? normalizeRestaurantId(dynamic restaurantId) {
  final normalized = restaurantId?.toString().trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

AuthProfileResolution resolveAuthProfileData({
  required bool userExists,
  required Map<String, dynamic>? userData,
  required bool hasSavedPin,
  required bool restaurantExists,
  String? restaurantName,
  String? restaurantCode,
}) {
  if (!userExists) {
    return const AuthProfileResolution(
      role: UserRole.none,
      restaurantId: null,
      restaurantName: null,
      restaurantCode: null,
      shouldUnlock: false,
      errorMessage: 'Access Denied: User profile not found.',
    );
  }

  final data = userData;
  final status = (data?['status'] ?? 'active').toString().trim().toLowerCase();
  if (status == 'deleted') {
    return const AuthProfileResolution(
      role: UserRole.none,
      restaurantId: null,
      restaurantName: null,
      restaurantCode: null,
      shouldUnlock: false,
      errorMessage: 'Your account is deleted. Contact admin.',
    );
  }
  if (status == 'inactive') {
    return const AuthProfileResolution(
      role: UserRole.none,
      restaurantId: null,
      restaurantName: null,
      restaurantCode: null,
      shouldUnlock: false,
      errorMessage: 'Your account is disabled. Contact admin.',
    );
  }

  final role = userRoleFromString((data?['role'] ?? 'waiter').toString());
  final configuredRestaurantId = normalizeRestaurantId(data?['restaurantId']);
  final restaurantId = role == UserRole.kitchen
      ? (configuredRestaurantId ?? kitchenFallbackRestaurantId)
      : configuredRestaurantId;
  if (restaurantId == null) {
    return const AuthProfileResolution(
      role: UserRole.none,
      restaurantId: null,
      restaurantName: null,
      restaurantCode: null,
      shouldUnlock: false,
      errorMessage: 'Your user profile is missing a restaurant assignment. Contact admin.',
    );
  }

  if (role == UserRole.kitchen && !restaurantExists) {
    return AuthProfileResolution(
      role: role,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      restaurantCode: normalizeRestaurantId(restaurantCode) ?? kitchenFallbackRestaurantId,
      shouldUnlock: !hasSavedPin,
    );
  }

  if (!restaurantExists) {
    return AuthProfileResolution(
      role: role,
      restaurantId: restaurantId,
      restaurantName: null,
      restaurantCode: null,
      shouldUnlock: false,
      errorMessage: 'Assigned restaurant profile could not be found. Contact admin.',
    );
  }

  return AuthProfileResolution(
    role: role,
    restaurantId: restaurantId,
    restaurantName: restaurantName,
    restaurantCode: normalizeRestaurantId(restaurantCode),
    shouldUnlock: !hasSavedPin,
  );
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  User? get currentUser => _auth.currentUser;
  
  bool _isUnlocked = false;
  bool get isUnlocked => _isUnlocked;
  
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  UserRole _role = UserRole.none;
  UserRole get role => _role;

  String? _restaurantId;
  String? get restaurantId => _restaurantId;

  String? _restaurantName;
  String? get restaurantName => _restaurantName;

  String? _restaurantCode;
  String? get restaurantCode => _restaurantCode;

  String? _profileIssueMessage;
  String? get profileIssueMessage => _profileIssueMessage;

  String? _savedPin;
  bool get hasSavedPin => _savedPin != null;

  Timer? _sessionTimer;

  AuthService() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    const firstLaunchCompletedKey = 'first_launch_completed';
    final prefs = await SharedPreferences.getInstance();
    _savedPin = prefs.getString('staff_pin');

    final firstLaunchCompleted = prefs.getBool(firstLaunchCompletedKey) ?? false;
    if (!firstLaunchCompleted) {
      if (_auth.currentUser != null) {
        await _auth.signOut();
      }
      await prefs.setBool(firstLaunchCompletedKey, true);
    }
    
    _auth.authStateChanges().listen((user) async {
      try {
        _isLoading = false;
        if (user == null) {
          _clearSessionState();
          _stopSessionTimer();
        } else {
          final result = await _loadUserProfileResolution(
            user,
            hasSavedPin: _savedPin != null,
          );

          if (result.hasError) {
            await _auth.signOut();
            _clearSessionState();
            _profileIssueMessage = result.errorMessage;
            _stopSessionTimer();
            notifyListeners();
            return;
          }

          _applyProfileResolution(result);
        }
      } catch (_) {
        _clearSessionState();
        _stopSessionTimer();
      }
      notifyListeners();
    });
  }

  Future<AuthProfileResolution> _loadUserProfileResolution(
    User user, {
    required bool hasSavedPin,
  }) async {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    final role = userRoleFromString((data?['role'] ?? 'waiter').toString());
    final configuredRestaurantId = normalizeRestaurantId(data?['restaurantId']);
    final restaurantId = role == UserRole.kitchen
        ? (configuredRestaurantId ?? kitchenFallbackRestaurantId)
        : configuredRestaurantId;
    DocumentSnapshot<Map<String, dynamic>>? restaurantDoc;
    if (restaurantId != null) {
      restaurantDoc = await _firestore.collection('restaurants').doc(restaurantId).get();
    }

    return resolveAuthProfileData(
      userExists: doc.exists,
      userData: data,
      hasSavedPin: hasSavedPin,
      restaurantExists: restaurantDoc?.exists ?? false,
      restaurantName: restaurantDoc?.data()?['name']?.toString(),
      restaurantCode: normalizeRestaurantId(
        restaurantDoc?.data()?['restaurantCode'] ?? restaurantDoc?.data()?['code'],
      ),
    );
  }

  void _applyProfileResolution(AuthProfileResolution result) {
    _role = result.role;
    _restaurantId = result.restaurantId;
    _restaurantName = result.restaurantName;
    _restaurantCode = result.restaurantCode;
    _profileIssueMessage = null;
    _isUnlocked = result.shouldUnlock;
    if (_isUnlocked) {
      _startSessionTimer();
    } else {
      _stopSessionTimer();
    }
  }

  void _clearSessionState() {
    _isUnlocked = false;
    _role = UserRole.none;
    _restaurantId = null;
    _restaurantName = null;
    _restaurantCode = null;
  }

  Future<String?> loginWithEmail(String email, String password) async {
    try {
      _profileIssueMessage = null;
      final credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final result = await _loadUserProfileResolution(
        credential.user!,
        hasSavedPin: false,
      );
      if (result.hasError) {
        await _auth.signOut();
        _clearSessionState();
        _profileIssueMessage = result.errorMessage;
        notifyListeners();
        return result.errorMessage;
      }

      _applyProfileResolution(result);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'user-disabled':
          return 'This account has been disabled. Contact manager.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait and try again.';
        case 'network-request-failed':
          return 'No internet connection. Please check your network.';
        default:
          return 'Login failed. Please try again.';
      }
    } on FirebaseException {
      return 'Login failed due to a server issue. Please try again.';
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  bool unlockWithPin(String pin) {
    if (pin == _savedPin && currentUser != null) {
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('staff_pin', pin);
    _savedPin = pin;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('staff_pin');
    _savedPin = null;
    _profileIssueMessage = null;
    _clearSessionState();
    _stopSessionTimer();
    await _auth.signOut();
    notifyListeners();
  }

  Future<void> lockSession() async {
    if (_savedPin != null) {
      _isUnlocked = false;
      _stopSessionTimer();
      notifyListeners();
    } else {
      await logout();
    }
  }

  void _startSessionTimer() {
    _stopSessionTimer();
    _sessionTimer = Timer(const Duration(hours: 12), () {
      logout(); // Auto logout after 12h
    });
  }

  void _stopSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  /// Admin creates a new user without logging out themselves
  Future<String?> adminCreateUser({
    required String email, 
    required String password, 
    required String name, 
    required String role,
    String? phone,
    String? pin,
  }) async {
    if (_restaurantId == null || _restaurantId!.isEmpty) {
      return 'Unable to create staff: admin account has no restaurant context. Please ensure you are logged in to a restaurant admin account.';
    }
    FirebaseApp? secondaryApp;
    try {
      // Initialize a temporary secondary app to create the user
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);
      
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'name': name,
        'email': email,
        'role': role,
        'restaurantId': _restaurantId, // Inherit from admin
        'phone': phone,
        if (pin != null && pin.trim().isNotEmpty) 'pin': pin.trim(),
        'status': 'active', // active or inactive (deactivated)
        'createdAt': FieldValue.serverTimestamp(),
      });

      await secondaryAuth.signOut();
      return null;
    } on FirebaseAuthException catch (e) {
      return '[${e.code}] ${e.message ?? 'Authentication error'}';
    } on FirebaseException catch (e) {
      return '[${e.code}] ${e.message ?? 'Firebase operation failed'}';
    } catch (e) {
      return e.toString();
    } finally {
      await secondaryApp?.delete();
    }
  }

  Future<void> updateStaffStatus(String uid, bool isActive) async {
    await _firestore.collection('users').doc(uid).update({
      'status': isActive ? 'active' : 'inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> adminUpdateStaffUser({
    required String uid,
    required String name,
    required String email,
    required String role,
    required String phone,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'name': name,
      'email': email,
      'role': role,
      'phone': phone,
      'restaurantId': _restaurantId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> adminSoftDeleteStaffUser({
    required String uid,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> sendResetEmail(String email) async {
    final trimmedEmail = email.trim();

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'ResetCheck_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      final probeAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final probePassword = '___invalid_probe_password___';

      bool emailLooksValidAndExisting = false;
      try {
        final credential = await probeAuth.signInWithEmailAndPassword(
          email: trimmedEmail,
          password: probePassword,
        );
        if (credential.user != null) {
          emailLooksValidAndExisting = true;
          await probeAuth.signOut();
        }
      } on FirebaseAuthException catch (probeError) {
        if (probeError.code == 'user-not-found') {
          return 'Email not found. Please check and try again.';
        }

        if (probeError.code == 'wrong-password' ||
            probeError.code == 'invalid-credential') {
          emailLooksValidAndExisting = true;
        } else if (probeError.code == 'invalid-email') {
          return 'Enter a valid email address.';
        } else {
          return '[${probeError.code}] ${probeError.message ?? 'Authentication error'}';
        }
      }

      if (!emailLooksValidAndExisting) {
        return 'Unable to verify this email. Please check and try again.';
      }

      await _auth.sendPasswordResetEmail(email: trimmedEmail);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return 'Email not found. Please check and try again.';
      }
      return '[${e.code}] ${e.message ?? 'Authentication error'}';
    } on FirebaseException catch (e) {
      return '[${e.code}] ${e.message ?? 'Firebase operation failed'}';
    } catch (e) {
      return e.toString();
    } finally {
      await secondaryApp?.delete();
    }
  }

  void userActivityDetected() {
    if (_isUnlocked) {
      _startSessionTimer(); // Reset timer on interaction
    }
  }
}
