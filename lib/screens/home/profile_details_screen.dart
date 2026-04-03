import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

class ProfileDetailsScreen extends StatelessWidget {
  const ProfileDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Details'),
        backgroundColor: const Color(0xFF8C0D20),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
        future: uid == null
            ? Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null)
            : FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profileData = snapshot.data?.data();
          final name = profileData?['name']?.toString() ?? auth.currentUser?.displayName ?? 'N/A';
          final email = profileData?['email']?.toString() ?? auth.currentUser?.email ?? 'Not available';
          final role = profileData?['role']?.toString() ?? auth.role.name;
          final restaurant = profileData?['restaurantName']?.toString() ?? auth.restaurantName ?? auth.restaurantId ?? 'N/A';
          final phone = profileData?['phone']?.toString() ?? 'Not provided';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 22),
                CircleAvatar(
                  radius: 46,
                  backgroundColor: const Color(0xFF8C0D20),
                  child: Text(
                    _initials(name),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),
                Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(email, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 4),
                Chip(
                  label: Text(role.toUpperCase()),
                  backgroundColor: Colors.grey[200],
                ),
                const SizedBox(height: 18),

                _InfoCard(
                  title: 'Profile',
                  icon: Icons.person_outline,
                  rows: [
                    _InfoRow(label: 'Name', value: name),
                    _InfoRow(label: 'Email', value: email),
                    _InfoRow(label: 'Role', value: role),
                    _InfoRow(label: 'Phone', value: phone),
                    _InfoRow(label: 'Restaurant', value: restaurant),
                  ],
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Logout'),
                            content: const Text('Are you sure you want to log out?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Logout'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirmed == true) {
                        context.read<AuthService>().logout();
                      }
                    },
                    child: const Text('LOGOUT'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _initials(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'SR';
    return normalized.substring(0, 1).toUpperCase();
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < rows.length; i++) ...[
              _InfoTile(row: rows[i]),
              if (i != rows.length - 1) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.row});

  final _InfoRow row;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            row.label,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            row.value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
