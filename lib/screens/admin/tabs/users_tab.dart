import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../services/auth_service.dart';
import '../../../utils/order_status_utils.dart';

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

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Unable to load staff users: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final users = snapshot.data?.docs ?? [];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 720;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(context, isMobile, users.length),
                  const SizedBox(height: 16),
                  _buildOrphanedUsersAlert(context),
                  const SizedBox(height: 16),
                  if (isMobile)
                    _buildStaffMobileList(users, context)
                  else
                    _buildStaffDesktopTable(users, context),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOrphanedUsersAlert(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final orphanedUsers = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final role = (data['role'] ?? '').toString().trim().toLowerCase();
          final restaurantId = (data['restaurantId'] ?? '').toString().trim();
          return (role == 'kitchen' || role == 'chef') && restaurantId.isEmpty;
        }).toList();

        if (orphanedUsers.isEmpty) {
          return const SizedBox.shrink();
        }

        final preview = orphanedUsers
            .take(3)
            .map((doc) => ((doc.data() as Map<String, dynamic>)['email'] ?? doc.id).toString())
            .join(', ');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kitchen users without restaurant assignment detected',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${orphanedUsers.length} kitchen/chef user(s) are missing `restaurantId` and may fail to log in properly.',
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Examples: $preview',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, bool isMobile, int userCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF8C1026).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.people_outline, color: Color(0xFF8C1026), size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            '$userCount Users',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _openCreateUserDialog(context),
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: Text(isMobile ? 'Add User' : 'Create Staff Member'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffMobileList(List<QueryDocumentSnapshot> users, BuildContext context) {
    if (users.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
        final doc = users[index];
        final data = doc.data() as Map<String, dynamic>;
        final role = (data['role'] ?? 'waiter').toString();
        final status = (data['status'] ?? 'active').toString();
        final name = (data['name'] ?? 'N/A').toString();
        final email = (data['email'] ?? 'N/A').toString();
        final normalizedStatus = OrderStatusUtils.normalizeOrderStatusForRead(
          rawStatus: status,
          auth: context.read<AuthService>(),
        );

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openUserDetails(context, doc),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF8C1026).withValues(alpha: 0.10),
                          child: Text(
                            name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Color(0xFF8C1026), fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildStatusChip(status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(email, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildRoleChip(role),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF8C1026)),
                              onPressed: () => _openUserDetails(context, doc),
                              tooltip: 'View Details',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                            ),
                            IconButton(
                              icon: const Icon(Icons.mail_outline, size: 20, color: Colors.blue),
                              onPressed: status == 'deleted' ? null : () => _sendResetEmail(context, email),
                              tooltip: 'Reset Password',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                            ),
                            IconButton(
                              icon: Icon(
                                normalizedStatus == 'active' ? Icons.block : Icons.check_circle_outline,
                                size: 20,
                                color: normalizedStatus == 'active' ? Colors.red : Colors.green,
                              ),
                              onPressed: status == 'deleted'
                                  ? null
                                  : () => _toggleUserStatus(context, doc.id, normalizedStatus == 'active'),
                              tooltip: normalizedStatus == 'active' ? 'Disable User' : 'Enable User',
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaffDesktopTable(List<QueryDocumentSnapshot> users, BuildContext context) {
    if (users.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 48),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
              horizontalMargin: 20,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: users.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final role = (data['role'] ?? 'waiter').toString();
                final status = (data['status'] ?? 'active').toString();
                final normalizedStatus = OrderStatusUtils.normalizeOrderStatusForRead(
                  rawStatus: status,
                  auth: context.read<AuthService>(),
                );
                final name = (data['name'] ?? 'N/A').toString();
                final email = (data['email'] ?? 'N/A').toString();
                final phone = (data['phone'] ?? '-').toString();

                return DataRow(
                  onSelectChanged: (_) => _openUserDetails(context, doc),
                  cells: [
                    DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(email, style: TextStyle(color: Colors.grey.shade600))),
                    DataCell(Text(phone, style: TextStyle(color: Colors.grey.shade700))),
                    DataCell(_buildRoleChip(role)),
                    DataCell(_buildStatusChip(normalizedStatus)),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF8C1026)),
                          onPressed: () => _openUserDetails(context, doc),
                          tooltip: 'View Details',
                        ),
                        IconButton(
                          icon: const Icon(Icons.mail_outline, size: 20, color: Colors.blue),
                          onPressed: normalizedStatus == 'deleted' ? null : () => _sendResetEmail(context, email),
                          tooltip: 'Reset Password',
                        ),
                        IconButton(
                          icon: Icon(
                            normalizedStatus == 'active' ? Icons.block : Icons.check_circle_outline,
                            size: 20,
                            color: normalizedStatus == 'active' ? Colors.red : Colors.green,
                          ),
                          onPressed: normalizedStatus == 'deleted'
                              ? null
                              : () => _toggleUserStatus(context, doc.id, normalizedStatus == 'active'),
                          tooltip: normalizedStatus == 'active' ? 'Disable User' : 'Enable User',
                        ),
                      ],
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        children: [
          Icon(Icons.group_off_outlined, size: 36, color: Colors.grey),
          SizedBox(height: 10),
          Text('No staff users found.', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRoleChip(String role) {
    Color color = Colors.blue;
    if (role == 'admin') color = Colors.purple;
    if (role == 'cashier') color = Colors.orange;
    if (role == 'kitchen') color = Colors.teal;

    String displayRole;
    if (role == 'admin') {
      displayRole = 'Admin';
    } else if (role == 'cashier') {
      displayRole = 'Cashier';
    } else if (role == 'waiter') {
      displayRole = 'Waiter';
    } else if (role == 'kitchen') {
      displayRole = 'Kitchen';
    } else {
      displayRole = role;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        displayRole.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final normalized = status.toLowerCase();
    final active = normalized == 'active';
    final deleted = normalized == 'deleted';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: deleted
            ? Colors.grey.shade200
            : (active ? Colors.green.shade50 : Colors.red.shade50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        deleted ? 'DELETED' : (active ? 'ACTIVE' : 'DISABLED'),
        style: TextStyle(
          color: deleted ? Colors.grey.shade700 : (active ? Colors.green : Colors.red),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _openCreateUserDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const AddOrEditUserDialog());
  }

  void _openEditUserDialog(BuildContext context, String userId, Map<String, dynamic> userData) {
    showDialog(
      context: context,
      builder: (_) => AddOrEditUserDialog(
        userId: userId,
        initialData: userData,
      ),
    );
  }

  void _openUserDetails(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailsScreen(
          userId: doc.id,
          userData: data,
          onEdit: () => _openEditUserDialog(context, doc.id, data),
          onDelete: () => _deleteUser(context, doc.id),
        ),
      ),
    );
  }

  Future<void> _deleteUser(BuildContext context, String uid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text('This will mark user as deleted and block login. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await context.read<AuthService>().adminSoftDeleteStaffUser(uid: uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted successfully.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _toggleUserStatus(BuildContext context, String uid, bool currentActive) async {
    try {
      await context.read<AuthService>().updateStaffStatus(uid, !currentActive);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
      );
    }
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
      const SnackBar(content: Text('Reset email sent! Please ask user to check spam folder too.')),
    );
  }
}

class UserDetailsScreen extends StatelessWidget {
  const UserDetailsScreen({
    super.key,
    required this.userId,
    required this.userData,
    required this.onEdit,
    required this.onDelete,
  });

  final String userId;
  final Map<String, dynamic> userData;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = (userData['name'] ?? 'N/A').toString();
    final email = (userData['email'] ?? 'N/A').toString();
    final phone = (userData['phone'] ?? '-').toString();
    final role = (userData['role'] ?? 'waiter').toString();
    final status = (userData['status'] ?? 'active').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('User Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Name', name),
                  _infoRow('Email', email),
                  _infoRow('Phone', phone),
                  _infoRow('Role', role.toUpperCase()),
                  _infoRow('Status', status.toUpperCase()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit User'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete User'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class AddOrEditUserDialog extends StatefulWidget {
  const AddOrEditUserDialog({
    super.key,
    this.userId,
    this.initialData,
  });

  final String? userId;
  final Map<String, dynamic>? initialData;

  bool get isEdit => userId != null;

  @override
  State<AddOrEditUserDialog> createState() => _AddOrEditUserDialogState();
}

class _AddOrEditUserDialogState extends State<AddOrEditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _selectedRole = 'waiter';
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _nameCtrl.text = (widget.initialData?['name'] ?? '').toString();
      _emailCtrl.text = (widget.initialData?['email'] ?? '').toString();
      _phoneCtrl.text = (widget.initialData?['phone'] ?? '').toString();
      _selectedRole = (widget.initialData?['role'] ?? 'waiter').toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter full name.';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter email address.';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return 'Please enter valid email format.';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter phone number.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (widget.isEdit) return null;
    if (value == null || value.trim().isEmpty) return 'Please enter password.';
    if (value.trim().length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix highlighted fields.')),
      );
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    if (auth.restaurantId == null || auth.restaurantId!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot create user: admin has no restaurant context.')), 
      );
      return;
    }

    try {
      if (widget.isEdit) {
        await auth.adminUpdateStaffUser(
          uid: widget.userId!,
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          role: _selectedRole,
        );
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User updated successfully.'), backgroundColor: Colors.green),
        );
      } else {
        final error = await auth.adminCreateUser(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          role: _selectedRole,
          phone: _phoneCtrl.text.trim(),
        );

        if (!mounted) return;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        } else {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Staff user created successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF8C1026).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.isEdit ? Icons.edit_outlined : Icons.person_add_alt_1,
              color: const Color(0xFF8C1026),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isEdit ? 'Edit Staff Member' : 'Create New Staff Member',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                validator: _validateName,
                decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
              ),
              TextFormField(
                controller: _emailCtrl,
                validator: _validateEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              ),
              TextFormField(
                controller: _phoneCtrl,
                validator: _validatePhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              if (!widget.isEdit)
                TextFormField(
                  controller: _passCtrl,
                  validator: _validatePassword,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Assign Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                items: ['waiter', 'cashier', 'kitchen', 'admin'].map((r) {
                  final label = r == 'waiter'
                      ? 'Waiter'
                      : r == 'cashier'
                          ? 'Cashier'
                          : r == 'kitchen'
                              ? 'Kitchen'
                              : 'Admin';
                  return DropdownMenuItem(value: r, child: Text(label));
                }).toList(),
                onChanged: (v) => setState(() => _selectedRole = v ?? 'waiter'),
                decoration: const InputDecoration(labelText: 'Assign Role', prefixIcon: Icon(Icons.badge_outlined)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(
          onPressed: _loading ? null : _save,
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_loading ? 'Saving...' : (widget.isEdit ? 'Save Changes' : 'Create User')),
        ),
      ],
    );
  }
}
