import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { waiter, admin, cashier, none }

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

  String? _savedPin;
  bool get hasSavedPin => _savedPin != null;

  Timer? _sessionTimer;

  AuthService() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    _savedPin = prefs.getString('waiter_pin');
    
    _auth.authStateChanges().listen((user) async {
      try {
        _isLoading = false;
        if (user == null) {
          _isUnlocked = false;
          _restaurantId = null;
          _stopSessionTimer();
        } else {
          if (_savedPin == null) {
            final doc = await _firestore.collection('users').doc(user.uid).get();
            String roleStr = doc.data()?['role'] ?? 'waiter';
            _role = _getRoleFromString(roleStr);
            _restaurantId = doc.data()?['restaurantId'];

            if (_restaurantId != null) {
              final resDoc = await _firestore.collection('restaurants').doc(_restaurantId).get();
              _restaurantName = resDoc.data()?['name'];
            }

            _isUnlocked = true;
            _startSessionTimer();
          } else {
            _isUnlocked = false;
          }
        }
      } catch (_) {
        _isUnlocked = false;
        _stopSessionTimer();
      }
      notifyListeners();
    });
  }

  UserRole _getRoleFromString(String roleStr) {
    switch (roleStr) {
      case 'admin': return UserRole.admin;
      case 'cashier': return UserRole.cashier;
      case 'waiter': return UserRole.waiter;
      default: return UserRole.waiter;
    }
  }

  Future<String?> registerWithEmail({
    required String email, 
    required String password, 
    required String name, 
    required String restaurantName,
    String role = 'admin',
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      
      // Create Restaurant
      final restaurantDoc = await _firestore.collection('restaurants').add({
        'name': restaurantName,
        'createdAt': FieldValue.serverTimestamp(),
        'adminUid': credential.user!.uid,
      });

      await _firestore.collection('users').doc(credential.user!.uid).set({
        'email': email,
        'name': name,
        'role': role,
        'restaurantId': restaurantDoc.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      _role = _getRoleFromString(role);
      _restaurantId = restaurantDoc.id;
      _restaurantName = restaurantName;
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return '[${e.code}] ${e.message ?? 'Authentication error'}';
    } on FirebaseException catch (e) {
      return '[${e.code}] ${e.message ?? 'Firebase operation failed'}';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> loginWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      // Fetch role and restaurantId
      final doc = await _firestore.collection('users').doc(credential.user!.uid).get();
      if (!doc.exists) {
        await _auth.signOut();
        return 'Access Denied: User profile not found.';
      }
      
      String roleStr = doc.data()?['role'] ?? 'waiter';
      _role = _getRoleFromString(roleStr);
      _restaurantId = doc.data()?['restaurantId'];
      
      if (_restaurantId != null) {
        final resDoc = await _firestore.collection('restaurants').doc(_restaurantId).get();
        _restaurantName = resDoc.data()?['name'];
      }
      
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return '[${e.code}] ${e.message ?? 'Authentication error'}';
    } on FirebaseException catch (e) {
      return '[${e.code}] ${e.message ?? 'Firebase operation failed'}';
    } catch (e) {
      return e.toString();
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
    await prefs.setString('waiter_pin', pin);
    _savedPin = pin;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('waiter_pin');
    _savedPin = null;
    _isUnlocked = false;
    _role = UserRole.none;
    _restaurantId = null;
    _restaurantName = null;
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
        'pin': pin,
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
    });
  }

  Future<void> sendResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  void userActivityDetected() {
    if (_isUnlocked) {
      _startSessionTimer(); // Reset timer on interaction
    }
  }
}
