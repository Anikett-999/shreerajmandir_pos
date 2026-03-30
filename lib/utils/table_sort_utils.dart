import '../models/table_model.dart';

int? extractTableNumber(Object? value) {
  if (value == null) return null;

  if (value is num) {
    return value.toInt();
  }

  final normalized = value.toString().trim();
  if (normalized.isEmpty) return null;

  final match = RegExp(r'\d+').firstMatch(normalized);
  if (match == null) return null;

  return int.tryParse(match.group(0)!);
}

String normalizeTableLabel(Object? value) {
  if (value == null) return '';
  return value.toString().trim().toLowerCase();
}

int compareTableValues(
  Object? left,
  Object? right, {
  Object? leftFallback,
  Object? rightFallback,
}) {
  final leftNumber = extractTableNumber(left);
  final rightNumber = extractTableNumber(right);

  if (leftNumber != null && rightNumber != null) {
    final numberCompare = leftNumber.compareTo(rightNumber);
    if (numberCompare != 0) return numberCompare;
  } else if (leftNumber != null) {
    return -1;
  } else if (rightNumber != null) {
    return 1;
  }

  final leftLabel = normalizeTableLabel(leftFallback ?? left);
  final rightLabel = normalizeTableLabel(rightFallback ?? right);
  return leftLabel.compareTo(rightLabel);
}

List<T> sortTablesByNumber<T>(
  Iterable<T> tables, {
  required Object? Function(T table) valueOf,
  Object? Function(T table)? fallbackOf,
}) {
  final sortedTables = tables.toList();
  sortedTables.sort((left, right) {
    return compareTableValues(
      valueOf(left),
      valueOf(right),
      leftFallback: fallbackOf?.call(left),
      rightFallback: fallbackOf?.call(right),
    );
  });
  return sortedTables;
}

List<TableModel> sortTableModelsByNumber(Iterable<TableModel> tables) {
  return sortTablesByNumber(
    tables,
    valueOf: (table) => table.name,
    fallbackOf: (table) => table.name,
  );
}
