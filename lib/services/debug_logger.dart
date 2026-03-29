import 'dart:convert';

import 'package:flutter/foundation.dart';

class DebugLogger {
  static void logEvent({
    required String event,
    Map<String, dynamic>? data,
  }) {
    final payload = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'event': event,
      'userRole': data?['userRole'] ?? 'unknown',
      'userId': data?['userId'] ?? 'unknown',
      'tableId': data?['tableId'] ?? 'unknown',
      'orderId': data?['orderId'] ?? 'unknown',
      'lockedBy': data?['lockedBy'],
      'previousState': data?['previousState'],
      'newState': data?['newState'],
      if (data != null) ...data,
    };

    debugPrint('[DEBUG_LOG] ${jsonEncode(payload)}');
  }
}
