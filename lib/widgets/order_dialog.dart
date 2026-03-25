import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../models/table_model.dart';
import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../services/report_service.dart';
import '../utils/debouncer.dart';

class CommonOrderDialog extends StatefulWidget {
  final TableModel table;
  const CommonOrderDialog({super.key, required this.table});

  @override
  State<CommonOrderDialog> createState() => _CommonOrderDialogState();
}

class _CommonOrderDialogState extends State<CommonOrderDialog> {
  String _selectedCategory = "All";
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<CartItem> _selectedItems = [];
  final Debouncer _debouncer = Debouncer(milliseconds: 1000);

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Dialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
      child: Container(
        width: isMobile ? screenWidth : screenWidth * 0.9,
        height: MediaQuery.of(context).size.height * (isMobile ? 1.0 : 0.9),
        color: Colors.grey[50],
        child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _buildDialogHeader(),
          _buildSearchBar(),
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: Colors.brown[700],
              indicatorColor: Colors.brown[700],
              tabs: [
                Tab(text: "Menu", icon: const Icon(Icons.restaurant_menu, size: 18)),
                Tab(
                  text: "Cart (${_selectedItems.fold(0, (sum, i) => sum + i.quantity)})",
                  icon: const Icon(Icons.shopping_cart, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_buildMenuPane(), _buildCartPane()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // LEFT SIDE: MENU GRID
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogHeader(),
                const SizedBox(height: 12),
                _buildSearchBar(),
                const SizedBox(height: 12),
                Expanded(child: _buildMenuPane()),
              ],
            ),
          ),
        ),
        // RIGHT SIDE: CATEGORIES SIDEBAR (As per Reference Image)
        _buildCategorySidebar(),
        // FAR RIGHT: CART (Toggleable or persistent)
        Container(
          width: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(left: BorderSide(color: Colors.grey[200]!)),
          ),
          child: _buildCartPane(),
        ),
      ],
    );
  }

  Widget _buildCategorySidebar() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            width: double.infinity,
            color: Colors.grey[50],
            child: const Center(child: Text("Categories", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('menu_categories')
                  .where('restaurantId', isEqualTo: restaurantId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final cats = (snapshot.data?.docs ?? []).toList();
                cats.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));

                return ListView(
                  children: [
                    _buildCategoryItem("All", null, _selectedCategory == "All"),
                    ...cats.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name'] ?? 'N/A';
                      final imageUrl = data['imageUrl'];
                      return _buildCategoryItem(name, imageUrl, _selectedCategory == name);
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(String name, String? imageUrl, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedCategory = name),
      child: Container(
        height: 90,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF800000).withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF800000).withOpacity(0.3) : Colors.grey[100]!),
          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF800000).withOpacity(0.1), blurRadius: 4)] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1.5,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: imageUrl != null 
                  ? Image.network(imageUrl, fit: BoxFit.cover)
                  : Icon(Icons.category, color: isSelected ? const Color(0xFF800000) : Colors.grey[300], size: 24),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    name, 
                    style: TextStyle(
                      fontSize: 10, 
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFF800000) : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Table ${widget.table.name}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(DateFormat('dd MMM, hh:mm a').format(DateTime.now()), style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
        Row(
          children: [
             Text("Total: ₹${_selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity)).toStringAsFixed(0)}", 
               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF800000))),
             const SizedBox(width: 16),
             IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search items...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
            : null,
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[200]!)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[200]!)),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      ),
    );
  }

  Widget _buildMenuPane() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('isAvailable', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allDocs = snapshot.data!.docs;
        final allItems = allDocs.map((doc) => MenuItem.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();

        final filteredItems = allItems.where((i) {
          final matchesCategory = _selectedCategory == "All" || i.category == _selectedCategory;
          final matchesSearch = _searchQuery.isEmpty || i.name.toLowerCase().contains(_searchQuery);
          return matchesCategory && matchesSearch;
        }).toList();

        return Column(
          children: [
            Expanded(
              child: filteredItems.isEmpty
                ? const Center(child: Text("No items available.", style: TextStyle(color: Colors.grey)))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth < 400 ? 3 : (constraints.maxWidth < 600 ? 4 : 5);
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return InkWell(
                            onTap: () => setState(() {
                              final existingIdx = _selectedItems.indexWhere((i) => i.item.id == item.id);
                              if (existingIdx >= 0) {
                                _selectedItems[existingIdx].quantity++;
                              } else {
                                _selectedItems.add(CartItem(item: item));
                              }
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[100]!),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: item.imageUrl != null 
                                          ? Image.network(item.imageUrl!, fit: BoxFit.cover, width: double.infinity)
                                          : Center(child: Icon(Icons.fastfood, size: 28, color: Colors.grey[200])),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text("₹${item.price.toStringAsFixed(0)}", style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 9)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCartPane() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("Your Order", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),

        Expanded(
          child: _selectedItems.isEmpty
            ? const Center(child: Text("Cart is empty", style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _selectedItems.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final i = _selectedItems[index];
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.item.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            Text("₹${i.item.price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 22),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () => setState(() {
                              if (_selectedItems[index].quantity > 1) {
                                _selectedItems[index].quantity--;
                              } else {
                                _selectedItems.removeAt(index);
                              }
                            }),
                          ),
                          Text("${i.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.green, size: 22),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () => setState(() => _selectedItems[index].quantity++),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
        ),

        // Total + Button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    "₹${_selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity)).toStringAsFixed(2)}",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown[800]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _selectedItems.isEmpty ? null : () => _debouncer.run(() => _submitOrder()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Place Order (Send KOT)", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _submitOrder() async {
     final auth = context.read<AuthService>();
    final waiterDisplayName = auth.role == UserRole.admin ? "Admin (${auth.currentUser?.email?.split('@')[0] ?? 'Admin'})" : "Cashier";
     final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));

     final firestore = FirebaseFirestore.instance;
     final batch = firestore.batch();
     final orderRef = firestore.collection('orders').doc();
     
     batch.set(orderRef, {
        'tableId': widget.table.id,
        'tableName': widget.table.name,
        'waiterName': waiterDisplayName,
        'status': 'open',
        'restaurantId': auth.restaurantId,
        'createdAt': FieldValue.serverTimestamp(),
        'totalAmount': total,
        'items': _selectedItems.map((i) => {
           'id': i.item.id,
           'name': i.item.name,
           'price': i.item.price,
           'quantity': i.quantity,
           'category': i.item.category,
        }).toList(),
     });

     final itemsRef = orderRef.collection('items');
     for (var i in _selectedItems) {
        batch.set(itemsRef.doc(), {
           'menuItemId': i.item.id,
           'name': i.item.name,
           'price': i.item.price,
           'quantity': i.quantity,
           'totalPrice': i.item.price * i.quantity,
           'category': i.item.category,
           'restaurantId': auth.restaurantId,
           'status': 'Pending',
           'createdAt': FieldValue.serverTimestamp(),
        });
     }

     final kotRef = firestore.collection('kots').doc();
     batch.set(kotRef, {
        'orderId': orderRef.id,
        'tableId': widget.table.id,
        'tableName': widget.table.name,
        'status': 'Pending',
        'restaurantId': auth.restaurantId,
        'createdAt': FieldValue.serverTimestamp(),
        'waiterName': waiterDisplayName,
        'items': _selectedItems.map((i) => {
           'name': i.item.name,
           'quantity': i.quantity,
        }).toList(),
     });

     final tableRef = firestore.collection('tables').doc(widget.table.id);
     batch.update(tableRef, {
        'status': TableStatus.occupied.name,
        'currentOrderId': orderRef.id,
     });

     await batch.commit();

     final kotData = {
        'tableName': widget.table.name,
        'items': _selectedItems.map((i) => {
           'name': i.item.name,
           'quantity': i.quantity,
           'price': i.item.price,
        }).toList(),
     };
     
     await ReportService.printKOTReceipt(kotData, orderRef.id);

     if (mounted) {
       Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order placed! KOT sent to kitchen."), backgroundColor: Colors.green));
     }
  }
}
