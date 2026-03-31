import '../utils/order_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../services/report_service.dart';
import '../utils/order_status_utils.dart';
import '../utils/table_state_sync.dart';
import '../providers/cart_provider.dart';

class CartViewContent extends StatefulWidget {
  final bool isBottomSheet;
  const CartViewContent({super.key, this.isBottomSheet = false});

  @override
  State<CartViewContent> createState() => _CartViewContentState();
}

class _CartViewContentState extends State<CartViewContent> {
  bool _isSubmitting = false;

  // Central check for order editability
  Future<bool> _isOrderLockedForBilling({
    required String orderId,
    required String tableId,
    required String attemptedAction,
  }) async {
    final orderSnapshot = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    if (!orderSnapshot.exists) return false;
    final status = (orderSnapshot.data()?['status'] ?? '').toString();
    if (isOrderEditable(status)) return false;
    final auth = context.read<AuthService>();
    DebugLogger.logEvent(
      event: 'order_edit_blocked',
      data: {
        'userRole': auth.role.name,
        'userId': auth.currentUser?.uid,
        'tableId': tableId,
        'orderId': orderId,
        'attemptedAction': attemptedAction,
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order is locked for billing')),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);
    final maroon = const Color(0xFF922224);

    if (cart.items.isEmpty) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Text(
            'Cart is empty',
            style: theme.textTheme.titleMedium?.copyWith(color: maroon, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cart',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: maroon,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
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
              onPressed: _isSubmitting
                  ? null
                  : () => _placeOrder(cart, context),
            ),
          ),
        ],
      ),
    );
  }

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
        final isLocked = await _isOrderLockedForBilling(
          orderId: orderId,
          tableId: cart.tableId!,
          attemptedAction: 'send_kot',
        );
        if (isLocked) {
          if (mounted) {
            setState(() => _isSubmitting = false);
          }
          return;
        }

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
        // Ensure table state follows order state (active -> occupied)
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

      batch.set(kotRef, {
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

      // Table lock released after order/KOT created
      DebugLogger.logEvent(
        event: 'table_lock_released',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': tableId,
          'previousLockedBy': null,
          'newLockedBy': null,
        },
      );

      if (isOrderCreated) {
        OrderStatusUtils.logActiveStatusWrite(
          auth: auth,
          orderId: orderId,
          tableId: tableId,
          previousState: 'none',
          source: 'waiter_cart.create_order',
        );
      }

      if (isOrderCreated) {
        DebugLogger.logEvent(
          event: 'order_created',
          data: {
            'userRole': auth.role.name,
            'userId': auth.currentUser?.uid,
            'tableId': tableId,
            'orderId': orderId,
            'lockedBy': null,
            'previousState': 'none',
            'newState': 'active',
            'itemCount': cart.items.length,
          },
        );
      }

      DebugLogger.logEvent(
        event: 'items_added',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': tableId,
          'orderId': orderId,
          'lockedBy': null,
          'previousState': null,
          'newState': null,
          'itemCount': cart.items.length,
        },
      );
      
      // Auto-Print KOT for Waiter
      final kotData = {
        'tableName': tableDoc.exists ? (tableDoc.data() as Map<String, dynamic>)['name'] : 'Unknown',
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'price': i.item.price,
        }).toList(),
      };
      await ReportService.printKOTReceipt(kotData, orderId);

      DebugLogger.logEvent(
        event: 'kot_sent',
        data: {
          'userRole': auth.role.name,
          'userId': auth.currentUser?.uid,
          'tableId': tableId,
          'orderId': orderId,
          'lockedBy': null,
          'previousState': 'active',
          'newState': 'active',
          'orderProgress': 'kot_sent',
          'kotId': kotId,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order Placed! KOT: ${kotId.substring(0, 6).toUpperCase()}'),
          backgroundColor: Colors.green,
        ));
        cart.clearCart();
        if (widget.isBottomSheet) {
           Navigator.pop(context);
        }
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
}
