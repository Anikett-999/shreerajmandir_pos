class SeedStaffUser {
  const SeedStaffUser({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.phone,
    this.pin,
  });

  final String name;
  final String email;
  final String password;
  final String role;
  final String? phone;
  final String? pin;
}

const List<SeedStaffUser> defaultStaffSeed = [
  SeedStaffUser(
    name: 'Cashier One',
    email: 'cashier@test.com',
    password: 'Cashier@123',
    role: 'cashier',
    phone: '8888888888',
    pin: '2222',
  ),
  SeedStaffUser(
    name: 'Waiter One',
    email: 'waiter@test.com',
    password: 'Waiter@123',
    role: 'waiter',
    phone: '7777777777',
    pin: '3333',
  ),
];