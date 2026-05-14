import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController();
  Map<String, dynamic>? _lastPayload;
  bool _isProcessing = false;
  String? _scanMessage;
  Color _messageColor = Colors.green;
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
            burial:burial_id (name_of_deceased, cemetery_lot (lot_number, section:section_id (name)))
          ''')
          .gte('time_in', '$today 00:00:00')
          .lte('time_in', '$today 23:59:59')
          .order('time_in', ascending: false);
      
      setState(() {
        _todayVisitors = List<Map<String, dynamic>>.from(result);
        _isLoadingVisitors = false;
      });
    } catch (e) {
      setState(() => _isLoadingVisitors = false);
      print('Error loading visitors: $e');
    }
  }

  Future<void> _handleScan(Map<String, dynamic> payload) async {
    if (_isProcessing) return;
    
    // Debug: Print the entire payload to see what we're getting
    print('=== SCANNED QR PAYLOAD ===');
    print('Full payload: $payload');
    print('visitorName: ${payload['visitorName']}');
    print('visitorId: ${payload['visitorId']}');
    print('burialId: ${payload['burialId']}');
    print('deceasedName: ${payload['deceasedName']}');
    
    setState(() {
      _isProcessing = true;
      _scanMessage = null;
      _lastPayload = payload;
    });

    try {
      final supabase = Supabase.instance.client;
      
      // Extract visitor name - try multiple possible field names
      String visitorName = 'Unknown';
      if (payload['visitorName'] != null && payload['visitorName'].toString().isNotEmpty) {
        visitorName = payload['visitorName'];
      } else if (payload['displayName'] != null && payload['displayName'].toString().isNotEmpty) {
        visitorName = payload['displayName'];
      } else if (payload['name'] != null && payload['name'].toString().isNotEmpty) {
        visitorName = payload['name'];
      }
      
      final visitorId = payload['visitorId'];
      final burialId = payload['burialId'];
      final deceasedName = payload['deceasedName'];
      final lotNumber = payload['lotNumber'];
      
      print('Extracted visitorName: $visitorName');
      print('Extracted visitorId: $visitorId');
      
      if (visitorId == null) {
        setState(() {
          _scanMessage = '❌ Invalid QR code: No visitor ID found';
          _messageColor = Colors.red;
        });
        return;
      }
      
      // Check if already checked in today
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final existingCheckin = await supabase
          .from('visitor_log')
          .select('log_id')
          .eq('user_id', visitorId)
          .gte('time_in', '$today 00:00:00')
          .maybeSingle();
      
      if (existingCheckin != null) {
        setState(() {
          _scanMessage = '⚠️ $visitorName already checked in today';
          _messageColor = Colors.orange;
        });
        return;
      }
      
      // Save to visitor_log
      await supabase.from('visitor_log').insert({
        'user_id': visitorId,
        'burial_id': burialId,
        'time_in': DateTime.now().toIso8601String(),
        'method': 'QR',
      });
      
      // Add audit log
      final currentUser = supabase.auth.currentUser;
      await supabase.from('audit_log').insert({
        'user_email': currentUser?.email,
        'user_role': 'gate_officer',
        'action': 'SCAN_QR',
        'entity_type': 'visitor_log',
        'details': 'Scanned QR for $visitorName${deceasedName != null ? ' visiting $deceasedName' : ''}',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      setState(() {
        _scanMessage = burialId != null 
            ? '✅ $visitorName checked in to visit $deceasedName (Lot $lotNumber)'
            : '✅ $visitorName checked in';
        _messageColor = Colors.green;
      });
      
      // Refresh visitor list
      await _loadTodayVisitors();
      
    } catch (e) {
      print('❌ Scan error: $e');
      setState(() {
        _scanMessage = '❌ Error: $e';
        _messageColor = Colors.red;
      });
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _scanMessage = null;
          });
        }
      });
    }
  }

  Map<String, dynamic>? _tryDecodeJson(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) {
        print('✅ Successfully decoded QR');
        return v;
      }
      return null;
    } catch (e) {
      print('❌ Failed to decode QR: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gate Officer'),
          backgroundColor: const Color(0xFF4B6E4F),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner'),
              Tab(icon: Icon(Icons.history), text: "Today's Visitors"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildScannerTab(),
            _buildVisitorsTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _controller.toggleTorch();
          },
          backgroundColor: const Color(0xFF4B6E4F),
          child: const Icon(Icons.flash_on, color: Colors.white),
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
                  final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
                  if (raw == null) return;
                  final decoded = _tryDecodeJson(raw);
                  if (decoded != null) {
                    _handleScan(decoded);
                  }
                },
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                margin: const EdgeInsets.all(60),
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
                        CircularProgressIndicator(),
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
              color: _messageColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _messageColor),
            ),
            child: Row(
              children: [
                Icon(_messageColor == Colors.green ? Icons.check_circle : Icons.error,
                    color: _messageColor),
                const SizedBox(width: 12),
                Expanded(child: Text(_scanMessage!, style: TextStyle(color: _messageColor))),
              ],
            ),
          ),
        
        if (_lastPayload != null && !_isProcessing)
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Scan',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('Visitor: ${_lastPayload?['visitorName'] ?? 'Unknown'}'),
                    if (_lastPayload?['deceasedName'] != null)
                      Text('Visiting: ${_lastPayload?['deceasedName']}'),
                    if (_lastPayload?['lotNumber'] != null)
                      Text('Lot: ${_lastPayload?['lotNumber']}'),
                    Text('Time: ${DateFormat('h:mm a').format(DateTime.now())}'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVisitorsTab() {
    if (_isLoadingVisitors) {
      return const Center(child: CircularProgressIndicator());
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
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _todayVisitors.length,
        itemBuilder: (context, index) {
          final log = _todayVisitors[index];
          final user = log['user'] ?? {};
          final burial = log['burial'] ?? {};
          final lot = burial['cemetery_lot'] ?? {};
          final section = lot['section'] ?? {};
          
          final timeIn = log['time_in'] != null
              ? DateFormat('h:mm a').format(DateTime.parse(log['time_in']))
              : 'Unknown time';
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF4B6E4F).withOpacity(0.1),
                child: const Icon(Icons.qr_code, color: Color(0xFF4B6E4F)),
              ),
              title: Text(user['name'] ?? 'Unknown Visitor'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (burial['name_of_deceased'] != null)
                    Text('Visiting: ${burial['name_of_deceased']}'),
                  if (lot['lot_number'] != null)
                    Text('Lot ${lot['lot_number']} • Section ${section['name'] ?? 'N/A'}'),
                  Text('Time: $timeIn'),
                ],
              ),
              trailing: Chip(
                label: const Text('QR'),
                backgroundColor: Colors.green.withOpacity(0.1),
              ),
            ),
          );
        },
      ),
    );
  }
}