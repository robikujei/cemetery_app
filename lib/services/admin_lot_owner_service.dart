import 'package:supabase_flutter/supabase_flutter.dart';

class AdminLotOwnerService {
  const AdminLotOwnerService._();

  static const profileSelect = '''
    control_number,
    first_name,
    middle_name,
    last_name,
    address,
    occupation,
    age,
    civil_status,
    date_of_birth,
    gender,
    spouse_beneficiary,
    beneficiary_relationship,
    lot_class_type,
    block_number,
    lot_number,
    number_of_lots,
    purchase_term,
    lot_price,
    interment_fee,
    certification_fee,
    burial_permit_fee,
    total_amount,
    or_number,
    receipt_amount,
    receipt_date,
    approved_date,
    approved_by_name,
    approval_signature
  ''';

  static Map<String, dynamic> profilePayload(Map<String, String> result) {
    return {
      'control_number': _textOrNull(result['control_number']),
      'first_name': _textOrNull(result['first_name']),
      'middle_name': _textOrNull(result['middle_name']),
      'last_name': _textOrNull(result['last_name']),
      'address': _textOrNull(result['address']),
      'occupation': _textOrNull(result['occupation']),
      'age': _intOrNull(result['age']),
      'civil_status': _textOrNull(result['civil_status']),
      'date_of_birth': _textOrNull(result['date_of_birth']),
      'gender': _textOrNull(result['gender']),
      'spouse_beneficiary': _textOrNull(result['spouse_beneficiary']),
      'beneficiary_relationship': _textOrNull(
        result['beneficiary_relationship'],
      ),
      'lot_class_type': _textOrNull(result['lot_class_type']),
      'block_number': _textOrNull(result['block_number']),
      'lot_number': _textOrNull(result['lot_number']),
      'number_of_lots': _intOrNull(result['number_of_lots']),
      'purchase_term': _textOrNull(result['purchase_term']),
      'lot_price': _moneyOrNull(result['lot_price']),
      'interment_fee': _moneyOrNull(result['interment_fee']),
      'certification_fee': _moneyOrNull(result['certification_fee']),
      'burial_permit_fee': _moneyOrNull(result['burial_permit_fee']),
      'total_amount': _moneyOrNull(result['total_amount']),
      'or_number': _textOrNull(result['or_number']),
      'receipt_amount': _moneyOrNull(result['receipt_amount']),
      'receipt_date': _textOrNull(result['receipt_date']),
      'approved_date': _textOrNull(result['approved_date']),
      'approved_by_name': _textOrNull(result['approved_by_name']),
      'approval_signature': _textOrNull(result['approval_signature']),
    };
  }

  static Map<String, dynamic> lotUpdatesFromProfile(
    Map<String, dynamic> profile,
  ) {
    final data = <String, dynamic>{};
    final blockNumber = profile['block_number']?.toString().trim();
    final lotNumber = profile['lot_number']?.toString().trim();
    final lotClassType = profile['lot_class_type']?.toString().trim();
    final lotPrice = profile['lot_price'];

    if (blockNumber != null && blockNumber.isNotEmpty) {
      data['block_number'] = blockNumber;
    }
    if (lotNumber != null && lotNumber.isNotEmpty) {
      data['lot_number'] = lotNumber;
      data['lot_label'] = blockNumber == null || blockNumber.isEmpty
          ? lotNumber
          : '$blockNumber-$lotNumber';
    }
    if (lotClassType != null && lotClassType.isNotEmpty) {
      data['lot_class_type'] = lotClassType;
    }
    if (lotPrice != null) data['price'] = lotPrice;

    return data;
  }

  static int totalMonthsForPurchaseTerm(String? purchaseTerm) {
    return purchaseTerm == 'at_need' ? 24 : 1;
  }

  static Future<List<Map<String, dynamic>>> loadLotOwners() async {
    final owners = await Supabase.instance.client
        .from('users')
        .select('user_id, name, email, phone')
        .eq('role', 'lot_owner')
        .order('name');
    return List<Map<String, dynamic>>.from(owners as List);
  }

  static Future<Map<String, dynamic>?> loadOwnershipForLot(int lotId) async {
    final ownership = await Supabase.instance.client
        .from('lot_ownership')
        .select('''
          ownership_id,
          user_id,
          lot_id,
          total_months,
          months_paid,
          status,
          user:user_id (
            name,
            email,
            phone
          )
        ''')
        .eq('lot_id', lotId)
        .maybeSingle();
    return ownership == null ? null : Map<String, dynamic>.from(ownership);
  }

  static Map<String, Map<String, dynamic>> ownershipByLotId(
    Iterable<dynamic> rows,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final normalized = Map<String, dynamic>.from(row);
      final lotId = normalized['lot_id']?.toString();
      if (lotId == null || lotId.isEmpty) continue;
      map[lotId] = normalized;
    }
    return map;
  }

  static Future<String?> createAuthLotOwner({
    required String name,
    required String email,
    required String phone,
    required String password,
    required Map<String, dynamic> lotOwnerProfile,
  }) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.functions.invoke(
        'admin-user-management',
        body: {
          'action': 'create',
          'name': name,
          'email': email,
          'phone': phone,
          'role': 'lot_owner',
          'password': password,
          'lotOwnerProfile': lotOwnerProfile,
        },
      );

      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      if (data is Map) {
        final user = data['user'];
        if (user is Map) return user['id']?.toString();
      }
      return null;
    } catch (e) {
      final message = e.toString();
      if (message.contains('Failed to fetch') ||
          message.contains('ClientException')) {
        throw Exception(
          'Unable to reach the Supabase edge function "admin-user-management". '
          'Deploy it in Supabase or check the project URL and function name.',
        );
      }
      rethrow;
    }
  }

  static Future<String?> findUserIdByEmail(String email) async {
    final user = await Supabase.instance.client
        .from('users')
        .select('user_id')
        .eq('email', email)
        .maybeSingle();
    return user?['user_id']?.toString();
  }

  static Future<void> upsertLotOwnerDirectoryProfile({
    required String userId,
    required String name,
    required String email,
    required String phone,
    required Map<String, dynamic> lotOwnerProfile,
  }) async {
    await Supabase.instance.client.from('users').upsert({
      'user_id': userId,
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
      'role': 'lot_owner',
      'password': 'managed_by_auth',
      ...lotOwnerProfile,
    }, onConflict: 'user_id');
  }

  static Future<void> assignOwnerToLot({
    required int lotId,
    required String userId,
    required int totalMonths,
    Map<String, dynamic>? lotOwnerProfile,
    Map<String, dynamic>? lotUpdates,
  }) async {
    final supabase = Supabase.instance.client;

    if (lotOwnerProfile != null) {
      await supabase
          .from('users')
          .update(lotOwnerProfile)
          .eq('user_id', userId);
    }

    if (lotUpdates != null && lotUpdates.isNotEmpty) {
      await supabase
          .from('cemetery_lot')
          .update(lotUpdates)
          .eq('lot_id', lotId);
    }

    final existingForLot = await supabase
        .from('lot_ownership')
        .select('ownership_id')
        .eq('lot_id', lotId)
        .maybeSingle();

    if (existingForLot != null) {
      await supabase
          .from('lot_ownership')
          .update({
            'user_id': userId,
            'total_months': totalMonths,
            'status': 'Active',
          })
          .eq('ownership_id', existingForLot['ownership_id']);
    } else {
      await supabase.from('lot_ownership').insert({
        'user_id': userId,
        'lot_id': lotId,
        'total_months': totalMonths,
        'months_paid': 0,
        'start_date': DateTime.now().toIso8601String(),
        'status': 'Active',
      });
    }

    await refreshLotStatus(lotId);
  }

  static Future<void> removeOwnerFromLot(int lotId) async {
    await Supabase.instance.client
        .from('lot_ownership')
        .delete()
        .eq('lot_id', lotId);
    await refreshLotStatus(lotId);
  }

  static Future<void> refreshLotStatus(int lotId) async {
    final supabase = Supabase.instance.client;

    try {
      final occupiedGraves = await supabase
          .from('graves')
          .select('grave_id')
          .eq('lot_id', lotId)
          .eq('status', 'Occupied')
          .limit(1);
      if ((occupiedGraves as List).isNotEmpty) {
        await supabase
            .from('cemetery_lot')
            .update({'status': 'Occupied'})
            .eq('lot_id', lotId);
        return;
      }
    } catch (_) {
      // The graves table is optional during migration; burial_record still
      // protects occupied lots below.
    }

    final burials = await supabase
        .from('burial_record')
        .select('burial_id')
        .eq('lot_id', lotId)
        .limit(1);
    if ((burials as List).isNotEmpty) {
      await supabase
          .from('cemetery_lot')
          .update({'status': 'Occupied'})
          .eq('lot_id', lotId);
      return;
    }

    final ownerships = await supabase
        .from('lot_ownership')
        .select('ownership_id')
        .eq('lot_id', lotId)
        .limit(1);
    await supabase
        .from('cemetery_lot')
        .update({
          'status': (ownerships as List).isEmpty ? 'Available' : 'Reserved',
        })
        .eq('lot_id', lotId);
  }

  static String? _textOrNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _intOrNull(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  static double? _moneyOrNull(String? value) {
    final text =
        value
            ?.trim()
            .toUpperCase()
            .replaceAll('PHP', '')
            .replaceAll('₱', '')
            .replaceAll(',', '') ??
        '';
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }
}
