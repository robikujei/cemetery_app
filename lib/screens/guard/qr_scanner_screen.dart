import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/lot_formatters.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  static const _background = Color(0xFFFBF9F6);
  static const _primary = Color(0xFF335538);
  static const _primaryContainer = Color(0xFF4B6E4F);
  static const _primaryFixed = Color(0xFFC5EDC6);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceVariant = Color(0xFFE4E2DF);
  static const _onSurface = Color(0xFF1B1C1A);
  static const _onSurfaceVariant = Color(0xFF424841);
  static const _error = Color(0xFFBA1A1A);
  static const _warning = Color(0xFFF57C00);

  final MobileScannerController _controller = MobileScannerController();

  Map<String, dynamic>? _lastPayload;
  bool _isProcessing = false;
  String? _scanMessage;
  Color _messageColor = _primary;
  List<Map<String, dynamic>> _todayVisitors = [];
  bool _isLoadingVisitors = true;

  @override
  void initState() {
    super.initState();
    _loadTodayVisitors();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadTodayVisitors() async {
    setState(() => _isLoadingVisitors = true);

    try {
      final supabase = Supabase.instance.client;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final result = await supabase
          .from('visitor_log')
          .select('''
            log_id,
            time_in,
            method,
            user:user_id (name, email),
            burial:burial_id (
              name_of_deceased,
              cemetery_lot (
                lot_number,
                lot_label,
                block_number,
                lot_class_type
              )
            )
          ''')
          .gte('time_in', '$today 00:00:00')
          .lte('time_in', '$today 23:59:59')
          .order('time_in', ascending: false);

      if (!mounted) return;
      setState(() {
        _todayVisitors = List<Map<String, dynamic>>.from(result);
        _isLoadingVisitors = false;
      });
    } catch (e) {
      debugPrint('Error loading visitors: $e');
      if (!mounted) return;
      setState(() => _isLoadingVisitors = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: _error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go('/login');
    }
  }

  Future<void> _handleScan(Map<String, dynamic> payload) async {
    if (_isProcessing) return;

    debugPrint('=== SCANNED QR PAYLOAD ===');
    debugPrint('Full payload: $payload');
    debugPrint('visitorName: ${payload['visitorName']}');
    debugPrint('visitorId: ${payload['visitorId']}');
    debugPrint('burialId: ${payload['burialId']}');
    debugPrint('deceasedName: ${payload['deceasedName']}');

    setState(() {
      _isProcessing = true;
      _scanMessage = null;
      _lastPayload = payload;
    });

    try {
      final supabase = Supabase.instance.client;

      String visitorName = 'Unknown';
      if (payload['visitorName'] != null &&
          payload['visitorName'].toString().isNotEmpty) {
        visitorName = payload['visitorName'].toString();
      } else if (payload['displayName'] != null &&
          payload['displayName'].toString().isNotEmpty) {
        visitorName = payload['displayName'].toString();
      } else if (payload['name'] != null &&
          payload['name'].toString().isNotEmpty) {
        visitorName = payload['name'].toString();
      }

      final visitorUserId = await _resolveVisitorUserId(
        supabase: supabase,
        payload: payload,
      );
      final burialId = payload['burialId'];
      final deceasedName = payload['deceasedName'];
      final lotNumber = payload['lotNumber'];

      debugPrint('Extracted visitorName: $visitorName');
      debugPrint('Extracted visitorUserId: $visitorUserId');

      if (visitorUserId == null) {
        setState(() {
          _scanMessage = 'Invalid QR code: no matching visitor profile found';
          _messageColor = _error;
        });
        return;
      }

      final created = await _createVisitorLog(
        supabase: supabase,
        visitorId: visitorUserId,
        visitorName: visitorName,
        burialId: burialId,
        deceasedName: deceasedName?.toString(),
        lotNumber: lotNumber?.toString(),
      );

      if (!created) return;

      setState(() {
        _scanMessage = burialId != null
            ? '$visitorName checked in to visit $deceasedName (Lot $lotNumber)'
            : '$visitorName checked in';
        _messageColor = _primary;
      });

      await _loadTodayVisitors();
    } catch (e) {
      debugPrint('Scan error: $e');
      setState(() {
        _scanMessage = 'Error: $e';
        _messageColor = _error;
      });
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _scanMessage = null;
        });
      });
    }
  }

  Future<bool> _createVisitorLog({
    required SupabaseClient supabase,
    required String visitorId,
    required String visitorName,
    required dynamic burialId,
    required String? deceasedName,
    required String? lotNumber,
  }) async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    try {
      final existingCheckin = await supabase
          .from('visitor_log')
          .select('log_id')
          .eq('user_id', visitorId)
          .gte('time_in', '$today 00:00:00')
          .maybeSingle();

      if (existingCheckin != null) {
        setState(() {
          _scanMessage = '$visitorName already checked in today';
          _messageColor = _warning;
        });
        return false;
      }

      await supabase.from('visitor_log').insert({
        'user_id': visitorId,
        'burial_id': burialId,
        'time_in': now.toIso8601String(),
        'method': 'QR',
      });

      final currentUser = supabase.auth.currentUser;
      await supabase.from('audit_log').insert({
        'user_email': currentUser?.email,
        'user_role': 'gate_officer',
        'action': 'SCAN_QR',
        'entity_type': 'visitor_log',
        'details':
            'Scanned QR for $visitorName${deceasedName != null ? ' visiting $deceasedName' : ''}',
        'created_at': now.toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Direct insert failed, falling back to function: $e');

      final response = await supabase.functions.invoke(
        'visitor-checkin',
        body: {
          'visitorId': visitorId,
          'visitorName': visitorName,
          'burialId': burialId,
          'deceasedName': deceasedName,
          'lotNumber': lotNumber,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          throw Exception(data['error']);
        }

        if (data['alreadyCheckedIn'] == true) {
          setState(() {
            _scanMessage =
                data['message']?.toString() ??
                '$visitorName already checked in today';
            _messageColor = _warning;
          });
          return false;
        }
      }

      return true;
    }
  }

  Future<String?> _resolveVisitorUserId({
    required SupabaseClient supabase,
    required Map<String, dynamic> payload,
  }) async {
    final explicitId = payload['visitorUserId'] ?? payload['userId'];
    if (explicitId != null && explicitId.toString().trim().isNotEmpty) {
      return explicitId.toString();
    }

    final visitorEmail =
        payload['visitorEmail'] ?? payload['email'] ?? payload['displayEmail'];
    if (visitorEmail == null || visitorEmail.toString().trim().isEmpty) {
      return null;
    }

    final user = await supabase
        .from('users')
        .select('user_id')
        .eq('email', visitorEmail.toString().trim())
        .maybeSingle();

    final userId = user?['user_id'];
    if (userId == null || userId.toString().trim().isEmpty) {
      return null;
    }

    return userId.toString();
  }

  void _clearScanResult() {
    setState(() {
      _lastPayload = null;
      _scanMessage = null;
    });
  }

  String _visitorDisplayName() {
    return _lastPayload?['visitorName']?.toString().trim().isNotEmpty == true
        ? _lastPayload!['visitorName'].toString()
        : _lastPayload?['displayName']?.toString().trim().isNotEmpty == true
        ? _lastPayload!['displayName'].toString()
        : _lastPayload?['name']?.toString().trim().isNotEmpty == true
        ? _lastPayload!['name'].toString()
        : 'Unknown Visitor';
  }

  String _visitTypeLabel() {
    return _lastPayload?['blockName']?.toString().trim().isNotEmpty == true
        ? _lastPayload!['blockName'].toString()
        : _lastPayload?['sectionName']?.toString().trim().isNotEmpty == true
        ? _lastPayload!['sectionName'].toString()
        : _lastPayload?['lotNumber']?.toString().trim().isNotEmpty == true
        ? 'Lot ${_lastPayload!['lotNumber']}'
        : 'N/A';
  }

  String _loggedTime() {
    return DateFormat('h:mm a').format(DateTime.now());
  }

  String _visitorInitial() {
    final name = _visitorDisplayName().trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }

  Map<String, dynamic>? _tryDecodeJson(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) {
        debugPrint('Successfully decoded QR');
        return value;
      }
      return null;
    } catch (e) {
      debugPrint('Failed to decode QR: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: const Color(0x1A000000),
          titleSpacing: 0,
          leading: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.qr_code_scanner_rounded, color: _primary),
          ),
          leadingWidth: 40,
          title: const Text(
            'Gate Officer',
            style: TextStyle(
              color: _primary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
              color: _error,
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            indicatorColor: _primary,
            labelColor: _primary,
            unselectedLabelColor: _onSurface,
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner'),
              Tab(icon: Icon(Icons.history), text: "Today's Visitors"),
            ],
          ),
        ),
        body: TabBarView(children: [_buildScannerTab(), _buildVisitorsTab()]),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _controller.toggleTorch(),
          backgroundColor: _primaryContainer,
          foregroundColor: Colors.white,
          child: const Icon(Icons.flash_on),
        ),
      ),
    );
  }

  Widget _buildScannerTab() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  if (_isProcessing) return;
                  final raw = capture.barcodes.isEmpty
                      ? null
                      : capture.barcodes.first.rawValue;
                  if (raw == null) return;
                  final decoded = _tryDecodeJson(raw);
                  if (decoded != null) {
                    _handleScan(decoded);
                  }
                },
              ),
              Container(
                margin: const EdgeInsets.all(60),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'Position QR code here',
                    style: TextStyle(
                      color: Colors.white,
                      backgroundColor: Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              if (_isProcessing)
                Container(
                  color: Colors.black87,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Processing...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_scanMessage != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _messageColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _messageColor),
            ),
            child: Row(
              children: [
                Icon(
                  _messageColor == _primary ? Icons.check_circle : Icons.error,
                  color: _messageColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _scanMessage!,
                    style: TextStyle(color: _messageColor),
                  ),
                ),
              ],
            ),
          ),
        if (_lastPayload != null && !_isProcessing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _surfaceVariant),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _messageColor == _primary
                              ? Icons.check_circle_rounded
                              : _messageColor == _warning
                              ? Icons.info_rounded
                              : Icons.error_rounded,
                          color: _messageColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _messageColor == _primary
                                  ? 'Confirmed'
                                  : _messageColor == _warning
                                  ? 'Needs Attention'
                                  : 'Scan Result',
                              style: const TextStyle(
                                color: _onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _messageColor == _primary
                                  ? 'Gate Access Authorized'
                                  : _scanMessage ?? 'Visitor details ready',
                              style: const TextStyle(
                                color: _onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _clearScanResult,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3F0),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _primaryFixed,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _visitorInitial(),
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VISITOR NAME',
                                style: TextStyle(
                                  color: Color(0xFF5A6D7B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _visitorDisplayName(),
                                style: const TextStyle(
                                  color: _onSurface,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_lastPayload?['deceasedName'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Visiting ${_lastPayload!['deceasedName']}',
                                  style: const TextStyle(
                                    color: _onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ScanStatTile(
                          title: 'Time Logged',
                          value: _loggedTime(),
                          icon: Icons.schedule_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ScanStatTile(
                          title: 'Block',
                          value: _visitTypeLabel(),
                          icon: Icons.map_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVisitorsTab() {
    if (_isLoadingVisitors) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }

    if (_todayVisitors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No visitors today',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTodayVisitors,
      color: _primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _todayVisitors.length,
        itemBuilder: (context, index) {
          final log = _todayVisitors[index];
          final user = log['user'] ?? {};
          final burial = log['burial'] ?? {};
          final lot = burial['cemetery_lot'] ?? {};

          final timeIn = log['time_in'] != null
              ? DateFormat('h:mm a').format(DateTime.parse(log['time_in']))
              : 'Unknown time';

          return Card(
            color: _surface,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _surfaceVariant),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _primary.withValues(alpha: 0.1),
                child: const Icon(Icons.qr_code, color: _primary),
              ),
              title: Text(
                user['name'] ?? 'Unknown Visitor',
                style: const TextStyle(
                  color: _onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (burial['name_of_deceased'] != null)
                    Text('Visiting: ${burial['name_of_deceased']}'),
                  if (lotReference(lot, fallback: '').isNotEmpty)
                    Text('Lot ${lotReference(lot)} - ${lotBlockLabel(lot)}'),
                  Text(
                    'Time: $timeIn',
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              trailing: Chip(
                label: const Text('QR'),
                labelStyle: const TextStyle(color: _primary),
                backgroundColor: _primary.withValues(alpha: 0.1),
                side: BorderSide.none,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScanStatTile extends StatelessWidget {
  const _ScanStatTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3F0),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF5A6D7B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF335538)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1B1C1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
