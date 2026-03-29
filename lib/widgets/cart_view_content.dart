import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/debug_logger.dart';
import '../../services/report_service.dart';
import '../../utils/order_status_utils.dart';
import '../../utils/table_state_sync.dart';
import '../providers/cart_provider.dart';

class CartViewContent extends StatefulWidget {
  final bool isBottomSheet;
  const CartViewContent({super.key, this.isBottomSheet = false});

  @override
  State<CartViewContent> createState() => _CartViewContentState();
}

class _CartViewContentState extends State<CartViewContent> {
  bool _isSubmitting = false;

  Future<bool> _isOrderLockedForBilling({
    required String orderId,
    required String tableId,
    required String attemptedAction,
  }) async {
    final orderSnapshot = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    if (!orderSnapshot.exists) return false;

    final status = (orderSnapshot.data()?['status'] ?? '').toString();
    if (status != 'bill_requested') return false;

    final auth = context.read<AuthService>();
    DebugLogger.logEvent(
      event: 'blocked_action_bill_requested',
      data: {
        'userRole': auth.role.name,
        'userId': auth.currentUser?.uid,
        'tableId': tableId,
        'orderId': orderId,
        'lockedBy': null,
        'attemptedAction': attemptedAction,
        'previousState': status,
        'newState': status,
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.isBottomSheet ? const BorderRadius.vertical(top: Radius.circular(24)) : null,
      ),
      padding: const EdgeInsets.only(top: 16),
      child: SafeArea(
        child: Column(
          children: [
            if (widget.isBottomSheet)
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            const Text('Your Order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: Consumer<CartProvider>(
                builder: (context, cart, child) {
                  if (cart.items.isEmpty) {
                    return const Center(child: Text('Cart is empty'));
                  }
                  return ListView.builder(
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final cartItem = cart.items[index];
                      return Dismissible(
                        key: ValueKey('${cartItem.item.id}_${cartItem.specialInstructions}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          cart.removeItem(cartItem);
                        },
                        child: ListTile(
                          title: Text(cartItem.item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: cartItem.specialInstructions.isNotEmpty
                              ? Text('Note: ${cartItem.specialInstructions}', style: const TextStyle(color: Colors.redAccent))
                              : null,
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                                    onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity - 1),
                                  ),
                                  const SizedBox(width: 4),
                                  Text('${cartItem.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.add_circle_outline, size: 18),
                                    onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity + 1),
                                  ),
                                ],
                              ),
                              Text('₹${cartItem.totalPrice.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            Consumer<CartProvider>(
              builder: (context, cart, child) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('₹${cart.totalAmount.toStringAsFixed(0)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                );
              }
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    return ElevatedButton(
                      onPressed: cart.items.isEmpty || _isSubmitting ? null : () => _placeOrder(cart, context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Send Table to KOT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    );
                  }
                ),
              ),
            )
          ],
        ),
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
      final restaurantId = auth.restaurantId;
      final restaurantName = auth.restaurantName ?? "ShreeRajmandir";
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
          'status': 'active',
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': cartTotal,
          'items': cartItemsSummary,
        });
        // Ensure table state follows order state (active -> occupied)
        await TableStateSync.syncTableForOrderChange(
          firestore: firestore,
          tableId: tableId!,
          orderId: orderId,
          orderState: 'active',
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
        'status': 'Pending',
        'restaurantId': restaurantId,
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
          'status': 'Pending',
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
