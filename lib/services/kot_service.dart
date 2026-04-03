import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/order_status_utils.dart';

class KotService {
  /// Update KOT status with basic transition validation.
  /// Allowed kitchen transitions: placed -> preparing -> prepared
  static Future<void> updateStatus(String kotId, String targetStatus) async {
    final ref = FirebaseFirestore.instance.collection('kots').doc(kotId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('KOT not found');
      final data = snap.data() as Map<String, dynamic>;
      final current = OrderStatusUtils.normalizeStatus((data['status'] ?? '').toString());
      final target = OrderStatusUtils.normalizeStatus(targetStatus);

      const allowed = {
        'placed': ['preparing'],
        'preparing': ['prepared'],
      };

      final allowedTargets = allowed[current] ?? const [];
      if (!allowedTargets.contains(target)) {
        throw Exception('Invalid status transition: $current -> $target');
      }

      // update KOT
      tx.update(ref, {
        'status': target,
        'updatedAt': Timestamp.now(),
      });

      // Also attempt to update the parent order status to keep other clients
      // (waiter/cashier/admin) in sync. This is best-effort inside same
      // transaction so both writes succeed together.
      final orderId = (data['orderId'] ?? '').toString();
      if (orderId.isNotEmpty) {
        final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
        // Note: we don't validate order transitions here; OrderStatusUtils
        // manages that for direct order updates. For KOT-driven updates we
        // optimistically set the order status to the KOT's new status.
        tx.update(orderRef, {
          'status': target,
          'updatedAt': Timestamp.now(),
        });
      }
    });
  }
}
