import 'package:cloud_firestore/cloud_firestore.dart';

import '../seeds/default_staff_seed.dart';
import 'auth_service.dart';

class StaffSeedResult {
  const StaffSeedResult({
    required this.created,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  final int created;
  final int skipped;
  final int failed;
  final List<String> errors;
}

class StaffSeedService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<StaffSeedResult> seedDefaultUsers(AuthService auth) async {
    if (auth.role != UserRole.admin) {
      return const StaffSeedResult(
        created: 0,
        skipped: 0,
        failed: 1,
        errors: ['Only Admin can run seeding.'],
      );
    }

    final restaurantId = auth.restaurantId;
    final manager = auth.currentUser;

    if (restaurantId == null || manager == null) {
      return const StaffSeedResult(
        created: 0,
        skipped: 0,
        failed: 1,
        errors: ['Admin profile/restaurant is missing.'],
      );
    }

    await _firestore.collection('users').doc(manager.uid).set({
      'name': manager.email?.split('@').first ?? 'Main Admin',
      'email': manager.email,
      'role': 'admin',
      'restaurantId': restaurantId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    int created = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    for (final seedUser in defaultStaffSeed) {
      final exists = await _firestore
          .collection('users')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('email', isEqualTo: seedUser.email)
          .limit(1)
          .get();

      if (exists.docs.isNotEmpty) {
        skipped++;
        continue;
      }

      final error = await auth.adminCreateUser(
        email: seedUser.email,
        password: seedUser.password,
        name: seedUser.name,
        role: seedUser.role,
        phone: seedUser.phone,
        pin: seedUser.pin,
      );

      if (error == null) {
        created++;
      } else {
        failed++;
        errors.add('${seedUser.email}: $error');
      }
    }

    return StaffSeedResult(
      created: created,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }
}