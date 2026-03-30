import 'package:flutter_test/flutter_test.dart';
import 'package:shreerajmandir/models/table_model.dart';
import 'package:shreerajmandir/utils/table_sort_utils.dart';

void main() {
  group('sortTablesByNumber', () {
    test('sorts numeric strings numerically instead of lexicographically', () {
      final sorted = sortTablesByNumber<String>(
        ['10', '2', '1'],
        valueOf: (value) => value,
      );

      expect(sorted, ['1', '2', '10']);
    });

    test('sorts mixed number and string values using numeric table number', () {
      final sorted = sortTablesByNumber<Object?>(
        ['10', 2, '1'],
        valueOf: (value) => value,
      );

      expect(sorted, ['1', 2, '10']);
    });

    test('pushes null and invalid values to the end without crashing', () {
      final sorted = sortTablesByNumber<Object?>(
        [null, 'Table X', '2', 'Table 10'],
        valueOf: (value) => value,
      );

      expect(sorted, ['2', 'Table 10', null, 'Table X']);
    });

    test('sorts table models by parsed table number from their names', () {
      final tables = [
        TableModel(id: 'a', name: '10', capacity: 4, status: TableStatus.available),
        TableModel(id: 'b', name: '2', capacity: 4, status: TableStatus.available),
        TableModel(id: 'c', name: '1', capacity: 4, status: TableStatus.available),
      ];

      final sorted = sortTableModelsByNumber(tables);

      expect(sorted.map((table) => table.name).toList(), ['1', '2', '10']);
    });
  });
}
