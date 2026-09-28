import 'supabase_service.dart';
import 'session_service.dart';

class PharmacyService {
  static Future<Map<String, String>> getDetails() async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) {
      return {
        'name': '',
        'address': '',
        'phone': '',
        'email': '',
        'type': 'Retail Pharmacy',
      };
    }

    final row = await SupabaseService.client
        .from('pharmacies')
        .select()
        .eq('id', pharmacyId)
        .maybeSingle();

    return {
      'name': row?['name'] ?? '',
      'address': row?['address'] ?? '',
      'phone': row?['phone'] ?? '',
      'email': row?['email'] ?? '',
      'type': row?['type'] ?? 'Retail Pharmacy',
    };
  }

  static Future<void> saveDetails({
    required String name,
    required String address,
    required String phone,
    required String email,
    required String type,
  }) async {
    final pharmacyId = await SessionService.pharmacyId;
    if (pharmacyId == null) return;
    await SupabaseService.client.from('pharmacies').update({
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'type': type,
    }).eq('id', pharmacyId);
  }
}