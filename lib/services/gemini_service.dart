import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;

class GeminiService {
  static const String apiKey = Env.geminiKey;

  static Future<Uint8List?> _compressImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await compute(_compressBytes, bytes);
    } catch (e) {
      debugPrint('Image compression failed, using original: $e');
      try {
        return await File(path).readAsBytes();
      } catch (_) {
        return null;
      }
    }
  }

  static Uint8List _compressBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final resized = decoded.width > decoded.height
        ? img.copyResize(decoded, width: 800)
        : img.copyResize(decoded, height: 800);

    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  static Future<Map<String, dynamic>> _callGemini(
    String promptText,
    List<DataPart> images,
  ) async {
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        final model = GenerativeModel(
          model: 'gemini-flash-lite-latest',
          apiKey: apiKey,
        );

        final parts = <Part>[TextPart(promptText), ...images];

        final response = await model
            .generateContent([Content.multi(parts)])
            .timeout(
              const Duration(seconds: 45),
              onTimeout: () => throw Exception('Gemini timeout'),
            );

        final text = response.text ?? '{}';
        debugPrint('Gemini raw: $text');

        final cleaned = text
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        return jsonDecode(cleaned) as Map<String, dynamic>;
      } catch (e) {
        final errorMsg = e.toString();
        debugPrint('Gemini error (attempt ${retries + 1}): $errorMsg');

        final shouldRetry = errorMsg.contains('429') ||
            errorMsg.contains('quota') ||
            errorMsg.contains('503') ||
            errorMsg.contains('UNAVAILABLE') ||
            errorMsg.contains('timeout');

        if (shouldRetry) {
          retries++;
          if (retries < maxRetries) {
            final waitSecs = retries * 5;
            debugPrint('Retrying in $waitSecs seconds...');
            await Future.delayed(Duration(seconds: waitSecs));
            continue;
          }
        }

        return {};
      }
    }
    return {};
  }

  static Future<Map<String, dynamic>> analyzeMedicine({
    required String rawText,
    String? frontImagePath,
    String? backImagePath,
    String? frontOcrText,
    String? backOcrText,
  }) async {
    final List<DataPart> images = [];

    if (frontImagePath != null && frontImagePath.isNotEmpty) {
      final bytes = await _compressImage(frontImagePath);
      if (bytes != null) images.add(DataPart('image/jpeg', bytes));
    }

    if (backImagePath != null && backImagePath.isNotEmpty) {
      final bytes = await _compressImage(backImagePath);
      if (bytes != null) images.add(DataPart('image/jpeg', bytes));
    }

    if (images.isEmpty) return {};

    final promptText = '''
You are analyzing a medicine or pharmacy product package. You are given up to two photos: one of the FRONT label, and one of the BACK/EXPIRY label. You are also given OCR text extracted from them as a helpful reference. The OCR text may contain mistakes or be incomplete — always trust what you see in the images over the OCR text when they conflict.

OCR TEXT FROM FRONT:
${frontOcrText ?? rawText}

OCR TEXT FROM BACK:
${backOcrText ?? ''}

Extract ONLY these 6 fields:

1. product_name: The BRAND/TRADE NAME ONLY (e.g., "Symdex-D", "Clircaf", "Biogesic", "Cepham", "Allerkid", "Belfour").
   - The brand name is the main title printed in the LARGEST/BOLDEST text on the front label.
   - EXCLUDE the generic/chemical name. Many boxes put the generic name (e.g., "Cetirizine", "Paracetamol", "Cefalexin", "Lagundi Leaf") at the VERY TOP or in a box. DO NOT USE THIS.
   - EXCLUDE the manufacturer name (e.g., "Unilab", "Pascual Lab", "LifeSquare").
   - EXCLUDE dosage (e.g., 500mg, 10ml) and form (e.g., Syrup, Drops, Tablet).
   - EXCLUDE color/variant words (e.g., "Pink", "Blue", "Cool", "Fresh") — those go in image_search_query instead.
   - Normalize casing to Title Case (e.g., "SYMDEX-D" -> "Symdex-D").
   - If the image is too blurry to confidently read the actual brand name, return an empty string "".

2. search_query: Short search phrase (2-4 words) for the general product family — brand + form.
   - e.g., "Symdex-D Syrup", "Allerkid Drops", "Cepham Drops", "Biogesic Tablet".
   - INCLUDE the form word (syrup, drops, tablet, capsule, suspension, cream, lotion, spray, etc.).
   - DO NOT include dosage, generic/chemical names, or manufacturer names.
   - If the form is not clearly visible, use just the brand name.

3. image_search_query: RICHER search phrase used ONLY for fetching the exact product photo online. This is what disambiguates variants that look identical but differ in color, scent, or product line.
   - Combine: BRAND NAME + FORM + VARIANT/COLOR/SCENT/LINE (whatever is visible on the pack).
   - Examples:
     • "Belfour Underarm Spray Pink" (if the pack is pink and says "Underarm Spray")
     • "Belfour Underarm Spray Blue" (if the pack is blue)
     • "Symdex-D Syrup" (no variant visible → just brand + form)
     • "Head & Shoulders Shampoo Cool Menthol"
     • "Nivea Body Lotion Whitening"
     • "Rexona Deodorant Roll On Powder Dry"
   - INCLUDE the visible color word (pink, blue, green, red, white, black) IF the product line uses color to distinguish variants AND the color is clearly printed or the packaging is clearly that color.
   - INCLUDE the product-line / variant word printed on the pack (e.g., "Underarm Spray", "Roll On", "Cool", "Fresh", "Whitening", "Menthol").
   - DO NOT include dosage strength (no "500mg", no "10ml").
   - DO NOT include generic/chemical names or manufacturer names.
   - Keep it 3 to 6 words. This is the most important field for getting the right image — be specific.

4. expiry_date: Look ONLY at the BACK/EXPIRY label.
   - Look for labels: EXPIRY, EXP, BEST BEFORE, USE BEFORE, BB.
   - IGNORE any date labeled MFG, MANUFACTURED, PRODUCTION, PROD DATE, or a bare "M"/"M:" in an M/E pairing.
   - If you see "M:MAY2026 E:MAY2028", return "2028-05" (the "E" date).
   - Return in YYYY-MM format only.
   - If not visible/blurry/ambiguous, return "".

5. category: EXACTLY one of:
   - "Branded" — has a distinct trade/brand name.
   - "Generics" — only the plain chemical/generic name, no trade name.
   - "Pharmacy Convenience" — non-medicine personal care (deodorant, lotion, soap, wash, spray, shampoo).

6. form: Dosage form printed on the packaging — one of: "Syrup", "Tablet", "Capsule", "Drops", "Suspension", "Cream", "Lotion", "Spray", "Ointment", "Powder", "Injection", "Lozenge", "Roll On", "Shampoo", "Soap", "Wash", "Deodorant".
   - Read directly off the pack.
   - If not visible, return "".

Return ONLY valid JSON, no markdown, no backticks.

Examples:
- Box shows "PHENYLPROPANOLAMINE... PARACETAMOL", "Symdex-D" bold, "Syrup" printed → {"product_name":"Symdex-D","search_query":"Symdex-D Syrup","image_search_query":"Symdex-D Syrup","expiry_date":"2027-09","category":"Branded","form":"Syrup"}
- Pink spray can shows "Belfour" bold, "Underarm Spray", pack is pink → {"product_name":"Belfour","search_query":"Belfour Underarm Spray","image_search_query":"Belfour Underarm Spray Pink","expiry_date":"","category":"Pharmacy Convenience","form":"Spray"}
- Blue spray can shows "Belfour" bold, "Underarm Spray", pack is blue → {"product_name":"Belfour","search_query":"Belfour Underarm Spray","image_search_query":"Belfour Underarm Spray Blue","expiry_date":"","category":"Pharmacy Convenience","form":"Spray"}
- Box shows "Cefalexin" in a box at the top, "CEPHAM" bold, "Drops" → {"product_name":"Cepham","search_query":"Cepham Drops","image_search_query":"Cepham Drops","expiry_date":"","category":"Branded","form":"Drops"}
- Bottle shows "Head & Shoulders" and "Cool Menthol" → {"product_name":"Head & Shoulders","search_query":"Head & Shoulders Shampoo","image_search_query":"Head & Shoulders Shampoo Cool Menthol","expiry_date":"","category":"Pharmacy Convenience","form":"Shampoo"}

Example output format:
{"product_name":"Symdex-D","search_query":"Symdex-D Syrup","image_search_query":"Symdex-D Syrup","expiry_date":"2027-09","category":"Branded","form":"Syrup"}
''';

    return _callGemini(promptText, images);
  }

  /// The best query to use for online image search. Prefers the richer
  /// `image_search_query` (brand + form + variant/color) when Gemini
  /// provided one, and falls back to `product_name + form` otherwise.
  ///
  /// This helper is **idempotent** — if `product_name` already contains
  /// the form word (e.g. product_name = "Symdex-D Syrup", form = "Syrup"),
  /// the form is NOT appended again.
  static String buildImageSearchQuery(Map<String, dynamic> result) {
    final rich = (result['image_search_query'] ?? '').toString().trim();
    if (rich.isNotEmpty) return rich;

    final productName = (result['product_name'] ?? '').toString().trim();
    final form = (result['form'] ?? '').toString().trim();

    if (productName.isEmpty) return '';

    if (form.isEmpty) return productName;

    // Don't duplicate the form word if it's already in the product name.
    if (productName.toLowerCase().contains(form.toLowerCase())) {
      return productName;
    }

    return '$productName $form';
  }
}