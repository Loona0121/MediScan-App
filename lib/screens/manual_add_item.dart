import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';
import 'inventory.dart';
import '../widgets/top_banner.dart';
import '../utils/app_palette.dart';
import '../services/background_tasks.dart';

class ManualAddItemScreen extends StatefulWidget {
  final MedicineItem? existingItem;

  const ManualAddItemScreen({super.key, this.existingItem});

  bool get isEditing => existingItem != null;

  /// Shows the form as a modal over the current screen with a blurred
  /// backdrop. Returns `true` if saved, `null`/`false` otherwise.
  static Future<bool?> show(
    BuildContext context, {
    MedicineItem? existingItem,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.10),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          ManualAddItemScreen(existingItem: existingItem),
    );
  }

  @override
  State<ManualAddItemScreen> createState() => _ManualAddItemScreenState();
}

class _ManualAddItemScreenState extends State<ManualAddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController productController = TextEditingController();
  final TextEditingController expiryController = TextEditingController();
  final TextEditingController quantityController =
      TextEditingController(text: '1');

  String _selectedCategory = 'Pharmacy Convenience';
  bool _isSaving = false;

  List<String> _categories = ['Branded', 'Generics', 'Pharmacy Convenience'];

  static const Color _primaryBlue = Color(0xFF4D7CFE);
  static const Color _datePickerPurple = Color(0xFF6A1BFF);

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    if (item != null) {
      productController.text = item.productName;
      expiryController.text = item.expiryDate;
      quantityController.text = item.quantity?.toString() ?? '1';

      if (item.category.isNotEmpty && !_categories.contains(item.category)) {
        _categories = [item.category, ..._categories];
      }
      if (item.category.isNotEmpty) {
        _selectedCategory = item.category;
      }
    }
  }

  @override
  void dispose() {
    productController.dispose();
    expiryController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime? _tryParseExistingExpiry(String raw) {
    if (raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    final parts = raw.split('-');
    if (parts.length >= 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null) return DateTime(y, m, 1);
    }
    return null;
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final initial = _tryParseExistingExpiry(expiryController.text) ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 15),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'SELECT DATE',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _datePickerPurple,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              headerBackgroundColor: _datePickerPurple,
              headerForegroundColor: Colors.white,
              headerHeadlineStyle: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              headerHelpStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: Colors.white70,
              ),
              weekdayStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
              dayStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              dayShape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _datePickerPurple;
                }
                return Colors.transparent;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return const Color(0xFF1E293B);
              }),
              todayBorder: const BorderSide(
                color: _datePickerPurple,
                width: 1.5,
              ),
              todayForegroundColor: const WidgetStatePropertyAll(
                Color(0xFF1E293B),
              ),
              todayBackgroundColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              yearShape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _datePickerPurple;
                }
                return Colors.transparent;
              }),
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return const Color(0xFF1E293B);
              }),
              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: _datePickerPurple,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              confirmButtonStyle: TextButton.styleFrom(
                foregroundColor: _datePickerPurple,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _datePickerPurple),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: _datePickerPurple,
              foregroundColor: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      expiryController.text = _formatDate(picked);
    }
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final productName = productController.text.trim();
      final quantity = int.tryParse(quantityController.text.trim()) ?? 1;
      final expiry = expiryController.text.trim();

      if (widget.isEditing) {
        await SupabaseService.updateItemCore(
          id: widget.existingItem!.id,
          productName: productName,
          expiryDate: expiry,
          category: _selectedCategory,
        );
        await SupabaseService.updateItemDetails(
          id: widget.existingItem!.id,
          quantity: quantity,
        );

        if (!mounted) return;
        TopBanner.show(
          context,
          message: 'Item updated successfully!',
          width: 320,
          alignment: Alignment.topCenter,
        );
      } else {
        final imageUrl = await SupabaseService.resolveProductImageUrl(
          productName,
        );

        await SupabaseService.saveToInventory(
          productName: productName,
          expiryDate: expiry,
          category: _selectedCategory,
          imageUrl: imageUrl,
          quantity: quantity,
        );

        if (!mounted) return;
        TopBanner.show(
          context,
          message: 'Item added to inventory!',
          width: 320,
          alignment: Alignment.topCenter,
        );
      }

      BackgroundTasks.runOnceNow();

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration({
    required AppPalette p,
    String? hint,
    Widget? suffixIcon,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: p.searchBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  Widget _fieldLabel(String label, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.isEditing;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      // Fully transparent so the dialog barrier + blur show through to
      // the page underneath (inventory / dashboard / etc.).
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Blur over whatever is behind the dialog ──
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Material(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header ──
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isEditing
                                            ? 'Edit Item'
                                            : 'Add Item Manually',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isEditing
                                            ? 'Update the details of this item.'
                                            : 'Enter product details to add it to inventory.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () => Navigator.pop(context),
                                  icon: Icon(
                                    Icons.close,
                                    size: 22,
                                    color: p.textSecondary,
                                  ),
                                  tooltip: 'Close',
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // ── Product Name ──
                            _fieldLabel('Product Name', p),
                            TextFormField(
                              controller: productController,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(color: p.textPrimary),
                              decoration: _inputDecoration(
                                p: p,
                                hint: 'e.g. Biogesic 500mg',
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Please enter a product name'
                                  : null,
                            ),
                            const SizedBox(height: 16),

                            // ── Expiry Date ──
                            _fieldLabel('Expiry Date', p),
                            TextFormField(
                              controller: expiryController,
                              readOnly: true,
                              onTap: _pickExpiryDate,
                              style: TextStyle(color: p.textPrimary),
                              decoration: _inputDecoration(
                                p: p,
                                hint: 'Tap to select date',
                                suffixIcon: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                  color: p.textSecondary,
                                ),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Please select an expiry date'
                                  : null,
                            ),
                            const SizedBox(height: 16),

                            // ── Quantity ──
                            _fieldLabel('Quantity', p),
                            TextFormField(
                              controller: quantityController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: p.textPrimary,
                              ),
                              decoration: _inputDecoration(
                                p: p,
                                hint: 'Enter quantity',
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) {
                                  return 'Please enter a quantity';
                                }
                                final n = int.tryParse(text);
                                if (n == null || n < 1) {
                                  return 'Must be at least 1';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // ── Category ──
                            _fieldLabel('Category', p),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCategory,
                              decoration: _inputDecoration(p: p),
                              dropdownColor: p.cardBg,
                              icon: Icon(
                                Icons.keyboard_arrow_down,
                                color: p.textSecondary,
                              ),
                              style: GoogleFonts.poppins(
                                color: p.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                              items: _categories
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c,
                                        style: GoogleFonts.poppins(
                                          color: p.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedCategory = value);
                                }
                              },
                            ),

                            const SizedBox(height: 24),

                            // ── Actions ──
                            // Cancel is now `Expanded` (equal to Save Changes'
                            // column) so "Cancel" no longer wraps to
                            // "Canc\nel". Save Changes keeps flex 2, so the
                            // row is still 1/3 : 2/3 in favor of the primary
                            // action.
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 48,
                                    child: OutlinedButton(
                                      onPressed: _isSaving
                                          ? null
                                          : () => Navigator.pop(context),
                                      style: OutlinedButton.styleFrom(
                                        side:
                                            BorderSide(color: p.cardBorder),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: Text(
                                        'Cancel',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: p.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: SizedBox(
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed:
                                          _isSaving ? null : _saveItem,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryBlue,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            _primaryBlue.withValues(
                                          alpha: 0.6,
                                        ),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: _isSaving
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              isEditing
                                                  ? 'Save Changes'
                                                  : 'Add to Inventory',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}