// services/image_search_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ImageSearchService {
  static const _apiKey = Env.serperKey;

  /// Fetch a product image using a search query that already contains
  /// the brand name, form, and (when available) the variant/color.
  ///
  /// [form] is used to filter results so a "Syrup" query can't return a
  /// Tablet box, and a "Spray" query is further filtered by any color /
  /// variant words present in [searchQuery] (e.g. "Belfour Underarm
  /// Spray Pink" prefers results mentioning "pink").
  static Future<String?> fetchProductImageUrl(
    String searchQuery, {
    String? form,
  }) async {
    final url = Uri.parse('https://google.serper.dev/images');

    // Keep the query intact — do NOT strip the form or variant word.
    final query = searchQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) return null;

    try {
      final response = await http.post(
        url,
        headers: {
          'X-API-KEY': _apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'q': query,
          'gl': 'ph',
          'hl': 'en',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = data['images'] as List?;

        if (images != null && images.isNotEmpty) {
          // ignore: avoid_print
          print('Serper found ${images.length} result(s) for "$query"');

          final formLower = (form ?? '').toLowerCase().trim();

          // Pull variant keywords (color, scent, product line) out of the
          // query so we can prefer results that mention them.
          const variantWords = [
            'pink', 'blue', 'green', 'red', 'white', 'black', 'yellow',
            'orange', 'purple', 'violet', 'teal', 'gold', 'silver',
            'cool', 'fresh', 'menthol', 'whitening', 'lightening',
            'roll on', 'roll-on', 'underarm', 'spray', 'stick',
            'pink', 'powder', 'dry',
          ];
          final queryLower = query.toLowerCase();
          final variantKeywords = variantWords
              .where((w) => queryLower.contains(w))
              .toSet()
              .toList();

          bool matches(Map img) {
            final title = (img['title'] ?? '').toString().toLowerCase();
            final imageUrl =
                (img['imageUrl'] ?? '').toString().toLowerCase();
            final haystack = '$title $imageUrl';

            // Must match the form (if provided).
            if (formLower.isNotEmpty && !haystack.contains(formLower)) {
              return false;
            }

            // Must match every variant keyword found in the query.
            for (final kw in variantKeywords) {
              if (!haystack.contains(kw)) return false;
            }

            return true;
          }

          final matching =
              images.where((img) => matches(img as Map)).toList();
          final pool = matching.isNotEmpty ? matching : images;

          for (var img in pool) {
            final imageUrl = img['imageUrl'] as String?;
            if (imageUrl != null &&
                !imageUrl.contains('logo') &&
                !imageUrl.contains('icon')) {
              return imageUrl;
            }
          }
          return pool.first['imageUrl'] as String?;
        } else {
          // ignore: avoid_print
          print('Serper returned 0 image results for "$query"');
        }
      } else {
        // ignore: avoid_print
        print('Serper error (${response.statusCode}) for "$query": ${response.body}');
      }
    } catch (e) {
      print('Image search failed: $e');
    }
    return null;
  }
}