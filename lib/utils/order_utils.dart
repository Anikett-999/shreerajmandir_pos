bool isOrderEditable(dynamic rawStatus) {
  final status = (rawStatus ?? 'active').toString().trim().toLowerCase();

  switch (status) {
    case 'bill_requested':
    case 'billed':
    case 'cancelled':
      return false;
    default:
      return true;
  }
}
