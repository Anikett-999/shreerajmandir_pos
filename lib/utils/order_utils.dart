import 'order_status_utils.dart';

bool isOrderEditable(dynamic rawStatus) {
  final status = OrderStatusUtils.normalizeStatus(rawStatus?.toString() ?? '');
  switch (status) {
    case 'served':
    case 'closed':
    case 'cancelled':
      return false;
    default:
      return true;
  }
}
