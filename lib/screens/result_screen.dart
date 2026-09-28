import 'dart:io';
import '../services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'scan.dart';
import '../services/gemini_service.dart';
import 'inventory.dart';
import '../widgets/top_banner.dart';

class ResultScreen extends StatefulWidget {
  final ScanResult result;
  const ResultScreen({super.key, required this.result});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late TextEditingController productController;
  late TextEditingController expiryController;
  late TextEditingController quantityController;

  String _selectedCategory = '';
  bool isLoadingGemini = false;
  bool _isSaving = false;

  // The rich search query Gemini produced for the image lookup. Prefers
  // `image_search_query` (brand + form + variant/color, e.g. "Belfour
  // Underarm Spray Pink") over `search_query`. Used only for the online
  // image search — the saved product name stays clean.
  String _searchQuery = '';

  // Gemini-extracted dosage form (e.g. "Syrup", "Tablet", "Drops").
  // Passed to ImageSearchService so Serper results can be filtered by
  // the correct form factor.
  String _resolvedForm = '';

  // Online product photo (e.g. from Serper), resolved as soon as Gemini
  // returns a product name — shown in the preview instead of the raw scan
  // photo once it's ready. _resolvedImageForName guards against showing a
  // stale image if the user edits the product name afterward.
  String? _resolvedImageUrl;
  String? _resolvedImageForName;
  bool _isResolvingImage = false;

  static const List<String> _categories = [
    'Branded',
    'Generics',
    'Pharmacy Convenience',
  ];

  @override
  void initState() {
    super.initState();
    productController = TextEditingController();
    expiryController = TextEditingController();
    quantityController = TextEditingController();
    _runGemini();
  }

  Future<void> _runGemini() async {
    setState(() => isLoadingGemini = true);

    final Map<String, dynamic> data;
    if (widget.result.geminiFuture != null) {
      data = await widget.result.geminiFuture!;
    } else {
      data = await GeminiService.analyzeMedicine(
        rawText: widget.result.rawText,
        frontImagePath: widget.result.frontImagePath,
        backImagePath: widget.result.imagePath,
      );
    }
    debugPrint('Gemini response: $data');

    if (!mounted) return;

    final geminiName = (data['product_name'] as String?)?.trim();
    productController.text = (geminiName != null && geminiName.isNotEmpty)
        ? geminiName
        : (widget.result.productName ?? '');

    // Capture the dosage form Gemini extracted (Syrup, Tablet, Drops, etc.).
    _resolvedForm = (data['form'] as String?)?.trim() ?? '';

    // Build the search query. Prefer the richer `image_search_query`
    // (which includes variant/color like "Belfour Underarm Spray Pink"),
    // falling back to `search_query`, then to the product name.
    final richQuery = (data['image_search_query'] as String?)?.trim();
    final geminiSearchQuery = (data['search_query'] as String?)?.trim();

    String query;
    if (richQuery != null && richQuery.isNotEmpty) {
      query = richQuery;
    } else if (geminiSearchQuery != null && geminiSearchQuery.isNotEmpty) {
      query = geminiSearchQuery;
    } else {
      query = productController.text.trim();
    }

    // Defensive fallback: if no form word is present anywhere, try to
    // detect one from the OCR text and append it.
    if (_resolvedForm.isEmpty) {
      query = _ensureFormInQuery(query, widget.result.rawText);
      final detected = _detectFormWord(query);
      if (detected != null) _resolvedForm = detected;
    }

    _searchQuery = query;
    debugPrint('🎯 search_query used for image: "$_searchQuery"');
    debugPrint('💊 form used for filtering: "$_resolvedForm"');

    final geminiExpiry = (data['expiry_date'] as String?)?.trim();
    expiryController.text = (geminiExpiry != null && geminiExpiry.isNotEmpty)
        ? geminiExpiry
        : (widget.result.expiryDate ?? '');

    final cat = (data['category'] as String?)?.trim() ?? '';
    setState(() {
      _selectedCategory =
          _categories.contains(cat) ? cat : 'Pharmacy Convenience';
      isLoadingGemini = false;
    });

    // Kick off the online product-photo lookup as soon as we have a name,
    // so the preview can upgrade from the raw scan photo to the real
    // product image without waiting for the user to hit Save.
    if (_searchQuery.isNotEmpty) {
      _resolveAndSetPreviewImage(_searchQuery, form: _resolvedForm);
    }
  }

  /// Returns the first recognized form word found in [text], or null.
  String? _detectFormWord(String text) {
    const formWords = [
      'syrup',
      'drops',
      'tablet',
      'capsule',
      'suspension',
      'cream',
      'lotion',
      'spray',
      'ointment',
      'gel',
    ];
    final lower = text.toLowerCase();
    for (final form in formWords) {
      if (lower.contains(form)) {
        return form[0].toUpperCase() + form.substring(1);
      }
    }
    return null;
  }

  /// Ensures the search query contains a form word (Syrup, Drops, Tablet,
  /// etc.) so image search returns the correct variant. If the query
  /// already has one, or the OCR text has no form word, returns the query
  /// unchanged.
  String _ensureFormInQuery(String query, String rawText) {
    const formWords = [
      'syrup',
      'drops',
      'tablet',
      'capsule',
      'suspension',
      'cream',
      'lotion',
      'spray',
      'ointment',
      'gel',
    ];

    final queryLower = query.toLowerCase();

    // Already has a form word — no change needed.
    for (final form in formWords) {
      if (queryLower.contains(form)) return query;
    }

    // Look in the raw OCR text (front + back) for a form word.
    final textLower = rawText.toLowerCase();
    for (final form in formWords) {
      if (textLower.contains(form)) {
        final capitalized = form[0].toUpperCase() + form.substring(1);
        return '$query $capitalized';
      }
    }

    return query; // No form found — return original.
  }

  /// Looks up the official product photo (Serper, via SupabaseService) for
  /// the given search query and, if found, stores it for the preview.
  /// Silent no-op on failure — the preview just falls back to the local
  /// scan photo / placeholder.
  Future<void> _resolveAndSetPreviewImage(
    String searchQuery, {
    String? form,
  }) async {
    setState(() => _isResolvingImage = true);
    try {
      final url = await SupabaseService.resolveProductImageUrl(
        searchQuery,
        form: form,
      );
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() {
          _resolvedImageUrl = url;
          _resolvedImageForName = searchQuery;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Preview image resolve failed: $e');
    } finally {
      if (mounted) setState(() => _isResolvingImage = false);
    }
  }

  /// Fetches the official product image from the internet first.
  /// If that fails, it falls back to uploading the scanned photo.
  Future<String?> _resolveProductImageUrl({
    required String searchQuery,
    String? form,
  }) async {
    // 1. Try to get the official image from the internet first
    try {
      final onlineImage = await SupabaseService.resolveProductImageUrl(
        searchQuery,
        form: form,
      );
      if (onlineImage != null && onlineImage.isNotEmpty) {
        debugPrint('🌐 Found online image: $onlineImage');
        return onlineImage;
      }
    } catch (e) {
      debugPrint('⚠️ Online image search failed: $e');
    }

    // 2. Fallback: Use the local scanned photo if internet search fails
    final photoPath = widget.result.frontImagePath ?? widget.result.imagePath;

    if (photoPath != null && photoPath.isNotEmpty && !kIsWeb) {
      try {
        final bytes = await File(photoPath).readAsBytes();
        final ext = photoPath.contains('.')
            ? photoPath.split('.').last.toLowerCase()
            : 'jpg';
        final uploaded = await SupabaseService.uploadProductImageBytes(
          bytes: bytes,
          fileExt: ext,
        );
        if (uploaded != null && uploaded.isNotEmpty) return uploaded;
      } catch (e) {
        debugPrint('⚠️ Scan photo upload failed: $e');
      }
    }

    return null; // Both failed, will show the default icon in inventory
  }

  Future<void> _saveToInventory() async {
    if (productController.text.isEmpty || expiryController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in product name and expiry date'),
        ),
      );
      return;
    }

    final parsedQty = int.tryParse(quantityController.text.trim()) ?? 1;
    final safeQty = parsedQty < 1 ? 1 : parsedQty;

    setState(() => _isSaving = true);

    try {
      final productName = productController.text.trim();

      // If the user edited the product name, the previously-resolved
      // search query may no longer match — fall back to using the
      // product name as the search query in that case.
      final effectiveSearchQuery =
          _searchQuery.isNotEmpty ? _searchQuery : productName;

      debugPrint('🔍 Resolving image for query: "$effectiveSearchQuery"');

      // Reuse the image already resolved for the preview if it still
      // matches the current search query — avoids a second Serper call
      // for the common case where the user didn't edit the name.
      final imageUrl = (_resolvedImageUrl != null &&
              _resolvedImageForName == effectiveSearchQuery)
          ? _resolvedImageUrl
          : await _resolveProductImageUrl(
              searchQuery: effectiveSearchQuery,
              form: _resolvedForm,
            );
      debugPrint('🖼️ Got image URL: $imageUrl');

      await SupabaseService.saveToInventory(
        productName: productName,
        expiryDate: expiryController.text.trim(),
        category: _selectedCategory.isEmpty
            ? 'Pharmacy Convenience'
            : _selectedCategory,
        imageUrl: imageUrl,
        quantity: safeQty,
      );

      if (!mounted) return;
      TopBanner.show(context, message: 'Saved to inventory!');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const InventoryScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      setState(() => _isSaving = false);
    }
  }

  void _rescan() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  @override
  void dispose() {
    productController.dispose();
    expiryController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: !isLoadingGemini,
          decoration: InputDecoration(
            hintText: isLoadingGemini ? 'Analyzing...' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quantity',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: quantityController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isLoadingGemini ? 'Analyzing...' : _selectedCategory,
            style: TextStyle(
              fontSize: 16,
              color: _selectedCategory.isEmpty
                  ? Colors.grey
                  : (isDark ? Colors.white : Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  /// The preview thumbnail at the top of this screen.
  Widget _buildScannedImagePreview() {
    if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          _resolvedImageUrl!,
          width: 130,
          height: 170,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _buildAnalyzingPlaceholder(
              progress: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
            );
          },
          errorBuilder: (_, __, ___) => _buildLocalOrPlaceholderPreview(),
        ),
      );
    }

    final pipelineStillRunning = isLoadingGemini || _isResolvingImage;
    if (pipelineStillRunning) {
      return _buildAnalyzingPlaceholder();
    }

    return _buildLocalOrPlaceholderPreview();
  }

  Widget _buildAnalyzingPlaceholder({double? progress}) {
    return Container(
      width: 130,
      height: 170,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Center(
        child: CircularProgressIndicator(strokeWidth: 2, value: progress),
      ),
    );
  }

  Widget _buildLocalOrPlaceholderPreview() {
    final previewPath = widget.result.frontImagePath ?? widget.result.imagePath;

    if (previewPath != null && previewPath.isNotEmpty && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(previewPath),
          width: 130,
          height: 170,
          fit: BoxFit.cover,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 130,
        height: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.blue.shade50,
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.medication_rounded,
              size: 64,
              color: Colors.blue.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'Medicine',
              style: TextStyle(
                color: Colors.blue.shade300,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF4D7CFE);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Scan Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildScannedImagePreview(),

            const SizedBox(height: 25),

            if (isLoadingGemini)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text('Analyzing…'),
                  ],
                ),
              ),

            _buildField(label: 'Product Name', controller: productController),
            const SizedBox(height: 20),
            _buildField(label: 'Expiry Date', controller: expiryController),
            const SizedBox(height: 20),

            _buildCategoryField(),
            const SizedBox(height: 20),

            _buildQuantityField(),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveToInventory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: primaryBlue.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save to Inventory',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton(
                onPressed: _isSaving ? null : _rescan,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Rescan Product',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}