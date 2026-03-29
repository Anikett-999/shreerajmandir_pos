import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminMenuProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore;

  AdminMenuProvider({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  String? _restaurantId;
  bool _isInitializing = false;
  bool _isBusy = false;
  String? _errorMessage;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _categories = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _categoriesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _itemsSub;

  String? get restaurantId => _restaurantId;
  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get categories => _categories;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get items => _items;

  Future<void> initialize(String? restaurantId) async {
    if (_restaurantId == restaurantId && (_categoriesSub != null || _itemsSub != null)) {
      return;
    }

    await _categoriesSub?.cancel();
    await _itemsSub?.cancel();

    _restaurantId = restaurantId;
    _categories = [];
    _items = [];
    _errorMessage = null;
    _isInitializing = true;
    notifyListeners();

    if (_restaurantId == null) {
      _isInitializing = false;
      notifyListeners();
      return;
    }

    _categoriesSub = _firestore
        .collection('menu_categories')
        .where('restaurantId', isEqualTo: _restaurantId)
        .snapshots()
        .listen((snapshot) {
      _categories = snapshot.docs.toList()
        ..sort((a, b) {
          final aOrder = (a.data()['order'] ?? 0) as int;
          final bOrder = (b.data()['order'] ?? 0) as int;
          return aOrder.compareTo(bOrder);
        });
      _errorMessage = null;
      _isInitializing = false;
      notifyListeners();
    }, onError: (error) {
      _errorMessage = error.toString();
      _isInitializing = false;
      notifyListeners();
    });

    _itemsSub = _firestore
        .collection('menu_items')
        .where('restaurantId', isEqualTo: _restaurantId)
        .snapshots()
        .listen((snapshot) {
      _items = snapshot.docs.toList();
      _errorMessage = null;
      _isInitializing = false;
      notifyListeners();
    }, onError: (error) {
      _errorMessage = error.toString();
      _isInitializing = false;
      notifyListeners();
    });
  }

  Future<void> addOrUpdateCategory({
    String? id,
    required String name,
    required int order,
    required bool isVisible,
    String? imageUrl,
  }) async {
    await _runBusy(() async {
      final data = {
        'name': name,
        'order': order,
        'isVisible': isVisible,
        'restaurantId': _restaurantId,
        'imageUrl': imageUrl,
      };

      if (id == null) {
        await _firestore.collection('menu_categories').add(data);
      } else {
        await _firestore.collection('menu_categories').doc(id).update(data);
      }
    });
  }

  Future<void> deleteCategory(String id) async {
    await _runBusy(() async {
      await _firestore.collection('menu_categories').doc(id).delete();
    });
  }

  Future<void> addOrUpdateItem({
    String? id,
    required String name,
    required double price,
    required String description,
    required String? category,
    required bool isAvailable,
    String? imageUrl,
  }) async {
    await _runBusy(() async {
      final data = {
        'name': name,
        'price': price,
        'description': description,
        'category': category,
        'imageUrl': imageUrl,
        'isAvailable': isAvailable,
        'restaurantId': _restaurantId,
      };

      if (id == null) {
        await _firestore.collection('menu_items').add(data);
      } else {
        await _firestore.collection('menu_items').doc(id).update(data);
      }
    });
  }

  Future<void> deleteItem(String id) async {
    await _runBusy(() async {
      await _firestore.collection('menu_items').doc(id).delete();
    });
  }

  Future<void> toggleItemAvailability(String id, bool isAvailable) async {
    try {
      _errorMessage = null;
      await _firestore.collection('menu_items').doc(id).set(
        {
          'isAvailable': isAvailable,
          'restaurantId': _restaurantId,
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString();
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _categoriesSub?.cancel();
    _itemsSub?.cancel();
    super.dispose();
  }
}
