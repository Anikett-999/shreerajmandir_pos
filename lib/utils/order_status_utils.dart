import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../utils/table_state_sync.dart';

class OrderStatusUtils {
  static const _statusMap = {
    'pending': 'placed',
    'active': 'placed',
    'open': 'placed',
    'placed': 'placed',
    'prepared': 'prepared',
    'preparing': 'preparing',
    'ready': 'served',
    'done': 'served',
    'served': 'served',
    'bill_requested': 'served',
    'bill-requested': 'served',
    'billed': 'closed',
    'cancelled': 'cancelled',
    'cancel': 'cancelled',
    'closed': 'closed',
  };

  static String normalizeStatus(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    final mapped = _statusMap[normalized];

    DebugLogger.logEvent(
      event: 'status_normalized',
      data: {
        'rawStatus': rawStatus,
        'normalized': mapped ?? 'placed',
      },
    );

    return mapped ?? 'placed';
  }

  static bool isValidTransition(String fromStatus, String toStatus, String role) {
    final from = normalizeStatus(fromStatus);
    final to = normalizeStatus(toStatus);

    if (from == to) return true;

    final allowed = <String, List<String>>{
      'placed': ['preparing', 'prepared', 'served', 'cancelled', 'closed'],
      'preparing': ['prepared', 'served', 'cancelled', 'closed'],
      'prepared': ['served', 'cancelled', 'closed'],
      'served': ['closed'],
      'closed': [],
      'cancelled': [],
    };

    final allowedTargets = allowed[from] ?? [];
    final valid = allowedTargets.contains(to);

    if (!valid) {
      DebugLogger.logEvent(
        event: 'invalid_status_transition',
        data: {
          'from': from,
          'to': to,
          'role': role,
        },
      );
    }

    return valid;
  }

  static String getDisplayLabel(String status) {
    final normalized = normalizeStatus(status);
    switch (normalized) {
      case 'placed':
        return 'Placed';
      case 'preparing':
        return 'Preparing';
      case 'prepared':
        return 'Prepared';
      case 'served':
        return 'Served';
      case 'closed':
        return 'Closed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.trim().isEmpty ? 'Unknown' : status.trim();
    }
  }

  static Future<bool> updateOrderStatus({
    required String orderId,
    required String targetStatus,
    required String role,
    required AuthService auth,
    bool force = false,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final orderRef = firestore.collection('orders').doc(orderId);

    final snapshot = await orderRef.get();
    if (!snapshot.exists) {
      DebugLogger.logEvent(event: 'update_order_status_failed', data: {'orderId': orderId, 'reason': 'order_not_found'});
      return false;
    }

    final currentRaw = (snapshot.data()?['status'] ?? '').toString();
    final current = normalizeStatus(currentRaw);
    final target = normalizeStatus(targetStatus);

    if (current == 'placed' && target == 'closed' && !force) {
      DebugLogger.logEvent(
        event: 'forced_transition_required',
        data: {'orderId': orderId, 'from': current, 'to': target, 'role': role},
      );
      return false;
    }

    if (!isValidTransition(current, target, role)) {
      return false;
    }

    await orderRef.update({
      'status': target,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await TableStateSync.syncTableForOrderChange(
      firestore: firestore,
      tableId: (snapshot.data()?['tableId'] ?? '').toString(),
      orderId: orderId,
      orderState: target,
      auth: auth,
    );

    DebugLogger.logEvent(
      event: 'status_updated',
      data: {
        'orderId': orderId,
        'from': current,
        'to': target,
        'role': role,
        'force': force,
      },
    );

    return true;
  }

  static String normalizeOrderStatusForRead({
    required dynamic rawStatus,
    required AuthService auth,
    String? orderId,
    String? tableId,
    String? source,
  }) {
    final status = (rawStatus ?? 'active').toString();
    final normalized = normalizeStatus(status);

    if (status.trim().toLowerCase() == 'open') {
      DebugLogger.logEvent(
        event: 'open_interpreted_as_active',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': tableId,
          'orderId': orderId,
          'lockedBy': null,
          'previousState': 'open',
          'newState': normalized,
          'source': source,
        },
      );
    }

    return normalized;
  }

  static void logActiveStatusWrite({
    required AuthService auth,
    String? orderId,
    String? tableId,
    String? previousState,
    String? source,
  }) {
    DebugLogger.logEvent(
      event: 'status_written_active',
      data: {
        'userRole': auth.role.name,
        'userId': auth.currentUser?.uid,
        'tableId': tableId,
        'orderId': orderId,
        'lockedBy': null,
        'previousState': previousState,
        'newState': 'placed',
        'source': source,
      },
    );
  }
}
