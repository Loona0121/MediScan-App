import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:csv/csv.dart';
import '../services/supabase_service.dart';
import '../services/session_service.dart';
import '../services/account_service.dart';
import '../widgets/web_shell.dart';
import '../utils/csv_downloader.dart';
import 'inventory.dart';
import 'package:flutter/foundation.dart';
import '../widgets/top_banner.dart';
import '../utils/app_palette.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _reportType = 'Overall';
  String _exportFormat = 'PDF';
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  bool _isGenerating = false;
  bool _allTime = true;

  // Header profile info (for the web header's avatar/name/role) — same
  // data Settings already loads, kept lightweight here since Reports
  // only needs it for display, not editing.
  String _headerDisplayName = '';
  String _headerRoleLabel = '';
  String? _headerPhotoUrl;

  // Pharmacy name used for report branding (PDF title + filenames).
  String _pharmacyName = '';

  @override
  void initState() {
    super.initState();
    _loadHeaderProfile();
  }

 Future<void> _loadHeaderProfile() async {
  try {
    final email = await SessionService.email ?? '';
    final fullName = await SessionService.fullName ?? '';
    final roleLabel = await SessionService.roleLabel ?? '';

    final roleOnly = roleLabel.contains('•')
        ? roleLabel.split('•').first.trim()
        : roleLabel.trim();

    String? photoUrl;
    if (email.isNotEmpty) {
      photoUrl = await AccountService.getPhotoUrl(email);
    }

    // Fetch the pharmacy name — defensive against null / empty / non-String.
    String pharmacy = 'MediScan';
    try {
      final fetched = await SupabaseService.fetchPharmacyName();
      if (fetched != null && fetched is String && fetched.trim().isNotEmpty) {
        pharmacy = fetched.trim();
      }
    } catch (_) {
      pharmacy = 'MediScan';
    }

    if (!mounted) return;
    setState(() {
      _headerDisplayName = fullName;
      _headerRoleLabel = roleOnly;
      _headerPhotoUrl = photoUrl;
      _pharmacyName = pharmacy;
    });
  } catch (e) {
    debugPrint('Reports header profile load failed: $e');
    if (!mounted) return;
    // Even on failure, guarantee _pharmacyName is a valid string so
    // _generatePdf never sees null.
    setState(() {
      if (_pharmacyName.isEmpty) _pharmacyName = 'MediScan';
    });
  }
}

  String get _headerInitials {
    final name = _headerDisplayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length < 2) return name.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static const _reportTypes = [
    {'label': 'Overall', 'icon': Icons.bar_chart_rounded},
    {'label': 'Safe', 'icon': Icons.verified_user_outlined},
    {'label': 'Expiring', 'icon': Icons.warning_amber_rounded},
    {'label': 'Expired', 'icon': Icons.error_outline},
  ];

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      switch (preset) {
        case 'All Time':
          _allTime = true;
          break;
        case 'Next 30 Days':
          _allTime = false;
          _fromDate = now;
          _toDate = now.add(const Duration(days: 30));
          break;
        case 'Next 90 Days':
          _allTime = false;
          _fromDate = now;
          _toDate = now.add(const Duration(days: 90));
          break;
        case 'This Year':
          _allTime = false;
          _fromDate = DateTime(now.year, 1, 1);
          _toDate = DateTime(now.year, 12, 31);
          break;
        case 'Custom':
          _allTime = false;
          break;
      }
    });
  }

  String get _activePreset {
    if (_allTime) return 'All Time';
    return 'Custom';
  }

  ExpiryStatus? _statusFilterFor(String reportType) {
    switch (reportType) {
      case 'Safe':
        return ExpiryStatus.safe;
      case 'Expiring':
        return ExpiryStatus.warning;
      case 'Expired':
        return ExpiryStatus.expired;
      default:
        return null;
    }
  }

  Future<List<MedicineItem>> _fetchFilteredItems() async {
    final data = await SupabaseService.fetchInventory();
    final items = data.map((e) => MedicineItem.fromMap(e)).toList();

    final statusFilter = _statusFilterFor(_reportType);

    return items.where((item) {
      if (statusFilter != null && item.status != statusFilter) return false;
      if (_allTime) return true;

      final parts = item.expiryDate.split('-');
      if (parts.length < 2) return true;
      final expiry = DateTime(int.parse(parts[0]), int.parse(parts[1]));

      return !expiry.isBefore(_fromDate) && !expiry.isAfter(_toDate);
    }).toList();
  }

  Future<void> _generateReport() async {
    setState(() => _isGenerating = true);
    try {
      final items = await _fetchFilteredItems();

      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items match this report range.')),
        );
        return;
      }

      if (_exportFormat == 'PDF') {
        await _generatePdf(items);
      } else {
        await _generateCsv(items);
      }

      if (!mounted) return;
     TopBanner.show(
  context,
  message: 'Report generated successfully!',
  width: 320,
  alignment: Alignment.topCenter,
);
    } catch (e) {
      debugPrint('Report generation error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // PDF GENERATION — branded, KPI summary, colored status pills,
  // category breakdown, page footer.
  // ─────────────────────────────────────────────────────────────────
  Future<void> _generatePdf(List<MedicineItem> items) async {
    final doc = pw.Document();
    final dateFmt = DateFormat('MMM d, yyyy');
    final generatedFmt = DateFormat('MMM d, yyyy - h:mm a');

  final rawName = (_pharmacyName.trim().isEmpty) ? 'MediScan' : _pharmacyName;
final safeName = rawName.replaceAll(' ', '_');

    // ── Compute summary stats ──
    final totalItems = items.length;
    final safeCount =
        items.where((i) => i.status == ExpiryStatus.safe).length;
    final warningCount =
        items.where((i) => i.status == ExpiryStatus.warning).length;
    final expiredCount =
        items.where((i) => i.status == ExpiryStatus.expired).length;

    final totalUnits =
        items.fold<int>(0, (sum, i) => sum + (i.quantity ?? 0));
    final unitsAtRisk = items
        .where((i) =>
            i.status == ExpiryStatus.warning ||
            i.status == ExpiryStatus.expired)
        .fold<int>(0, (sum, i) => sum + (i.quantity ?? 0));

    // ── Category breakdown ──
    final categoryTotals = <String, int>{};
    for (final item in items) {
      categoryTotals[item.category] =
          (categoryTotals[item.category] ?? 0) + (item.quantity ?? 0);
    }
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ── Palette ──
    const pdfBlue = PdfColor.fromInt(0xFF2563EB);
    const pdfBlueLight = PdfColor.fromInt(0xFFDBEAFE);
    const pdfSlate900 = PdfColor.fromInt(0xFF0F172A);
    const pdfSlate600 = PdfColor.fromInt(0xFF475569);
    const pdfSlate400 = PdfColor.fromInt(0xFF94A3B8);
    const pdfSlate100 = PdfColor.fromInt(0xFFF1F5F9);
    const pdfGreen = PdfColor.fromInt(0xFF15803D);
    const pdfGreenBg = PdfColor.fromInt(0xFFDCFCE7);
    const pdfAmber = PdfColor.fromInt(0xFFB45309);
    const pdfAmberBg = PdfColor.fromInt(0xFFFEF3C7);
    const pdfRed = PdfColor.fromInt(0xFFB91C1C);
    const pdfRedBg = PdfColor.fromInt(0xFFFEE2E2);

    PdfColor statusTextColor(ExpiryStatus s) => switch (s) {
          ExpiryStatus.safe => pdfGreen,
          ExpiryStatus.warning => pdfAmber,
          ExpiryStatus.expired => pdfRed,
        };

    PdfColor statusBgColor(ExpiryStatus s) => switch (s) {
          ExpiryStatus.safe => pdfGreenBg,
          ExpiryStatus.warning => pdfAmberBg,
          ExpiryStatus.expired => pdfRedBg,
        };

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 48),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: pdfSlate400, width: 0.4),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _pharmacyName,
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: pdfSlate600,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: pdfSlate600,
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          // ─────────────────────────────────────────────
          // HEADER BAND
          // ─────────────────────────────────────────────
          pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(
      _pharmacyName,
      style: pw.TextStyle(
        fontSize: 11,
        color: pdfBlue,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      'Inventory Report',
      style: pw.TextStyle(
        fontSize: 22,
        color: pdfSlate900,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  ],
),
          pw.SizedBox(height: 12),

          // ── Meta line ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Scope: ${_reportType == 'Overall' ? 'All items' : '$_reportType items'}',
                style: const pw.TextStyle(fontSize: 10, color: pdfSlate600),
              ),
              pw.Text(
                'Generated: ${generatedFmt.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: pdfSlate600),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _allTime
                ? 'Period: All Time'
                : 'Period: ${dateFmt.format(_fromDate)} — ${dateFmt.format(_toDate)}',
            style: const pw.TextStyle(fontSize: 10, color: pdfSlate600),
          ),
          pw.SizedBox(height: 16),

          // ─────────────────────────────────────────────
          // SUMMARY BAND
          // ─────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: pdfSlate400, width: 0.4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SUMMARY',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: pdfSlate600,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  children: [
                    _summaryCell('Total Items', '$totalItems', pdfSlate900),
                    pw.SizedBox(width: 10),
                    _summaryCell('Safe', '$safeCount', pdfGreen, pdfGreenBg),
                    pw.SizedBox(width: 10),
                    _summaryCell(
                        'Warning', '$warningCount', pdfAmber, pdfAmberBg),
                    pw.SizedBox(width: 10),
                    _summaryCell('Expired', '$expiredCount', pdfRed, pdfRedBg),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  children: [
                    _summaryCell('Total Stock', '$totalUnits', pdfSlate900),
                    pw.SizedBox(width: 10),
                    _summaryCell(
                        'Stock at Risk', '$unitsAtRisk', pdfRed, pdfRedBg),
                  ],
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────
          // MAIN TABLE
          // ─────────────────────────────────────────────
          pw.Text(
            'INVENTORY DETAIL',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: pdfSlate600,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: pdfSlate400, width: 0.4),
            columnWidths: {
              0: const pw.FlexColumnWidth(3.5), // Product
              1: const pw.FlexColumnWidth(2), // Category
              2: const pw.FlexColumnWidth(1.4), // Expiry
              3: const pw.FlexColumnWidth(1), // Units
              4: const pw.FlexColumnWidth(1.4), // Status
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: pdfBlueLight),
                children: [
                  _pdfHeaderCell('Product Name'),
                  _pdfHeaderCell('Category'),
                  _pdfHeaderCell('Expiry'),
                  _pdfHeaderCell('Stock', align: pw.TextAlign.right),
                  _pdfHeaderCell('Status', align: pw.TextAlign.center),
                ],
              ),
              // Data rows
              ...items.map(
                (item) => pw.TableRow(
                  children: [
                    _pdfCell(item.productName),
                    _pdfCell(item.category),
                    _pdfCell(item.formattedExpiry),
                    _pdfCell(
                      item.formattedQuantity,
                      align: pw.TextAlign.right,
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: pw.BoxDecoration(
                          color: statusBgColor(item.status),
                          borderRadius: pw.BorderRadius.circular(10),
                        ),
                        child: pw.Text(
                          item.status.name.toUpperCase(),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: statusTextColor(item.status),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Total row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: pdfSlate100),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      'TOTAL',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: pdfSlate900,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      '$totalItems items',
                      style:
                          const pw.TextStyle(fontSize: 9, color: pdfSlate600),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.SizedBox(),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      '$totalUnits',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: pdfSlate900,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.SizedBox(),
                  ),
                ],
              ),
            ],
          ),

          // ─────────────────────────────────────────────
          // CATEGORY BREAKDOWN
          // ─────────────────────────────────────────────
          if (sortedCategories.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'ITEMS BY CATEGORY',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: pdfSlate600,
                letterSpacing: 1.2,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: pdfSlate400, width: 0.4),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: pdfBlueLight),
                  children: [
                    _pdfHeaderCell('Category'),
                    _pdfHeaderCell('Stock', align: pw.TextAlign.right),
                    _pdfHeaderCell('Share', align: pw.TextAlign.right),
                  ],
                ),
                ...sortedCategories.map(
                  (entry) => pw.TableRow(
                    children: [
                      _pdfCell(entry.key),
                      _pdfCell(
                        '${entry.value}',
                        align: pw.TextAlign.right,
                      ),
                      _pdfCell(
                        totalUnits == 0
                            ? '0%'
                            : '${((entry.value / totalUnits) * 100).toStringAsFixed(1)}%',
                        align: pw.TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          pw.SizedBox(height: 20),
        ],
      ),
    );

    final pdfBytes = await doc.save();

    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '${safeName}_report.pdf',
      );
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/${safeName}_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(pdfBytes);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '${safeName}_report.pdf',
      );
    }
  }

  Future<void> _generateCsv(List<MedicineItem> items) async {
    final rows = <List<String>>[
      ['Product Name', 'Category', 'Expiry Date', 'Units', 'Status'],
      ...items.map((item) => [
            item.productName,
            item.category,
            item.formattedExpiry,
            item.formattedQuantity,
            item.status.name.toUpperCase(),
          ]),
    ];

    final csvData = const ListToCsvConverter().convert(rows);
    final rawName = (_pharmacyName.trim().isEmpty) ? 'MediScan' : _pharmacyName;
final safeName = rawName.replaceAll(' ', '_');
    final filename =
        '${safeName}_report_${DateTime.now().millisecondsSinceEpoch}.csv';

    // Await so any error from the downloader (e.g. share sheet failure)
    // bubbles up to _generateReport's catch block instead of silently
    // showing a false "success" banner.
    await downloadCsv(csvData, filename);
  }

  // ─────────────────────────────────────────────────────────────────
  // PDF cell helpers
  // ─────────────────────────────────────────────────────────────────
  static pw.Widget _pdfHeaderCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
            color: const PdfColor.fromInt(0xFF0F172A),
          ),
        ),
      );

  static pw.Widget _pdfCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          text,
          textAlign: align,
          style: const pw.TextStyle(fontSize: 9),
        ),
      );

  // KPI tile used inside the summary band. When `bgColor` is provided,
  // the tile gets a tinted background + colored border to reinforce the
  // status it represents.
  static pw.Widget _summaryCell(
  String label,
  String value,
  PdfColor valueColor, [
  PdfColor? bgColor,
]) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: pw.BoxDecoration(
        // No fill — just a thin outline so the layout keeps its shape.
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFFCBD5E1),
          width: 0.4,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColor.fromInt(0xFF475569),
              letterSpacing: 0.6,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    ),
  );
}

  // ─────────────────────────────────────────────────────────────────
  // Report type tile
  // ─────────────────────────────────────────────────────────────────
  Widget _typeCard(String label, IconData icon, AppPalette p, {double? width}) {
    final selected = _reportType == label;

    return GestureDetector(
      onTap: () => setState(() => _reportType = label),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? kPrimaryBlue.withValues(alpha: p.isDark ? 0.18 : 0.08)
              : p.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kPrimaryBlue : p.cardBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 22,
                    color: selected ? kPrimaryBlue : p.textSecondary),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? kPrimaryBlue : p.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: kPrimaryBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Export format card
  // ─────────────────────────────────────────────────────────────────
  Widget _formatCard(String label, IconData icon, AppPalette p,
      {double? width}) {
    final selected = _exportFormat == label;

    return GestureDetector(
      onTap: () => setState(() => _exportFormat = label),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: selected
              ? kPrimaryBlue.withValues(alpha: p.isDark ? 0.18 : 0.08)
              : (p.isDark ? p.searchBg : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kPrimaryBlue : p.cardBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? kPrimaryBlue : p.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? kPrimaryBlue : p.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Date field
  // ─────────────────────────────────────────────────────────────────
  Widget _dateField(String label, DateTime date,
      {required bool isFrom, required AppPalette p}) {
    return GestureDetector(
      onTap: () => _pickDate(isFrom: isFrom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: p.searchBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: p.textSecondary),
            const SizedBox(width: 10),
            Text(
              DateFormat('MMM d, yyyy').format(date),
              style: TextStyle(fontSize: 14, color: p.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Preset chip
  // ─────────────────────────────────────────────────────────────────
  Widget _presetChip(String label, AppPalette p) {
    final selected = _activePreset == label;

    return GestureDetector(
      onTap: () => _applyPreset(label),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 14 : 16,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? kPrimaryBlue
              : (p.isDark ? p.searchBg : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kPrimaryBlue : p.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : p.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Section header
  // ─────────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;

    if (isWeb) {
      return _buildWebLayout(context);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Inventory Report',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generate Report',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure your clinical analytics',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),

            _sectionLabel('Report Type', p),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 92,
              ),
              children: _reportTypes
                  .map((t) => _typeCard(
                        t['label'] as String,
                        t['icon'] as IconData,
                        p,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),

            _sectionLabel('Export Format', p),
            Row(
              children: [
                Expanded(
                  child: _formatCard('PDF', Icons.picture_as_pdf_outlined, p),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _formatCard('CSV', Icons.table_chart_outlined, p),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionLabel('Reporting Period', p),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'All Time',
                'Next 30 Days',
                'Next 90 Days',
                'This Year',
                'Custom'
              ].map((preset) => _presetChip(preset, p)).toList(),
            ),
            if (!_allTime) ...[
              const SizedBox(height: 16),
              Text('FROM DATE',
                  style: TextStyle(
                      fontSize: 11,
                      color: kPrimaryBlue,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _dateField('From', _fromDate, isFrom: true, p: p),
              const SizedBox(height: 14),
              Text('TO DATE',
                  style: TextStyle(
                      fontSize: 11,
                      color: kPrimaryBlue,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _dateField('To', _toDate, isFrom: false, p: p),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'Includes all items regardless of expiry date.',
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateReport,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _isGenerating ? 'Generating...' : 'Download Report',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Web layout
  // ─────────────────────────────────────────────────────────────────
    Widget _buildWebLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    const double typeCardWidth = 150;
    const double formatCardWidth = 180;
    const double sectionGap = 28;

    // WebShell's narrow top bar has no bottom spacing before the page
    // content, so add a gap here to match the wide layout's headerBar
    // breathing room — same pattern used on Inventory.
    final isNarrowShell = MediaQuery.of(context).size.width < 1024;

    return WebShell(
      activeRoute: 'reports',
      headerBar: WebTopBar(
        pageTitle: 'Reports',
        pageSubtitle: 'Configure your clinical analytics',
        showSearch: false,
        initials: _headerInitials,
        photoUrl: _headerPhotoUrl,
        displayName:
            _headerDisplayName.isEmpty ? 'Account' : _headerDisplayName,
        roleLabel: _headerRoleLabel,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNarrowShell) const SizedBox(height: 16),

            // ── Report Type ──
            _sectionLabel('Report Type', p),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _reportTypes
                  .map((t) => _typeCard(
                        t['label'] as String,
                        t['icon'] as IconData,
                        p,
                        width: typeCardWidth,
                      ))
                  .toList(),
            ),
            const SizedBox(height: sectionGap),

            // ── Reporting Period ──
            _sectionLabel('Reporting Period', p),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                'All Time',
                'Next 30 Days',
                'Next 90 Days',
                'This Year',
                'Custom',
              ].map((preset) => _presetChip(preset, p)).toList(),
            ),
            if (!_allTime) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dateField('From', _fromDate, isFrom: true, p: p),
                  const SizedBox(width: 12),
                  _dateField('To', _toDate, isFrom: false, p: p),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Includes all items regardless of expiry date.',
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: sectionGap),

            // ── Export Format ──
            _sectionLabel('Export Format', p),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _formatCard('PDF', Icons.picture_as_pdf_outlined, p,
                    width: formatCardWidth),
                _formatCard('CSV', Icons.table_chart_outlined, p,
                    width: formatCardWidth),
              ],
            ),
            SizedBox(height: sectionGap + 4),

            // ── Download button ──
            SizedBox(
              width: 260,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateReport,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  _isGenerating ? 'Generating...' : 'Download Report',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}