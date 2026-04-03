import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';

import '../utils/order_status_utils.dart';

class KotNotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isListening = false;
  final Map<String, String> _lastStatus = {};

  /// Start listening for KOT changes for the provided [restaurantId]. If
  /// [restaurantId] is null or empty, the listener will not start.
  void startListening(String? restaurantId) {
    if (_isListening) return;
    if (restaurantId == null || restaurantId.isEmpty) return;
    _isListening = true;

    _firestore
        .collection('kots')
        .where('restaurantId', isEqualTo: restaurantId)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;
        final id = doc.id;
        final newStatus = OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString());
        final oldStatus = _lastStatus[id];

        if (change.type == DocumentChangeType.added) {
          _lastStatus[id] = newStatus;
          continue;
        }

        if (change.type == DocumentChangeType.modified) {
          // if status changed, show a toast describing the transition
          if (oldStatus != null && oldStatus != newStatus) {
            Fluttertoast.showToast(
              msg: "KOT #${data['kotNumber'] ?? ''}: ${oldStatus.toUpperCase()} → ${newStatus.toUpperCase()}",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.TOP,
              backgroundColor: Colors.blueGrey,
              textColor: Colors.white,
              fontSize: 16.0,
            );
          } else if (oldStatus == null) {
            // first time seen
            Fluttertoast.showToast(
              msg: "KOT #${data['kotNumber'] ?? ''}: ${newStatus.toUpperCase()}",
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.TOP,
              backgroundColor: Colors.blueGrey,
              textColor: Colors.white,
              fontSize: 14.0,
            );
          }
          _lastStatus[id] = newStatus;
        }

        if (change.type == DocumentChangeType.removed) {
          _lastStatus.remove(id);
        }
      }
    });
  }
}
