import 'package:flutter_test/flutter_test.dart';
import 'package:shreerajmandir/services/auth_service.dart';

void main() {
  group('userRoleFromString', () {
    test('maps chef to kitchen role', () {
      expect(userRoleFromString('chef'), UserRole.kitchen);
    });
  });

  group('normalizeRestaurantId', () {
    test('returns null for null and blank values', () {
      expect(normalizeRestaurantId(null), isNull);
      expect(normalizeRestaurantId(''), isNull);
      expect(normalizeRestaurantId('   '), isNull);
    });

    test('trims valid values', () {
      expect(normalizeRestaurantId(' rest-1 '), 'rest-1');
    });
  });

  group('AuthProfileResolution', () {
    test('fresh login with valid kitchen profile hydrates and unlocks', () {
      final resolution = resolveAuthProfileData(
        userExists: true,
        userData: const {
          'role': 'kitchen',
          'restaurantId': 'rest-1',
          'status': 'active',
        },
        hasSavedPin: false,
        restaurantExists: true,
        restaurantName: 'Rajmandir',
        restaurantCode: 'RJM-001',
      );

      expect(resolution.hasError, isFalse);
      expect(resolution.shouldUnlock, isTrue);
      expect(resolution.role, UserRole.kitchen);
      expect(resolution.restaurantId, 'rest-1');
      expect(resolution.restaurantCode, 'RJM-001');
    });

    test('saved PIN session keeps hydrated context but delays unlock', () {
      final resolution = resolveAuthProfileData(
        userExists: true,
        userData: const {
          'role': 'chef',
          'restaurantId': 'rest-1',
          'status': 'active',
        },
        hasSavedPin: true,
        restaurantExists: true,
        restaurantName: 'Rajmandir',
        restaurantCode: 'RJM-001',
      );

      expect(resolution.hasError, isFalse);
      expect(resolution.shouldUnlock, isFalse);
      expect(resolution.role, UserRole.kitchen);
      expect(resolution.restaurantId, 'rest-1');
      expect(resolution.restaurantCode, 'RJM-001');
    });

    test('surfaces missing restaurant assignment error', () {
      final resolution = resolveAuthProfileData(
        userExists: true,
        userData: const {
          'role': 'kitchen',
          'status': 'active',
        },
        hasSavedPin: false,
        restaurantExists: false,
      );

      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'Your user profile is missing a restaurant assignment. Contact admin.',
      );
    });

    test('surfaces missing restaurant document error', () {
      final resolution = resolveAuthProfileData(
        userExists: true,
        userData: const {
          'role': 'kitchen',
          'restaurantId': 'rest-404',
          'status': 'active',
        },
        hasSavedPin: false,
        restaurantExists: false,
      );

      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'Assigned restaurant profile could not be found. Contact admin.',
      );
    });
  });
}
