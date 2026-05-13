import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/session_providers.dart';
import '../../models/app_user.dart';

class VisitorQrScreen extends ConsumerStatefulWidget {
  const VisitorQrScreen({super.key});

  @override
  ConsumerState<VisitorQrScreen> createState() => _VisitorQrScreenState();
}

class _VisitorQrScreenState extends ConsumerState<VisitorQrScreen> {
  String? _qrData;
  String _userName = 'Visitor';
  String _userEmail = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() {
          _errorMessage = 'Please log in to view your QR code';
          _isLoading = false;
        });
        return;
      }

      // Get user details from users table
      final userData = await supabase
          .from('users')
          .select('name, email')
          .eq('email', user.email!)
          .maybeSingle();

      if (userData != null) {
        _userName = userData['name'] ?? 'Visitor';
        _userEmail = userData['email'] ?? user.email!;
        
        // Create QR code payload
        final payload = jsonEncode({
          'visitorId': user.id,
          'displayName': _userName,
          'email': _userEmail,
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'visitor_checkin',
        });
        
        _qrData = payload;
      } else {
        // If no user data in table, still generate QR with auth data
        final payload = jsonEncode({
          'visitorId': user.id,
          'displayName': user.email?.split('@').first ?? 'Visitor',
          'email': user.email,
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'visitor_checkin',
        });
        _qrData = payload;
        _userName = user.email?.split('@').first ?? 'Visitor';
        _userEmail = user.email ?? '';
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshQrCode() async {
    await _loadUserData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR code refreshed!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR Code'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshQrCode,
            tooltip: 'Refresh QR Code',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : _buildQrContent(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadUserData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4B6E4F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Welcome Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFF4B6E4F).withOpacity(0.1),
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 50,
                      color: const Color(0xFF4B6E4F),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Welcome, $_userName',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userEmail,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Show this QR code to the gate officer',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // QR Code Display
          if (_qrData != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: _qrData!,
                    version: QrVersions.auto,
                    size: 250.0,
                    eyeStyle: const QrEyeStyle(
                      color: Color(0xFF4B6E4F),
                      eyeShape: QrEyeShape.square,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: Color(0xFF4B6E4F),
                      dataModuleShape: QrDataModuleShape.square,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B6E4F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Scan to check in',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B6E4F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 24),
          
          // Instructions Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How it works',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF4B6E4F),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionTile(
                    '1',
                    'Show this QR code',
                    'Present your phone screen to the gate officer',
                  ),
                  const Divider(),
                  _buildInstructionTile(
                    '2',
                    'Gate officer scans',
                    'They will scan your QR code using their device',
                  ),
                  const Divider(),
                  _buildInstructionTile(
                    '3',
                    'Entry recorded',
                    'Your visit will be automatically logged in the system',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Note about QR code
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your QR code is unique to you. Do not share it with anyone.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionTile(String step, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF4B6E4F).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4B6E4F),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}