enum TableStatus { available, occupied, kotSent, billRequested }

class TableModel {
  final String id;
  final String name;
  final int capacity;
  final TableStatus status;
  final String section;
  final String? currentOrderId; // Useful to navigate directly to the open order

  TableModel({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    required this.section,
    this.currentOrderId,
  });

  factory TableModel.fromMap(String documentId, Map<String, dynamic> data) {
    TableStatus mapStatus(String statusStr) {
      switch (statusStr) {
        case 'occupied': return TableStatus.occupied;
        case 'kotSent': return TableStatus.kotSent;
        case 'billRequested': return TableStatus.billRequested;
        default: return TableStatus.available;
      }
    }

    return TableModel(
      id: documentId,
      name: data['name'] ?? '',
      capacity: data['capacity'] ?? 2,
      status: mapStatus(data['status'] ?? 'available'),
      section: data['section']?.toString().trim().isNotEmpty == true
          ? data['section'].toString().trim()
          : 'Main',
      currentOrderId: data['currentOrderId'],
    );
  }
}
