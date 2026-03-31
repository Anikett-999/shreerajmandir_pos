import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';

import '../utils/order_status_utils.dart';

class KotNotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isListening = false;

  void startListening() {
    if (_isListening) return;
    _isListening = true;

    _firestore.collection('kots').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null && OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString()) == 'served') {
            Fluttertoast.showToast(
              msg: "KOT #${data['kotNumber'] ?? ''} is Ready to Serve!",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.TOP,
              backgroundColor: Colors.green,
              textColor: Colors.white,
              fontSize: 18.0,
            );
          }
        }
      }
    });
  }
}
