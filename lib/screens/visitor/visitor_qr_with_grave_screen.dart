import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

class _C {
  static const background = Color(0xFFFBF9F6);
  static const primary = Color(0xFF335538);
  static const primaryContainer = Color(0xFF4B6E4F);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onPrimaryContainer = Color(0xFFC7EFC8);
  static const primaryFixed = Color(0xFFC5EDC6);
  static const secondaryFixed = Color(0xFFCAE7F6);
  static const secondary = Color(0xFF47626F);
  static const tertiaryFixed = Color(0xFFF5DECE);
  static const tertiary = Color(0xFF5A4B3F);
  static const secondaryContainer = Color(0xFFC7E4F3);
  static const onSecondaryContainer = Color(0xFF4B6673);
  static const surfaceContainerLow = Color(0xFFF5F3F0);
  static const surfaceContainerHigh = Color(0xFFEAE8E5);
  static const surfaceContainer = Color(0xFFEFEEEB);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFE4E2DF);
  static const onSurface = Color(0xFF1B1C1A);
  static const onSurfaceVariant = Color(0xFF424841);
  static const outline = Color(0xFF727971);
  static const outlineVariant = Color(0xFFC2C8BF);
  static const white = Color(0xFFFFFFFF);
  static const error = Color(0xFFBA1A1A);
}

class VisitorQrWithGraveScreen extends ConsumerStatefulWidget {
  const VisitorQrWithGraveScreen({
    super.key,
    this.burialId,
    this.deceasedName,
    this.lotNumber,
    this.blockName,
    this.sectionName,
  });

  final int? burialId;
  final String? deceasedName;
  final String? lotNumber;
  final String? blockName;
  final String? sectionName;

  @override
  ConsumerState<VisitorQrWithGraveScreen> createState() =>
      _VisitorQrWithGraveScreenState();
}

class _VisitorQrWithGraveScreenState
    extends ConsumerState<VisitorQrWithGraveScreen> {
  String? _qrData;
  String _userName = 'Visitor';
  String _selectedGrave = 'No grave selected';
  bool _isLoading = true;
  String? _errorMessage;

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
          _errorMessage = 'Please log in to generate QR code';
          _isLoading = false;
        });
        return;
      }

      final userData = await supabase
          .from('users')
          .select('user_id, name')
          .eq('email', user.email!)
          .maybeSingle();

      _userName =
          userData?['name'] ?? user.email?.split('@').first ?? 'Visitor';

      final Map<String, dynamic> payload = {
        'visitorId': user.id,
        'visitorUserId': userData?['user_id'],
        'visitorName': _userName,
        'visitorEmail': user.email,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'visitor_checkin',
      };

      if (widget.burialId != null) {
        payload['burialId'] = widget.burialId;
        payload['deceasedName'] = widget.deceasedName ?? 'Unknown';
        payload['lotNumber'] = widget.lotNumber ?? 'Unknown';
        payload['blockName'] =
            widget.blockName ?? widget.sectionName ?? 'Unknown';

        _selectedGrave =
            '${widget.deceasedName ?? 'Unknown'} (Lot ${widget.lotNumber ?? 'N/A'})';
      }

      _qrData = jsonEncode(payload);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveQrCode() async {
    try {
      RenderRepaintBoundary boundary =
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final fileName =
          'visitor_qr_${DateTime.now().millisecondsSinceEpoch}.png';

      final result = await ImageGallerySaver.saveImage(
        pngBytes,
        quality: 100,
        name: fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('QR Code saved to device'),
            backgroundColor: _C.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving QR code: $e'),
            backgroundColor: _C.error,
          ),
        );
      }
    }
  }

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
          onPressed: () => Navigator.pop(context),
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
            icon: const Icon(Icons.refresh, color: _C.primaryContainer),
            onPressed: _loadUserData,
          ),
          IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
              color: _C.primaryContainer,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : _errorMessage != null
          ? _buildErrorWidget()
          : _qrData == null
          ? _buildNoQrWidget()
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
              style: const TextStyle(fontSize: 16, color: _C.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoQrWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_scanner,
            size: 80,
            color: _C.outline.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Unable to generate QR code',
            style: TextStyle(fontSize: 16, color: _C.outline),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: _C.primary,
              foregroundColor: _C.onPrimary,
            ),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Column(
          children: [
            // Welcome Section
            Column(
              children: const [
                Text(
                  'Visitor Pass',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w400,
                    color: _C.primary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Welcome to Eternal Rest Cemetery & Gardens.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _C.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Main Card
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _C.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: _C.outlineVariant),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14335538),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -60,
                    right: -60,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: _C.primary.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),

                  Column(
                    children: [
                      // User Info
                      Container(
                        padding: const EdgeInsets.only(bottom: 16),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: _C.surfaceVariant),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: _C.secondaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person,
                                size: 34,
                                color: _C.secondary,
                              ),
                            ),

                            const SizedBox(width: 16),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w500,
                                      color: _C.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedGrave,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _C.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // QR
                      Column(
                        children: [
                          RepaintBoundary(
                            key: _qrKey,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: _C.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: _C.primaryFixed,
                                  width: 4,
                                ),
                              ),
                              child: QrImageView(
                                data: _qrData!,
                                version: QrVersions.auto,
                                size: 240,
                                eyeStyle: const QrEyeStyle(
                                  color: _C.primary,
                                  eyeShape: QrEyeShape.square,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  color: _C.primary,
                                  dataModuleShape: QrDataModuleShape.square,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _C.primaryFixed.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.verified,
                                  size: 18,
                                  color: _C.primary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'VALID FOR ENTRY',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: _C.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Instructions
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _C.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: const [
                            Text(
                              'Present this QR code at the entrance',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
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
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveQrCode,
                style: FilledButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: _C.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Save to Device'),
              ),
            ),

            const SizedBox(height: 12),

            // Back Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _C.primary,
                  side: const BorderSide(color: _C.outlineVariant),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to Search'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
