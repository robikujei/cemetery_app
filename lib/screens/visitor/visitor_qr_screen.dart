import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class _C {
  static const background          = Color(0xFFFBF9F6);
  static const primary             = Color(0xFF335538);
  static const primaryContainer    = Color(0xFF4B6E4F);
  static const onPrimaryContainer  = Color(0xFFC7EFC8);
  static const primaryFixed        = Color(0xFFC5EDC6);
  static const secondaryContainer  = Color(0xFFC7E4F3);
  static const secondary           = Color(0xFF47626F);
  static const surfaceContainerLow = Color(0xFFF5F3F0);
  static const surfaceVariant      = Color(0xFFE4E2DF);
  static const outlineVariant      = Color(0xFFC2C8BF);
  static const onSurface           = Color(0xFF1B1C1A);
  static const onSurfaceVariant    = Color(0xFF424841);
  static const outline             = Color(0xFF727971);
  static const white               = Color(0xFFFFFFFF);
  static const error               = Color(0xFFBA1A1A);
}

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
  bool _isSaving = false;
  String? _errorMessage;
  DateTime? _checkInTime;

  // Captures only the QR card for saving
  final GlobalKey _qrKey = GlobalKey();

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

      final userData = await supabase
          .from('users')
          .select('user_id, name, email')
          .eq('email', user.email!)
          .maybeSingle();

      final now = DateTime.now();
      if (userData != null) {
        _userName = userData['name'] ?? 'Visitor';
        _userEmail = userData['email'] ?? user.email!;
        _qrData = jsonEncode({
          'visitorId': user.id,
          'visitorUserId': userData['user_id'],
          'displayName': _userName,
          'email': _userEmail,
          'timestamp': now.toIso8601String(),
          'type': 'visitor_checkin',
        });
      } else {
        _userName = user.email?.split('@').first ?? 'Visitor';
        _userEmail = user.email ?? '';
        _qrData = jsonEncode({
          'visitorId': user.id,
          'visitorUserId': null,
          'displayName': _userName,
          'email': _userEmail,
          'timestamp': now.toIso8601String(),
          'type': 'visitor_checkin',
        });
      }
      _checkInTime = now;
    } catch (e) {
      setState(() => _errorMessage = 'Error loading data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshQrCode() async {
    await _loadUserData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('QR code refreshed!'),
          backgroundColor: _C.primaryContainer,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // Helper to check if running on mobile platform
  bool get _isMobilePlatform {
    // For web, always return false
    if (identical(0, 0.0)) {
      // This is a web-specific check
      return false;
    }
    return true;
  }

  Future<void> _saveQrToDevice() async {
    if (_isSaving) return;
    
    // Check if running on web - show unsupported message
    if (!_isMobilePlatform) {
      _showSnackBar('Save to device is not supported on web. Please use a mobile device.', isError: true);
      return;
    }
    
    setState(() => _isSaving = true);

    try {
      // Request storage permission on Android (only when actually needed)
      // Use a try-catch to handle when permission_handler is not available
      try {
        if (await Permission.storage.request().isGranted) {
          // Permission granted, continue
        } else {
          _showSnackBar('Storage permission denied.', isError: true);
          return;
        }
      } catch (e) {
        // If permission_handler fails, try to save anyway (iOS might not need permission)
        print('Permission check failed, attempting save anyway: $e');
      }

      // Capture RepaintBoundary as PNG
      final boundary = _qrKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _showSnackBar('Could not capture QR code.', isError: true);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showSnackBar('Failed to encode image.', isError: true);
        return;
      }

      // Save to gallery
      final result = await ImageGallerySaver.saveImage(
        byteData.buffer.asUint8List(),
        quality: 100,
        name:
            'eternal_rest_qr_${DateTime.now().millisecondsSinceEpoch}',
      );

      final success =
          result['isSuccess'] == true || result['filePath'] != null;
      _showSnackBar(success
          ? 'QR code saved to your gallery!'
          : 'Failed to save QR code.',
          isError: !success);
    } catch (e) {
      _showSnackBar('Error saving QR code: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _C.error : _C.primaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatCheckInTime(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final hour =
        dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return 'Check-in: ${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour:$minute $period';
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.white.withOpacity(0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 4,
        title: Row(
          children: const [
            Icon(Icons.church, color: _C.primaryContainer, size: 20),
            SizedBox(width: 8),
            Text(
              'Eternal Rest',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _C.primaryContainer,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: _C.primaryContainer, size: 22),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1, thickness: 1, color: Colors.grey.shade100),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _C.primary))
          : _errorMessage != null
              ? _buildErrorWidget()
              : _buildQrContent(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: _C.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: _C.error, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loadUserData,
              style: FilledButton.styleFrom(
                backgroundColor: _C.primaryContainer,
                foregroundColor: _C.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // ── Page title ───────────────────────────────────────
                const Text(
                  'Visitor Pass',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w400,
                    color: _C.primary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Welcome to Eternal Rest Cemetery & Gardens.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: _C.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // ── QR Card (wrapped in RepaintBoundary for saving) ──
                RepaintBoundary(
                  key: _qrKey,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _C.white,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: _C.outlineVariant),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F335538),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // Decorative green circle accent (top-right)
                        Positioned(
                          top: -64,
                          right: -64,
                          child: Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              color: _C.primary.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              // ── User info block ──────────────────
                              Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: _C.secondaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.person_rounded,
                                        color: _C.secondary,
                                        size: 32),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _userName,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w500,
                                            color: _C.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatCheckInTime(
                                              _checkInTime),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.1,
                                            color: _C.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),
                              const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _C.surfaceVariant),
                              const SizedBox(height: 24),

                              // ── QR code with primaryFixed border ─
                              if (_qrData != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _C.white,
                                    border: Border.all(
                                        color: _C.primaryFixed,
                                        width: 4),
                                    borderRadius:
                                        BorderRadius.circular(24),
                                  ),
                                  child: QrImageView(
                                    data: _qrData!,
                                    version: QrVersions.auto,
                                    size: 220,
                                    backgroundColor: _C.white,
                                    eyeStyle: const QrEyeStyle(
                                      color: _C.primary,
                                      eyeShape: QrEyeShape.square,
                                    ),
                                    dataModuleStyle:
                                        const QrDataModuleStyle(
                                      color: _C.primary,
                                      dataModuleShape:
                                          QrDataModuleShape.square,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // "Valid for Entry" pill
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _C.primaryFixed
                                        .withOpacity(0.2),
                                    borderRadius:
                                        BorderRadius.circular(40),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.verified_rounded,
                                          color: _C.primary, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'VALID FOR ENTRY',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 1.0,
                                          color: _C.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              // ── Instruction block ────────────────
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _C.surfaceContainerLow,
                                  borderRadius:
                                      BorderRadius.circular(24),
                                ),
                                child: Column(
                                  children: const [
                                    Text(
                                      'Present this QR code at the entrance',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.15,
                                        color: _C.onSurfaceVariant,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Our staff will scan this to confirm your visit',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                        color: _C.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Save to Device button ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveQrToDevice,
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.primaryContainer,
                      foregroundColor: _C.onPrimaryContainer,
                      disabledBackgroundColor:
                          _C.primaryContainer.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _C.onPrimaryContainer),
                          )
                        : const Icon(Icons.download_rounded, size: 20),
                    label:
                        Text(_isSaving ? 'Saving...' : 'Save to Device'),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
