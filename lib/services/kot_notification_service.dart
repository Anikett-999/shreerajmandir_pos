import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class KotNotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isListening = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  void startListening() {
    if (_isListening) return;
    _isListening = true;

    _subscription = _firestore.collection('kots').where('status', isEqualTo: 'Done').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null && data['status'] == 'Done') {
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

  Future<void> stopListening() async {
    if (!_isListening) return;
    await _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }
}
