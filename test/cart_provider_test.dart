import 'package:flutter_test/flutter_test.dart';
import 'package:shreerajmandir/models/menu_item.dart';
import 'package:shreerajmandir/providers/cart_provider.dart';

void main() {
  group('Cart Provider Unit Tests', () {
    late CartProvider cart;
    late MenuItem burger;
    late MenuItem fries;

    setUp(() {
      cart = CartProvider();
      burger = MenuItem(id: '1', name: 'Burger', category: 'Mains', price: 10.0);
      fries = MenuItem(id: '2', name: 'Fries', category: 'Starters', price: 5.0);
    });

    test('Add item to cart increases total sum and item count', () {
      cart.addItem(burger, quantity: 2);
      expect(cart.totalItems, 2);
      expect(cart.totalAmount, 20.0);
      
      cart.addItem(fries, quantity: 1);
      expect(cart.totalItems, 3);
      expect(cart.totalAmount, 25.0);
    });

    test('Adding same item combines quantities', () {
      cart.addItem(burger, quantity: 1);
      cart.addItem(burger, quantity: 2); // Same item, no special instructions
      expect(cart.items.length, 1);
      expect(cart.items.first.quantity, 3);
      expect(cart.totalAmount, 30.0);
    });

    test('Different special instructions separate cart items', () {
      cart.addItem(burger, quantity: 1, instructions: 'No cheese');
      cart.addItem(burger, quantity: 1, instructions: 'Extra ketchup');
      expect(cart.items.length, 2);
      expect(cart.totalItems, 2);
      expect(cart.totalAmount, 20.0);
    });

    test('Clear cart empties items', () {
      cart.addItem(burger, quantity: 5);
      expect(cart.items.isNotEmpty, true);
      cart.clearCart();
      expect(cart.items.isEmpty, true);
      expect(cart.totalAmount, 0);
    });
  });
}
