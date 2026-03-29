import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../models/table_model.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/cart_view_content.dart';

class MenuScreen extends StatefulWidget {
  final TableModel table;
  const MenuScreen({super.key, required this.table});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  final Map<String, bool> _isAddAnimating = {};
  final Map<String, Timer> _addTimers = {};

  @override
  void dispose() {
    for (final timer in _addTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().setTable(widget.table.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              _buildTabs(),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildMenuGrid(),
                    const CartViewContent(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final primary = Theme.of(context).colorScheme.primary;
    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 380;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Table ${widget.table.name}',
                          style: TextStyle(
                            fontSize: isCompact ? 18 : 20,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dateTimeNowText(),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Total: ₹${cart.totalAmount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: isCompact ? 16 : 20,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: isCompact ? 28 : 30),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search items...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final primary = Theme.of(context).colorScheme.primary;
    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        return TabBar(
          indicatorColor: primary,
          labelColor: primary,
          unselectedLabelColor: Colors.black54,
          tabs: [
            const Tab(
              icon: Icon(Icons.restaurant_menu),
              text: 'Menu',
            ),
            Tab(
              icon: const Icon(Icons.shopping_cart),
              text: 'Cart (${cart.totalItems})',
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuGrid() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('menu_categories')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, categorySnapshot) {
        if (!categorySnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final visibleCategories = categorySnapshot.data!.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .where((data) => data['isVisible'] != false)
            .map((data) => (data['name'] ?? '').toString())
            .where((name) => name.isNotEmpty)
            .toSet();

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('menu_items')
              .where('restaurantId', isEqualTo: restaurantId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final items = snapshot.data!.docs
                .map((d) => MenuItem.fromMap(d.id, d.data() as Map<String, dynamic>))
                .where((item) {
                  final categoryAllowed = visibleCategories.contains(item.category);
                  final matchesSearch =
                      _searchQuery.isEmpty || item.name.toLowerCase().contains(_searchQuery);
                  return item.isAvailable && categoryAllowed && matchesSearch;
                })
                .toList();

            return Consumer<CartProvider>(
              builder: (context, cart, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount = 2;
                    if (constraints.maxWidth > 1200) {
                      crossAxisCount = 6;
                    } else if (constraints.maxWidth > 900) {
                      crossAxisCount = 4;
                    } else if (constraints.maxWidth > 600) {
                      crossAxisCount = 3;
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final cartQty = _cartQtyForItem(item.id, cart);
                        final showAddFx = _isAddAnimating[item.id] == true;
                        return _buildMenuItemCard(item, cartQty, showAddFx);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMenuItemCard(MenuItem item, int cartQty, bool showAddFx) {
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrowCard = constraints.maxWidth < 170;
        final nameSize = isNarrowCard ? 13.0 : 16.0;
        final priceSize = isNarrowCard ? 13.0 : 16.0;
        final badgeSize = isNarrowCard ? 9.0 : 11.0;

        return Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: item.isAvailable ? () => _quickAddItem(item) : null,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        color: Colors.grey[200],
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? Image.network(
                                item.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, size: 48, color: Colors.grey),
                              )
                            : const Icon(Icons.fastfood, size: 48, color: Colors.grey),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: EdgeInsets.all(isNarrowCard ? 8 : 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: nameSize),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '₹${item.price.toStringAsFixed(0)}',
                                    style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: priceSize),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!item.isAvailable)
                                  const Text(
                                    'Out',
                                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                  )
                                else
                                  Container(
                                    decoration: BoxDecoration(
                                      color: primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: IconButton(
                                      onPressed: () => _quickAddItem(item),
                                      icon: Icon(Icons.add, color: primary, size: isNarrowCard ? 18 : 22),
                                      padding: const EdgeInsets.all(4),
                                      constraints: BoxConstraints(minWidth: isNarrowCard ? 28 : 32, minHeight: isNarrowCard ? 28 : 32),
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Add one more',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
                if (cartQty > 0)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$cartQty in cart',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: badgeSize,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: AnimatedOpacity(
                    opacity: showAddFx ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: AnimatedScale(
                      scale: showAddFx ? 1 : 0.85,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '+1',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _cartQtyForItem(String itemId, CartProvider cart) {
    return cart.items
        .where((cartItem) => cartItem.item.id == itemId)
        .fold<int>(0, (sum, cartItem) => sum + cartItem.quantity);
  }

  void _quickAddItem(MenuItem item) {
    final cart = context.read<CartProvider>();
    cart.addItem(item, quantity: 1);
    HapticFeedback.selectionClick();
    _addTimers[item.id]?.cancel();
    setState(() {
      _isAddAnimating[item.id] = true;
    });
    _addTimers[item.id] = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _isAddAnimating[item.id] = false;
      });
    });
  }

  String _dateTimeNowText() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final day = now.day.toString().padLeft(2, '0');
    final month = months[now.month - 1];
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    return '$day $month, $hour12:$minute $suffix';
  }
}
