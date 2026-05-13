import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VisitorQrWithGraveScreen extends ConsumerStatefulWidget {
  const VisitorQrWithGraveScreen({
    super.key,
    this.burialId,
    this.deceasedName,
    this.lotNumber,
    this.sectionName,
  });

  final int? burialId;
  final String? deceasedName;
  final String? lotNumber;
  final String? sectionName;

  @override
  ConsumerState<VisitorQrWithGraveScreen> createState() => _VisitorQrWithGraveScreenState();
}

class _VisitorQrWithGraveScreenState extends ConsumerState<VisitorQrWithGraveScreen> {
  String? _qrData;
  String _userName = 'Visitor';
  String _selectedGrave = 'No grave selected';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        final userData = await supabase
            .from('users')
            .select('name')
            .eq('email', user.email!)
            .maybeSingle();

        _userName = userData?['name'] ?? 'Visitor';
        
        // Build QR payload with grave info if selected
        final Map<String, dynamic> payload = {
          'visitorId': user.id,
          'visitorName': _userName,
          'visitorEmail': user.email,
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'visitor_checkin',
        };
        
        // Add grave info if a specific grave was selected
        if (widget.burialId != null) {
          payload['burialId'] = widget.burialId;
          payload['deceasedName'] = widget.deceasedName ?? 'Unknown';
          payload['lotNumber'] = widget.lotNumber ?? 'Unknown';
          payload['sectionName'] = widget.sectionName ?? 'Unknown';
          _selectedGrave = '${widget.deceasedName ?? 'Unknown'} (Lot ${widget.lotNumber ?? 'N/A'})';
        }
        
        _qrData = jsonEncode(payload);
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visitor QR Code'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
      ),
      body: _qrData == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.qr_code_scanner, size: 60, color: Color(0xFF4B6E4F)),
                          const SizedBox(height: 12),
                          Text(
                            _userName,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Visiting: $_selectedGrave',
                              style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _qrData!,
                      version: QrVersions.auto,
                      size: 250,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.green.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Show this QR code to the gate officer. They will scan it to log your visit to this grave.',
                            style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Search'),
                  ),
                ],
              ),
            ),
    );
  }
}