import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/admin_menu_provider.dart';
import '../../../services/auth_service.dart';

class MenuTab extends StatefulWidget {
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  final AdminMenuProvider _menuProvider = AdminMenuProvider();

  static const Color _brandMaroon = Color(0xFF8C1026);
  static const Color _brandGreen = Color(0xFF2E7D32);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final restaurantId = context.read<AuthService>().restaurantId;
    _menuProvider.initialize(restaurantId);
  }

  @override
  void dispose() {
    _menuProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _menuProvider,
      child: Container(
        color: const Color(0xFFF9F7F5),
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _brandMaroon.withOpacity(0.12)),
                ),
                child: TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: _brandMaroon,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: _brandMaroon,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Categories', icon: Icon(Icons.category, size: 20)),
                    Tab(text: 'Menu Items', icon: Icon(Icons.restaurant_menu, size: 20)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Consumer<AdminMenuProvider>(
                builder: (context, provider, _) {
                  if (provider.isInitializing) {
                    return const Expanded(child: Center(child: CircularProgressIndicator()));
                  }

                  if (provider.errorMessage != null) {
                    return Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Error: ${provider.errorMessage}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    );
                  }

                  return Expanded(
                    child: TabBarView(
                      children: [
                        _buildCategoriesView(),
                        _buildItemsView(),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesView() {
    return Consumer<AdminMenuProvider>(
      builder: (context, provider, _) {
        final categories = provider.categories;
        return Column(
          children: [
            _buildHeader(
              title: '',
              buttonLabel: 'New Category',
              isBusy: provider.isBusy,
              onPressed: () => _showCategoryDialog(),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text('No categories yet. Add one to get started!'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final doc = categories[index];
                        final data = doc.data();
                        final id = doc.id;
                        final visible = data['isVisible'] ?? true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _brandMaroon.withOpacity(0.10)),
                            boxShadow: [
                              BoxShadow(
                                color: _brandMaroon.withOpacity(0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _brandMaroon.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${data['order'] ?? 0}',
                                      style: const TextStyle(
                                        color: _brandMaroon,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['name'] ?? 'N/A',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (visible ? _brandGreen : Colors.red).withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          visible ? 'VISIBLE' : 'HIDDEN',
                                          style: TextStyle(
                                            color: visible ? _brandGreen : Colors.red,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: _brandMaroon, size: 22),
                                  onPressed: provider.isBusy
                                      ? null
                                      : () => _showCategoryDialog(id: id, initialData: data),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                                  onPressed: provider.isBusy
                                      ? null
                                      : () => _deleteCategory(id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemsView() {
    return Consumer<AdminMenuProvider>(
      builder: (context, provider, _) {
        final items = provider.items;
        return Column(
          children: [
            _buildHeader(
              title: '',
              buttonLabel: 'Add Item',
              isBusy: provider.isBusy,
              onPressed: () => _openItemEditPage(context),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxis = width >= 1400
                      ? 5
                      : width >= 1100
                          ? 4
                          : width >= 700
                              ? 3
                              : 2;

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxis,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final doc = items[index];
                      final data = doc.data();
                        final available = data['isAvailable'] is bool
                          ? data['isAvailable'] as bool
                          : ((data['isAvailable']?.toString().toLowerCase() ?? 'true') == 'true');

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openItemDetailsPage(itemId: doc.id),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _brandMaroon.withOpacity(0.12)),
                            boxShadow: [
                              BoxShadow(
                                color: _brandMaroon.withOpacity(0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (data['imageUrl'] != null)
                                        Image.network(data['imageUrl'], fit: BoxFit.cover)
                                      else
                                        Container(
                                          color: _brandMaroon.withOpacity(0.07),
                                          child: Icon(Icons.restaurant_menu, color: _brandMaroon.withOpacity(0.35), size: 44),
                                        ),
                                      if (!available)
                                        Container(
                                          color: Colors.black45,
                                          child: const Center(
                                            child: Text(
                                              'UNAVAILABLE',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _brandMaroon,
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          child: Text(
                                            '₹${data['price'] ?? 0}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          data['name'] ?? 'N/A',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          data['category'] ?? 'General',
                                          style: const TextStyle(color: _brandGreen, fontSize: 10, fontWeight: FontWeight.w700),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const Text(
                                          'Tap to view details',
                                          style: TextStyle(fontSize: 10, color: Colors.black54),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildHeader({
    required String title,
    required String buttonLabel,
    required bool isBusy,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: _brandMaroon),
            )
          else
            const SizedBox.shrink(),
          ElevatedButton.icon(
            onPressed: isBusy ? null : onPressed,
            icon: const Icon(Icons.add, size: 18),
            label: Text(buttonLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandMaroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(String id) async {
    final provider = context.read<AdminMenuProvider>();
    try {
      await provider.deleteCategory(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete category: $error')));
    }
  }

  void _showCategoryDialog({String? id, Map<String, dynamic>? initialData}) {
    final nameCtrl = TextEditingController(text: initialData?['name']);
    final orderCtrl = TextEditingController(text: initialData?['order']?.toString() ?? '1');
    bool isVisible = initialData?['isVisible'] ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(id == null ? 'Add Category' : 'Edit Category'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _formField(controller: nameCtrl, label: 'Category Name', icon: Icons.category_outlined),
                  const SizedBox(height: 12),
                  _formField(
                    controller: orderCtrl,
                    label: 'Sort Order',
                    icon: Icons.sort,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _brandMaroon.withOpacity(0.05),
                      border: Border.all(color: _brandMaroon.withOpacity(0.20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.image_outlined, color: _brandMaroon),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Category image upload (Coming soon)', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        OutlinedButton(onPressed: null, child: const Text('Upload')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _brandGreen.withOpacity(0.08),
                    ),
                    child: SwitchListTile(
                      title: const Text('Visible', style: TextStyle(fontWeight: FontWeight.w700)),
                      value: isVisible,
                      activeColor: _brandGreen,
                      onChanged: (v) => setDialogState(() => isVisible = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _brandMaroon, foregroundColor: Colors.white),
              onPressed: () async {
                final provider = context.read<AdminMenuProvider>();
                try {
                  await provider.addOrUpdateCategory(
                    id: id,
                    name: nameCtrl.text.trim(),
                    order: int.tryParse(orderCtrl.text) ?? 1,
                    isVisible: isVisible,
                    imageUrl: initialData?['imageUrl'],
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(id == null ? 'Category created' : 'Category updated')),
                    );
                  }
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save category: $error')),
                  );
                }
              },
              child: const Text('Save Category'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openItemEditPage(
    BuildContext sourceContext, {
    String? id,
    Map<String, dynamic>? initialData,
  }) async {
    final scopedProvider = sourceContext.read<AdminMenuProvider>();
    await Navigator.push(
      sourceContext,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<AdminMenuProvider>.value(
          value: scopedProvider,
          child: MenuItemEditPage(id: id, initialData: initialData),
        ),
      ),
    );
  }

  void _openItemDetailsPage({required String itemId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<AdminMenuProvider>.value(
          value: _menuProvider,
          child: MenuItemDetailsPage(itemId: itemId),
        ),
      ),
    );
  }
}

class MenuItemDetailsPage extends StatelessWidget {
  const MenuItemDetailsPage({super.key, required this.itemId});

  final String itemId;

  static const Color _brandMaroon = Color(0xFF8C1026);
  static const Color _brandGreen = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F5),
      appBar: AppBar(
        title: const Text('Menu Item Details'),
        backgroundColor: _brandMaroon,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AdminMenuProvider>(
        builder: (context, menuProvider, _) {
          final match = menuProvider.items.where((doc) => doc.id == itemId);
          if (match.isEmpty) {
            return const Center(child: Text('Item not found.'));
          }
          final doc = match.first;
          final data = doc.data();
            final isAvailable = data['isAvailable'] is bool
              ? data['isAvailable'] as bool
              : ((data['isAvailable']?.toString().toLowerCase() ?? 'true') == 'true');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _brandMaroon.withOpacity(0.14)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: double.infinity,
                            height: 250,
                            child: data['imageUrl'] != null
                                ? Image.network(data['imageUrl'], fit: BoxFit.cover)
                                : Container(
                                    color: _brandMaroon.withOpacity(0.08),
                                    child: Icon(Icons.restaurant_menu, color: _brandMaroon.withOpacity(0.35), size: 72),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          data['name'] ?? 'N/A',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Category: ${data['category'] ?? 'General'}',
                          style: const TextStyle(color: _brandGreen, fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Price: ₹${data['price'] ?? 0}',
                          style: const TextStyle(color: _brandMaroon, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          data['description']?.toString().trim().isNotEmpty == true
                              ? data['description']
                              : 'No description available.',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Visible / Available', style: TextStyle(fontWeight: FontWeight.w700)),
                          activeColor: _brandGreen,
                          value: isAvailable,
                          onChanged: menuProvider.isBusy
                              ? null
                              : (v) async {
                                  if (v == null) return;
                                  try {
                                    await menuProvider.toggleItemAvailability(itemId, v);
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to update visibility: $error')),
                                    );
                                  }
                                },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                final scopedProvider = context.read<AdminMenuProvider>();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChangeNotifierProvider<AdminMenuProvider>.value(
                                      value: scopedProvider,
                                      child: MenuItemEditPage(id: itemId, initialData: data),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: menuProvider.isBusy
                                  ? null
                                  : () async {
                                      try {
                                        await menuProvider.deleteItem(itemId);
                                        if (context.mounted) Navigator.pop(context);
                                      } catch (error) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to delete item: $error')),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MenuItemEditPage extends StatefulWidget {
  const MenuItemEditPage({super.key, this.id, this.initialData});

  final String? id;
  final Map<String, dynamic>? initialData;

  @override
  State<MenuItemEditPage> createState() => _MenuItemEditPageState();
}

class _MenuItemEditPageState extends State<MenuItemEditPage> {
  late TextEditingController nameCtrl;
  late TextEditingController priceCtrl;
  late TextEditingController descCtrl;
  String? selectedCategory;
  String? imageUrl;
  bool isAvailable = true;

  static const Color _brandMaroon = Color(0xFF8C1026);
  static const Color _brandGreen = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialData?['name']);
    priceCtrl = TextEditingController(text: widget.initialData?['price']?.toString());
    descCtrl = TextEditingController(text: widget.initialData?['description']);
    selectedCategory = widget.initialData?['category'];
    imageUrl = widget.initialData?['imageUrl'];
    isAvailable = widget.initialData?['isAvailable'] ?? true;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<AdminMenuProvider>();
    try {
      await provider.addOrUpdateItem(
        id: widget.id,
        name: nameCtrl.text.trim(),
        price: double.tryParse(priceCtrl.text) ?? 0.0,
        description: descCtrl.text.trim(),
        category: selectedCategory,
        isAvailable: isAvailable,
        imageUrl: imageUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.id == null ? 'Item created' : 'Item updated')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save item: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F5),
      appBar: AppBar(
        title: Text(widget.id == null ? 'Add Menu Item' : 'Edit Menu Item'),
        backgroundColor: _brandMaroon,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AdminMenuProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _brandMaroon.withOpacity(0.20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _brandMaroon.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _brandMaroon.withOpacity(0.20)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.image_outlined, color: _brandMaroon),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Item image upload (Coming soon)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            OutlinedButton(onPressed: null, child: const Text('Upload')),
                          ],
                        ),
                      ),
                      if (imageUrl != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(imageUrl!, height: 120, fit: BoxFit.cover),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Item Name',
                          prefixIcon: Icon(Icons.fastfood_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price (INR)',
                          prefixIcon: Icon(Icons.currency_rupee),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: provider.categories.any((d) => d.data()['name'] == selectedCategory)
                            ? selectedCategory
                            : null,
                        hint: const Text('Select Category'),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: provider.categories
                            .map((d) => DropdownMenuItem(
                                  value: d.data()['name'].toString(),
                                  child: Text(d.data()['name']),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => selectedCategory = v),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _brandGreen.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SwitchListTile(
                          title: const Text('Available', style: TextStyle(fontWeight: FontWeight.w700)),
                          value: isAvailable,
                          activeColor: _brandGreen,
                          onChanged: (v) => setState(() => isAvailable = v),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: provider.isBusy ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandMaroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.save_outlined),
                          label: Text(widget.id == null ? 'Create Item' : 'Update Item'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Widget _formField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  TextInputType? keyboardType,
}) {
  return TextField(
    controller: controller,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF800000), width: 1.5),
      ),
    ),
  );
}
