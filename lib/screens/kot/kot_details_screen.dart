import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class KotDetailsScreen extends StatelessWidget {
  const KotDetailsScreen({
    super.key,
    required this.kotId,
  });

  final String kotId;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KOT Details'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: firestore.collection('kots').doc(kotId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unable to load KOT details: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists || snapshot.data!.data() == null) {
            return const Center(child: Text('KOT not found.'));
          }

          final data = snapshot.data!.data()!;
          final items = (data['items'] as List?) ?? [];
          final tableLabel = (data['tableName'] ?? data['tableId'] ?? 'N/A').toString();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TABLE ${tableLabel.toUpperCase()}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Order Items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No items in this KOT.'),
                    ),
                  )
                else
                  ...items.map((item) {
                    final name = (item['name'] ?? 'Item').toString();
                    final quantity = item['quantity'] ?? 0;
                    final specialInstructions = (item['specialInstructions'] ?? '').toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.35)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                          child: Text(
                            '$quantity',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: specialInstructions.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Note: $specialInstructions'),
                              )
                            : null,
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}
