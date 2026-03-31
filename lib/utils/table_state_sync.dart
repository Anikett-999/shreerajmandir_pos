import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/debug_logger.dart';

class TableStateSync {
  /// Map order status -> table status string
  static String mapOrderToTable(String orderStatus) {
    final s = orderStatus.toString().trim().toLowerCase();
    if (s == 'placed' || s == 'preparing' || s == 'served' || s == 'active' || s == 'open') return 'occupied';
    if (s == 'bill_requested' || s == 'bill-requested' || s == 'billrequested') return 'occupied';
    if (s == 'closed' || s == 'billed') return 'available';
    if (s == 'cancelled' || s == 'cancel') return 'available';
    return 'occupied';
  }

  /// Sync table state to match order state. Optionally perform the update using
  /// a WriteBatch or Transaction if provided (so callers can include it in
  /// their atomic operations). If neither is provided, a simple update is issued.
  static Future<void> syncTableForOrderChange({
    required FirebaseFirestore firestore,
    required String tableId,
    required String orderId,
    required String orderState,
    required AuthService auth,
    WriteBatch? batch,
    Transaction? transaction,
  }) async {
    final tableState = mapOrderToTable(orderState);
    final tableRef = firestore.collection('tables').doc(tableId);

    // Determine extra fields: if table becomes available, clear currentOrderId
    // if becomes occupied, set currentOrderId to orderId. For billRequested, keep currentOrderId as is.
    final Map<String, dynamic> updateData = {'status': tableState};
    if (tableState == 'available') {
      updateData['currentOrderId'] = null;
    } else if (tableState == 'occupied') {
      updateData['currentOrderId'] = orderId;
    }

    DebugLogger.logEvent(
      event: 'table_state_synced',
      data: {
        'tableId': tableId,
        'orderId': orderId,
        'orderState': orderState,
        'tableState': tableState,
        'userRole': auth.role.name,
        'userId': auth.currentUser?.uid,
      },
    );

    if (batch != null) {
      batch.update(tableRef, updateData);
      return;
    }
    if (transaction != null) {
      transaction.update(tableRef, updateData);
      return;
    }

    await tableRef.update(updateData);
  }
}
