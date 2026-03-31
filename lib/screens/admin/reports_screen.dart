import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/report_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    const maroon = Color(0xFF6B1620); // Even darker, shiny maroon
    const maroonGradient = LinearGradient(
      colors: [Color(0xFF922224), Color(0xFF6B1620)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF922224),
        title: const Text(
          'Reports',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 48, bottom: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF922224), Color(0xFF6B1620)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.account_circle,
                          size: 70,
                          color: Color(0xFF922224),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 1.1,
                        shadows: [
                          Shadow(
                            color: Colors.black38,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ... Add more drawer items here as needed ...
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: const [],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Text(
            'Generate Business Reports',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a period to create a structured PDF with summary, insights, and performance breakdown.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                ),
          ),
          const SizedBox(height: 18),
          _buildReportTile(
            icon: Icons.calendar_today_outlined,
            title: 'Daily Report',
            subtitle: 'Pick a date and generate day-wise business report',
            onTap: _isGenerating ? null : _onDailyPressed,
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            icon: Icons.date_range_outlined,
            title: 'Monthly Report',
            subtitle: 'Pick month and year with weekly trend breakdown',
            onTap: _isGenerating ? null : _onMonthlyPressed,
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            icon: Icons.event_note_outlined,
            title: 'Yearly Report',
            subtitle: 'Pick a year with month-over-month summary',
            onTap: _isGenerating ? null : _onYearlyPressed,
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(minHeight: 5),
            const SizedBox(height: 8),
            Text(
              'Preparing report...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.grey.shade800, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDailyPressed() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000, 1, 1),
      lastDate: now,
    );
    if (picked == null) return;

    final start = DateTime(picked.year, picked.month, picked.day);
    final end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    final label = 'Date: ${DateFormat('dd MMM yyyy').format(start)}';

    await _generateReport(
      title: 'Daily Business Report',
      periodLabel: label,
      start: start,
      end: end,
      granularity: ReportGranularity.daily,
    );
  }

  Future<void> _onMonthlyPressed() async {
    final now = DateTime.now();
    int selectedYear = now.year;
    int selectedMonth = now.month;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Month & Year'),
              content: Row(
                children: [
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: selectedMonth,
                      items: List.generate(12, (i) => i + 1)
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(DateFormat('MMMM').format(DateTime(2024, m))),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedMonth = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: selectedYear,
                        items: List.generate(now.year - 1999, (i) => now.year - i)
                          .map((y) => DropdownMenuItem(value: y, child: Text(y.toString())))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedYear = v);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate')),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final start = DateTime(selectedYear, selectedMonth, 1);
    final end = DateTime(selectedYear, selectedMonth + 1, 1).subtract(const Duration(seconds: 1));
    final label = 'Period: ${DateFormat('MMMM yyyy').format(start)}';

    await _generateReport(
      title: 'Monthly Business Report',
      periodLabel: label,
      start: start,
      end: end,
      granularity: ReportGranularity.monthly,
    );
  }

  Future<void> _onYearlyPressed() async {
    final now = DateTime.now();
    int selectedYear = now.year;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Year'),
              content: DropdownButton<int>(
                isExpanded: true,
                value: selectedYear,
                items: List.generate(now.year - 1999, (i) => now.year - i)
                    .map((y) => DropdownMenuItem(value: y, child: Text(y.toString())))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setDialogState(() => selectedYear = v);
                },
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate')),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final start = DateTime(selectedYear, 1, 1);
    final end = DateTime(selectedYear + 1, 1, 1).subtract(const Duration(seconds: 1));
    final label = 'Year: $selectedYear';

    await _generateReport(
      title: 'Yearly Business Report',
      periodLabel: label,
      start: start,
      end: end,
      granularity: ReportGranularity.yearly,
    );
  }

  Future<void> _generateReport({
    required String title,
    required String periodLabel,
    required DateTime start,
    required DateTime end,
    required ReportGranularity granularity,
  }) async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    final restaurantName = auth.restaurantName ?? 'ShreeRajmandir';

    if (restaurantId == null || restaurantId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant context is missing. Please login again.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      await ReportService.generateOperationalReport(
        title: title,
        periodLabel: periodLabel,
        start: start,
        end: end,
        restaurantId: restaurantId,
        granularity: granularity,
        restaurantName: restaurantName,
      );
    } catch (e, stackTrace) {
      debugPrint('Reports generation failed: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      String message = 'Unable to generate report. Please try again.';
      if (e is FirebaseException && e.code == 'failed-precondition') {
        message = 'Report indexes are still building. Please wait a few minutes and retry.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }
}
