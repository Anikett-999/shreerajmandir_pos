import '../services/auth_service.dart';
import '../services/debug_logger.dart';

class OrderStatusUtils {
  static String normalizeOrderStatusForRead({
    required dynamic rawStatus,
    required AuthService auth,
    String? orderId,
    String? tableId,
    String? source,
  }) {
    final status = (rawStatus ?? 'active').toString().trim().toLowerCase();
    if (status == 'open') {
      DebugLogger.logEvent(
        event: 'open_interpreted_as_active',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': tableId,
          'orderId': orderId,
          'lockedBy': null,
          'previousState': 'open',
          'newState': 'active',
          'source': source,
        },
      );
      return 'active';
    }
    return status;
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
        'newState': 'active',
        'source': source,
      },
    );
  }
}