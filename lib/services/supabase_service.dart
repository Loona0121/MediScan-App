import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session_service.dart';
import '../services/image_search_service.dart';
import 'package:flutter/foundation.dart';
import '../services/gemini_service.dart';
import 'package:http/http.dart' as http;
import '../constants/env.dart';


class SupabaseService {
  static const String supabaseUrl = Env.supabaseUrl;
  static const String supabaseAnonKey = Env.supabaseAnonKey;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> resetPassword(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'mediscan://reset-password',
      );
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> updatePassword(String newPassword) async {
    try {
      await client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> updateItemDetails({
    required int id,
    int? quantity,
  }) async {
    await client
        .from('inventory')
        .update({
          'quantity': quantity,
        })
        .eq('id', id);
  }

  static Future<void> updateItemCore({
    required int id,
    required String productName,
    required String expiryDate,
    required String category,
  }) async {
    await client
        .from('inventory')
        .update({
          'product_name': productName.trim(),
          'expiry_date': expiryDate.trim(),
          'category': category,
        })
        .eq('id', id);
  }

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  /// True when [url] is already served from our Supabase Storage (safe on web).
  static bool isSupabaseHostedImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    return url.contains(supabaseUrl) && url.contains('/product-images/');
  }

  /// Ensures [rawUrl] is a Supabase-hosted product image URL.
  static Future<String?> ensureHostedImageUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    if (isSupabaseHostedImageUrl(rawUrl)) return rawUrl;
    return rehostImageUrl(rawUrl.trim());
  }

  /// Rehosts an external image into `product-images`.
  static Future<String?> rehostImageUrl(String rawUrl) async {
    if (isSupabaseHostedImageUrl(rawUrl)) return rawUrl;

    try {
      final response = await client.functions.invoke(
        'rehost-product-image',
        body: {'imageUrl': rawUrl},
      );
      final data = response.data;
      if (data is Map) {
        final publicUrl = data['publicUrl'] as String?;
        if (publicUrl != null && publicUrl.isNotEmpty) return publicUrl;
        print('❌ Rehost edge function error: ${data['error']}');
      }
    } catch (e) {
      print('❌ Rehost edge function failed: $e');
    }

    try {
      final response = await http.get(Uri.parse(rawUrl));
      if (response.statusCode != 200) {
        print('❌ Rehost failed: HTTP ${response.statusCode} for $rawUrl');
        return null;
      }

      final contentType = response.headers['content-type'] ?? '';
      String fileExt = 'jpg';
      if (contentType.contains('png')) {
        fileExt = 'png';
      } else if (contentType.contains('webp')) {
        fileExt = 'webp';
      } else if (contentType.contains('gif')) {
        fileExt = 'gif';
      }

      return await uploadProductImageBytes(
        bytes: response.bodyBytes,
        fileExt: fileExt,
      );
    } catch (e) {
      print('❌ Rehost error for $rawUrl: $e');
      return null;
    }
  }

  static Future<String?> uploadProductImage(File imageFile) async {
    try {
      final fileName =
          'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await client.storage.from('product-images').upload(
            fileName,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );
      return client.storage.from('product-images').getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  /// Finds inventory items with missing OR external (non-Supabase) image URLs
  /// and rehosts / searches so Flutter web can display them without CORS errors.
  /// Safe to run multiple times.
  static Future<int> backfillMissingImages() async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) return 0;

    final rows = await client
        .from('inventory')
        .select('id, product_name, image_url')
        .eq('pharmacy_id', pharmacyId);

    int updated = 0;
    for (final row in rows) {
      final id = row['id'];
      final name = row['product_name'] as String? ?? '';
      final currentUrl = row['image_url'] as String?;
      if (name.trim().isEmpty) continue;
      if (isSupabaseHostedImageUrl(currentUrl)) continue;

      // 1. Try to rehost the existing URL.
      String? imageUrl = await ensureHostedImageUrl(currentUrl);

      // 2. If that failed, run a fresh image search using the product name.
      //    Legacy rows don't have a form column, so we pass an empty form —
      //    buildImageSearchQuery will just return the product name.
      if (imageUrl == null) {
        final searchQuery = GeminiService.buildImageSearchQuery({
          'product_name': name,
          'form': '',
        });
        final rawUrl =
            await ImageSearchService.fetchProductImageUrl(searchQuery);
        imageUrl = await ensureHostedImageUrl(rawUrl);
      }

      if (imageUrl != null && imageUrl != currentUrl) {
        await client
            .from('inventory')
            .update({'image_url': imageUrl})
            .eq('id', id);
        updated++;
      }
    }
    return updated;
  }

  static Future<String?> getExistingImageUrl(String productName) async {
    try {
      final pharmacyId = await SessionService.pharmacyId;
      final response = await client
          .from('inventory')
          .select('image_url')
          .eq('pharmacy_id', pharmacyId!)
          .ilike('product_name', productName.trim())
          .not('image_url', 'is', null)
          .neq('image_url', '')
          .limit(1)
          .maybeSingle();

      return response?['image_url'] as String?;
    } catch (e) {
      print('❌ Failed to check existing image: $e');
      return null;
    }
  }

  /// Resolves a display-ready product image URL for a new inventory item.
  ///
  /// [form] is the Gemini-extracted dosage form (e.g. "Syrup", "Tablet",
  /// "Drops"). It is only used to *build* the search query when the
  /// supplied [productName] doesn't already include the form word — so
  /// passing a rich query like "Symdex-D Syrup" as [productName] won't
  /// result in "Symdex-D Syrup Syrup".
  static Future<String?> resolveProductImageUrl(
    String productName, {
    String? form,
  }) async {
    final existing = await getExistingImageUrl(productName);
    final hostedExisting = await ensureHostedImageUrl(existing);
    if (hostedExisting != null) return hostedExisting;

    // If productName already contains the form word, don't append it again.
    final formLower = (form ?? '').toLowerCase().trim();
    final nameLower = productName.toLowerCase().trim();
    final alreadyHasForm =
        formLower.isNotEmpty && nameLower.contains(formLower);

    final searchQuery = alreadyHasForm
        ? productName
        : GeminiService.buildImageSearchQuery({
            'product_name': productName,
            'form': form ?? '',
          });

    final rawUrl = await ImageSearchService.fetchProductImageUrl(
      searchQuery,
      form: form,
    );
    return ensureHostedImageUrl(rawUrl);
  }

  static bool _imageBackfillRan = false;

  static Future<int> ensureProductImagesBackfilled() async {
    if (_imageBackfillRan) return 0;
    _imageBackfillRan = true;
    try {
      final updated = await backfillMissingImages();
      print('🖼️ Product image backfill updated $updated item(s)');
      return updated;
    } catch (e) {
      _imageBackfillRan = false;
      print('❌ Product image backfill failed: $e');
      return 0;
    }
  }

  static Future<String?> uploadProductImageBytes({
    required Uint8List bytes,
    String fileExt = 'jpg',
  }) async {
    try {
      final fileName =
          'product_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      await client.storage.from('product-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return client.storage.from('product-images').getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  static Future<String> uploadProfilePhoto({
    required String email,
    required Uint8List bytes,
    String fileExt = 'jpg',
  }) async {
    final safeEmail = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final fileName =
        'profile_${safeEmail}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from('profile-photos').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return client.storage.from('profile-photos').getPublicUrl(fileName);
  }

  static String normalizeProductName(String name) {
    return name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<void> saveToInventory({
    required String productName,
    required String expiryDate,
    required String category,
    String? imageUrl,
    int quantity = 1,
  }) async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) {
      throw Exception('No active pharmacy session found.');
    }

    final trimmedName = productName.trim();
    final trimmedExpiry = expiryDate.trim();
    final normalizedName = normalizeProductName(trimmedName);

    final existing = await client
        .from('inventory')
        .select('id, quantity')
        .eq('pharmacy_id', pharmacyId)
        .ilike('product_name', normalizedName)
        .eq('expiry_date', trimmedExpiry)
        .maybeSingle();

    if (existing != null) {
      final currentQty = (existing['quantity'] as num?)?.toInt() ?? 0;
      await client
          .from('inventory')
          .update({'quantity': currentQty + quantity})
          .eq('id', existing['id']);
    } else {
      await client.from('inventory').insert({
        'product_name': trimmedName,
        'expiry_date': trimmedExpiry,
        'category': category,
        'image_url': imageUrl,
        'pharmacy_id': pharmacyId,
        'quantity': quantity,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> fetchInventory() async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) return [];
    final response = await client
        .from('inventory')
        .select()
        .eq('pharmacy_id', pharmacyId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<String?> fetchPharmacyName() async {
    try {
      final pharmacyId = await SessionService.pharmacyId;
      if (pharmacyId == null) return null;

      final row = await client
          .from('pharmacies')
          .select('name')
          .eq('id', pharmacyId)
          .maybeSingle();

      final name = row?['name']?.toString();
      if (name == null || name.trim().isEmpty) return null;
      return name.trim();
    } catch (e) {
      debugPrint('fetchPharmacyName error: $e');
      return null;
    }
  }

  static Future<void> deleteItem(int id) async {
    await client.from('inventory').delete().eq('id', id);
  }

  static Future<void> markNotificationAsRead(int id) async {
    await client
        .from('inventory')
        .update({'is_read': true})
        .eq('id', id);
  }

  static Future<void> markAllNotificationsAsRead() async {
    final pharmacyId = await SessionService.pharmacyId;

    await client
        .from('inventory')
        .update({'is_read': true})
        .eq('pharmacy_id', pharmacyId!);
  }

  static Future<bool> hasUnreadNotifications() async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) return false;

    final response = await client
        .from('inventory')
        .select('expiry_date')
        .eq('pharmacy_id', pharmacyId)
        .eq('is_read', false);

    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    for (final row in response) {
      final expiryStr = row['expiry_date'] as String?;
      if (expiryStr == null) continue;
      final parts = expiryStr.split('-');
      if (parts.length < 2) continue;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null) continue;
      final day = parts.length >= 3 ? int.tryParse(parts[2]) ?? 1 : 1;

      DateTime expiry;
      try {
        expiry = DateTime(year, month, day);
      } catch (_) {
        continue;
      }

      final diff = expiry.difference(todayDateOnly).inDays;
      if (diff <= 90) return true;
    }

    return false;
  }

  static Future<void> saveNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final pharmacyId = await SessionService.pharmacyId;

      await client.from('notifications').insert({
        'pharmacy_id': pharmacyId,
        'title': title,
        'body': body,
        'type': type,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Notification saved to database');
    } catch (e) {
      print('❌ Failed to save notification: $e');
    }
  }
}