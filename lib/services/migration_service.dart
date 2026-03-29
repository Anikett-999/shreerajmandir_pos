import 'package:cloud_firestore/cloud_firestore.dart';

/// HELP: RUN THIS FROM A BUTTON IN THE APP (e.g. in a "Dev Mode" or "Settings" menu)
/// This script will assign a default restaurantId to all existing documents that miss it.
class DataMigrationService {
  static Future<void> migrateLegacyData(String restaurantId) async {
    final firestore = FirebaseFirestore.instance;
    final collections = [
      'users',
      'menu_categories',
      'menu_items',
      'tables',
      'orders',
      'kots',
      'daily_collections'
    ];

    print('Starting migration for restaurant: $restaurantId');

    for (var colName in collections) {
      final snap = await firestore.collection(colName).get();
      final batch = firestore.batch();
      int count = 0;

      for (var doc in snap.docs) {
        final data = doc.data();
        if (!data.containsKey('restaurantId')) {
          batch.update(doc.reference, {'restaurantId': restaurantId});
          count++;
        }
      }

      if (count > 0) {
        await batch.commit();
        print('Migrated $count documents in $colName');
      } else {
        print('No documents to migrate in $colName');
      }
    }
    
    print('Migration complete!');
  }
}
