import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// HELP: RUN THIS FROM A BUTTON IN THE APP (e.g. in a "Dev Mode" or "Settings" menu)
/// This script will assign a default restaurantId to all existing documents that miss it.
class DataMigrationService {
  static bool _isMissingRestaurantId(dynamic restaurantId) {
    final normalized = restaurantId?.toString().trim();
    return normalized == null || normalized.isEmpty;
  }

  static bool _isKitchenRole(dynamic role) {
    final normalized = (role ?? '').toString().trim().toLowerCase();
    return normalized == 'kitchen' || normalized == 'chef';
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> findKitchenUsersMissingRestaurantId() async {
    final firestore = FirebaseFirestore.instance;
    final snap = await firestore.collection('users').get();

    return snap.docs.where((doc) {
      final data = doc.data();
      return _isKitchenRole(data['role']) && _isMissingRestaurantId(data['restaurantId']);
    }).toList();
  }

  static Future<int> backfillKitchenUsersRestaurantId(String restaurantId) async {
    final firestore = FirebaseFirestore.instance;
    final missingUsers = await findKitchenUsersMissingRestaurantId();
    if (missingUsers.isEmpty) return 0;

    final batch = firestore.batch();
    for (final doc in missingUsers) {
      batch.update(doc.reference, {
        'restaurantId': restaurantId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return missingUsers.length;
  }

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

    // Log via DebugLogger instead of printing to stdout
    // Note: this migration helper is intended for developer use only.
    // Use DebugLogger so production logs are consistent.
    // Import is not added at top to avoid changing public API; use debugPrint fallback.
    debugPrint('Starting migration for restaurant: $restaurantId');

    for (var colName in collections) {
      final snap = await firestore.collection(colName).get();
      final batch = firestore.batch();
      int count = 0;

      for (var doc in snap.docs) {
        final data = doc.data();
        if (!data.containsKey('restaurantId') || _isMissingRestaurantId(data['restaurantId'])) {
          batch.update(doc.reference, {'restaurantId': restaurantId});
          count++;
        }
      }

        if (count > 0) {
        await batch.commit();
        debugPrint('Migrated $count documents in $colName');
      } else {
        debugPrint('No documents to migrate in $colName');
      }
    }
    
    debugPrint('Migration complete!');
  }

  static Future<Map<String, int>> migrateLegacyRestaurantReference({
    required String legacyRestaurantId,
    required String canonicalRestaurantId,
    String? restaurantCode,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final updatedCounts = <String, int>{};
    final collections = [
      'users',
      'menu_categories',
      'menu_items',
      'tables',
      'orders',
      'kots',
    ];

    for (final colName in collections) {
      final snap = await firestore
          .collection(colName)
          .where('restaurantId', isEqualTo: legacyRestaurantId)
          .get();
      if (snap.docs.isEmpty) continue;

      final batch = firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'restaurantId': canonicalRestaurantId,
          if (restaurantCode != null && restaurantCode.trim().isNotEmpty) 'restaurantCode': restaurantCode.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      updatedCounts[colName] = snap.docs.length;
    }

    return updatedCounts;
  }

  static Future<int> migrateDailyCollectionDocumentIds({
    required String legacyRestaurantId,
    required String canonicalRestaurantId,
    String? restaurantCode,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final snap = await firestore.collection('daily_collections').get();
    var migrated = 0;

    for (final doc in snap.docs) {
      if (!doc.id.startsWith('${legacyRestaurantId}_')) continue;
      final suffix = doc.id.substring(legacyRestaurantId.length);
      final targetId = '$canonicalRestaurantId$suffix';
      final data = {
        ...doc.data(),
        'restaurantId': canonicalRestaurantId,
        if (restaurantCode != null && restaurantCode.trim().isNotEmpty) 'restaurantCode': restaurantCode.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await firestore.collection('daily_collections').doc(targetId).set(data, SetOptions(merge: true));
      migrated++;
    }

    return migrated;
  }

  static Future<bool> migrateReceiptCounterDocumentId({
    required String legacyRestaurantId,
    required String canonicalRestaurantId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final oldDoc = await firestore.collection('receipt_counters').doc(legacyRestaurantId).get();
    if (!oldDoc.exists) return false;

    await firestore.collection('receipt_counters').doc(canonicalRestaurantId).set(
      {
        ...?oldDoc.data(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }
}
