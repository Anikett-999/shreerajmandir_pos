import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/staff_seed_service.dart';

class UsersTab extends StatelessWidget {
  const UsersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final restaurantId = context.read<AuthService>().restaurantId;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final users = snapshot.data?.docs ?? [];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row / Column
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Staff Management", 
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddUserDialog(context),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text("Create Staff Member"),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _seedDefaultUsers(context),
                            icon: const Icon(Icons.bolt, size: 18),
                            label: const Text("Seed Test Users"),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Staff Management", 
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _seedDefaultUsers(context),
                              icon: const Icon(Icons.bolt, size: 18),
                              label: const Text("Seed Test Users"),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () => _showAddUserDialog(context),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text("Create Staff Member"),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 32),
                  
                  _buildSectionHeader("Active Staff Members", Icons.people, Colors.blue),
                  const SizedBox(height: 16),

                  // Responsive List Layout
                  if (isMobile)
                    _buildStaffMobileList(users, context)
                  else
                    _buildStaffDesktopTable(users, context),
                  
                  const SizedBox(height: 40),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildStaffMobileList(List<QueryDocumentSnapshot> users, BuildContext context) {
    if (users.isEmpty) return const Center(child: Text("No staff members found."));

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final data = users[index].data() as Map<String, dynamic>;
        final role = data['role'] ?? 'waiter';
        final status = data['status'] ?? 'active';
        final name = data['name'] ?? 'N/A';
        final email = data['email'] ?? 'N/A';
        final uid = users[index].id;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    _buildStatusChip(status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildRoleChip(role.toString()),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.mail_outline, size: 20, color: Colors.blue),
                          onPressed: () => _sendResetEmail(context, email),
                          tooltip: "Reset Password",
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: Icon(
                            status == 'active' ? Icons.block : Icons.check_circle_outline, 
                            size: 20, 
                            color: status == 'active' ? Colors.red : Colors.green
                          ),
                          onPressed: () => _toggleUserStatus(context, uid, status == 'active'),
                          tooltip: status == 'active' ? "Disable User" : "Enable User",
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaffDesktopTable(List<QueryDocumentSnapshot> users, BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 48),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey[50]),
              horizontalMargin: 20,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: users.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final role = data['role'] ?? 'waiter';
                final status = data['status'] ?? 'active';
                final name = data['name'] ?? 'N/A';
                final email = data['email'] ?? 'N/A';
                final uid = doc.id;

                return DataRow(cells: [
                  DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(email, style: TextStyle(color: Colors.grey[600]))),
                  DataCell(_buildRoleChip(role.toString())),
                  DataCell(_buildStatusChip(status)),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.mail_outline, size: 20, color: Colors.blue),
                        onPressed: () => _sendResetEmail(context, email),
                        tooltip: "Reset Password",
                      ),
                      IconButton(
                        icon: Icon(
                          status == 'active' ? Icons.block : Icons.check_circle_outline, 
                          size: 20, 
                          color: status == 'active' ? Colors.red : Colors.green
                        ),
                        onPressed: () => _toggleUserStatus(context, uid, status == 'active'),
                        tooltip: status == 'active' ? "Disable User" : "Enable User",
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: color.withOpacity(0.2), thickness: 1)),
      ],
    );
  }

  Widget _buildRoleChip(String role) {
    Color color = Colors.blue;
    if (role == 'admin') color = Colors.purple;
    if (role == 'cashier') color = Colors.orange;

    String displayRole;
    if (role == 'admin') {
      displayRole = 'Admin';
    } else if (role == 'cashier') {
      displayRole = 'Cashier';
    } else if (role == 'waiter') {
      displayRole = 'Waiter';
    } else {
      displayRole = role;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(displayRole.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusChip(String status) {
    bool active = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: active ? Colors.green[50] : Colors.red[50], borderRadius: BorderRadius.circular(20)),
      child: Text(active ? "ACTIVE" : "DISABLED", style: TextStyle(color: active ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _showAddUserDialog(BuildContext context) {
     showDialog(context: context, builder: (_) => const AddUserDialog());
  }

  void _toggleUserStatus(BuildContext context, String uid, bool curActive) async {
    await context.read<AuthService>().updateStaffStatus(uid, !curActive);
  }

  void _sendResetEmail(BuildContext context, String email) async {
    final error = await context.read<AuthService>().sendResetEmail(email);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Reset email sent! Please ask user to check spam folder too.")),
    );
  }

  Future<void> _seedDefaultUsers(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Seeding test users...'),
          ],
        ),
      ),
    );

    final auth = context.read<AuthService>();
    final result = await StaffSeedService().seedDefaultUsers(auth);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final summary = 'Seed complete: created ${result.created}, skipped ${result.skipped}, failed ${result.failed}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary),
        backgroundColor: result.failed > 0 ? Colors.orange : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );

    if (result.errors.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Seed Errors'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Text(result.errors.join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

class AddUserDialog extends StatefulWidget {
  const AddUserDialog({super.key});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _selectedRole = 'waiter';
  bool _loading = false;

  void _create() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final error = await context.read<AuthService>().adminCreateUser(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      role: _selectedRole,
      phone: _phoneCtrl.text.trim(),
      pin: _pinCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _loading = false);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Staff user created successfully!"), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create New Staff Member"),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Full Name")),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "Email")),
            TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: "Assign Password"), obscureText: true),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "Phone (Optional)")),
            TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: "Login PIN (4 digits)"), maxLength: 4, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              items: ['waiter', 'cashier', 'admin'].map((r) {
                final label = r == 'waiter' ? 'Waiter' : r == 'cashier' ? 'Cashier' : 'Admin';
                return DropdownMenuItem(value: r, child: Text(label));
              }).toList(),
              onChanged: (v) => setState(() => _selectedRole = v!),
              decoration: const InputDecoration(labelText: "Assign Role"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(onPressed: _loading ? null : _create, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Create User")),
      ],
    );
  }
}
