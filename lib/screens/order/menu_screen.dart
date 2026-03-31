import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/table_model.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/cart_bottom_sheet.dart';
import '../../widgets/cart_view_content.dart';

class MenuScreen extends StatefulWidget {
  final TableModel table;
  const MenuScreen({super.key, required this.table});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedCategory = 'All';

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
      appBar: AppBar(
        title: Text('Table ${widget.table.name} Menu'),
        backgroundColor: const Color(0xFF8C0D20),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildCategoryTabs(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: _buildMenuGrid()),
                      VerticalDivider(width: 1, color: Colors.grey[200]),
                      const Expanded(flex: 1, child: CartViewContent()),
                    ],
                  );
                }
                return _buildMenuGrid();
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (MediaQuery.of(context).size.width > 900) return const SizedBox.shrink();
          return Consumer<CartProvider>(
            builder: (context, cart, child) {
              if (cart.items.isEmpty) return const SizedBox.shrink();
              return InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const CartBottomSheet(),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.primary,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
                          child: Text('${cart.totalItems}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        const Row(
                          children: [
                            Text('View Cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            SizedBox(width: 8),
                            Icon(Icons.shopping_cart_outlined, color: Colors.white)
                          ],
                        ),
                        Text('\$${cart.totalAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('menu_categories')
          .where('restaurantId', isEqualTo: restaurantId)
          .orderBy('order').snapshots(),
      builder: (context, snapshot) {
        final List<String> categories = ['All', 'Starters', 'Mains', 'Desserts', 'Drinks'];
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
           categories.clear();
           categories.add('All');
           categories.addAll(snapshot.data!.docs.map((d) => (d.data() as Map)['name'].toString()));
        }

        return SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 10, bottom: 10),
                child: ChoiceChip(
                  label: Text(cat, style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.black87
                  )),
                  selected: isSelected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = cat);
                  },
                ),
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildMenuGrid() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final items = snapshot.data!.docs.map((d) => MenuItem.fromMap(d.id, d.data() as Map<String,dynamic>))
            .where((item) => _selectedCategory == 'All' || item.category == _selectedCategory).toList();
            
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
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildMenuItemCard(item);
              },
            );
          },
        );
      }
    );
  }

  Widget _buildMenuItemCard(MenuItem item) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: item.isAvailable ? () => _showQuantitySelector(item) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.grey[200],
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? Image.network(item.imageUrl!, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.fastfood, size: 48, color: Colors.grey))
                    : const Icon(Icons.fastfood, size: 48, color: Colors.grey),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('\$${item.price.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                        if (!item.isAvailable)
                          const Text('Out', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showQuantitySelector(MenuItem item) {
    int quantity = 1;
    String instructions = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 32),
                        onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
                      ),
                      const SizedBox(width: 16),
                      Text('$quantity', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 32),
                        onPressed: () => setState(() => quantity++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Special Instructions',
                      hintText: 'e.g. No onion',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) => instructions = val,
                  )
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    context.read<CartProvider>().addItem(item, quantity: quantity, instructions: instructions);
                    Navigator.pop(context);
                  }, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: const Text('Add to Cart', style: TextStyle(fontWeight: FontWeight.bold))
                ),
              ],
            );
          }
        );
      }
    );
  }
}
