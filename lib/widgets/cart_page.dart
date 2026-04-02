import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/cart_provider.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../services/report_service.dart';
import '../utils/table_state_sync.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _isSubmitting = false;

  Future<void> _placeOrder(CartProvider cart, BuildContext context) async {
    if (cart.tableId == null) return;
    setState(() => _isSubmitting = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      final tableRef = firestore.collection('tables').doc(cart.tableId);
      final tableDoc = await tableRef.get();
      
      String orderId;
      final cartTotal = cart.totalAmount;
      final cartItemsSummary = cart.items.map((i) => {
        'id': i.item.id,
        'name': i.item.name,
        'price': i.item.price,
        'quantity': i.quantity,
        'category': i.item.category,
      }).toList();

      final auth = context.read<AuthService>();
      final tableRestaurantId = (tableDoc.data()?['restaurantId'] ?? '').toString().trim();
      final restaurantId = auth.restaurantId ?? (tableRestaurantId.isNotEmpty ? tableRestaurantId : null);
      final restaurantCode = auth.restaurantCode;
      if (restaurantId == null || restaurantId.isEmpty) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                auth.profileIssueMessage ?? 'Restaurant profile missing for this user.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final tableId = cart.tableId;
      bool isOrderCreated = false;

      if (tableDoc.exists && tableDoc.data()?['currentOrderId'] != null) {
        orderId = tableDoc.data()!['currentOrderId'];
        // No lock check for simplicity; add if needed
        final orderRef = firestore.collection('orders').doc(orderId);
        batch.update(orderRef, {
          'totalAmount': FieldValue.increment(cartTotal),
          'items': FieldValue.arrayUnion(cartItemsSummary),
        });
      } else {
        final orderRef = firestore.collection('orders').doc();
        orderId = orderRef.id;
        isOrderCreated = true;
        batch.set(orderRef, {
          'tableId': cart.tableId,
          'tableName': (tableDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown',
          'waiterName': 'Waiter',
          'status': 'placed',
          'restaurantId': restaurantId,
          if (restaurantCode != null) 'restaurantCode': restaurantCode,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': cartTotal,
          'items': cartItemsSummary,
        });
        // Table state sync: update table status to occupied and set currentOrderId
        await TableStateSync.syncTableForOrderChange(
          firestore: firestore,
          tableId: tableId!,
          orderId: orderId,
          orderState: 'placed',
          auth: auth,
          batch: batch,
        );
      }

      final kotRef = firestore.collection('kots').doc();
      final kotId = kotRef.id;

      final kotItems = cart.items.map((cartItem) => {
        'menuItemId': cartItem.item.id,
        'name': cartItem.item.name,
        'quantity': cartItem.quantity,
        'price': cartItem.item.price,
        'specialInstructions': cartItem.specialInstructions,
      }).toList();

      final itemsRef = firestore.collection('orders').doc(orderId).collection('items');
      for (var cartItem in cart.items) {
        final newItemRef = itemsRef.doc();
        batch.set(newItemRef, {
          'kotId': kotId,
          'menuItemId': cartItem.item.id,
          'name': cartItem.item.name,
          'quantity': cartItem.quantity,
          'price': cartItem.item.price,
          'totalPrice': cartItem.totalPrice,
          'specialInstructions': cartItem.specialInstructions,
          'restaurantId': restaurantId,
          if (restaurantCode != null) 'restaurantCode': restaurantCode,
          'status': 'placed',
        });
      }

      await batch.commit();

      // Order and order-items persisted. Now attempt to print KOT using
      // the shared ReportService (same as Cashier). Do not block order
      // persistence on printing failures.
      final kotData = {
        'tableName': (tableDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown',
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'price': i.item.price,
        }).toList(),
      };
      try {
        DebugLogger.logEvent(event: 'kot_print_invoked', data: {'orderId': orderId, 'kotId': kotId});
        // UI feedback: notify user that printing started
        mounted ? ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sending KOT to printer...'),
          duration: Duration(seconds: 3),
        )) : null;
        await ReportService.printKOT(kotData, orderId);
        DebugLogger.logEvent(event: 'kot_print_finished', data: {'orderId': orderId, 'kotId': kotId, 'status': 'success'});
        // UI feedback: notify user that printing succeeded
        mounted ? ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('KOT printed successfully'),
          duration: Duration(seconds: 2),
        )) : null;
      } catch (e) {
        DebugLogger.logEvent(event: 'kot_print_finished', data: {'orderId': orderId, 'kotId': kotId, 'status': 'failed', 'error': e.toString()});
        // UI feedback: notify user that printing failed
        mounted ? ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('KOT saved but printing failed: $e'),
          backgroundColor: Colors.orange,
        )) : null;
      }

      // Persist the KOT document now that printing was attempted
      await firestore.collection('kots').doc(kotId).set({
        'orderId': orderId,
        'tableId': cart.tableId,
        'tableName': (tableDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown',
        'status': 'placed',
        'restaurantId': restaurantId,
        if (restaurantCode != null) 'restaurantCode': restaurantCode,
        'items': kotItems,
        'createdAt': FieldValue.serverTimestamp(),
        'kotNumber': kotId.substring(0, 6).toUpperCase(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order Placed! KOT: ${kotId.substring(0, 6).toUpperCase()}'),
          backgroundColor: Colors.green,
        ));
        cart.clearCart();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to place order: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);
    final maroon = const Color(0xFF922224);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: maroon,
        title: const Text('Cart'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: cart.items.isEmpty
                ? null
                : () {
                    cart.clearCart();
                  },
          ),
        ],
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Text(
                'Cart is empty',
                style: theme.textTheme.titleMedium?.copyWith(color: maroon, fontWeight: FontWeight.bold),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: cart.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final cartItem = cart.items[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            cartItem.item.name,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: cartItem.specialInstructions.isNotEmpty
                              ? Text('Note: ${cartItem.specialInstructions}', style: theme.textTheme.bodySmall)
                              : null,
                          leading: CircleAvatar(
                            backgroundColor: maroon.withOpacity(0.1),
                            child: Text('${cartItem.quantity}', style: TextStyle(color: maroon, fontWeight: FontWeight.bold)),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () {
                                  if (cartItem.quantity > 1) {
                                    cart.updateQuantity(cartItem, cartItem.quantity - 1);
                                  } else {
                                    cart.removeItem(cartItem);
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity + 1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => cart.removeItem(cartItem),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total:',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '₹${cart.totalAmount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: maroon,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_isSubmitting ? 'Placing Order...' : 'Place Order'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSubmitting || cart.items.isEmpty
                          ? null
                          : () async {
                              await _placeOrder(cart, context);
                            },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
