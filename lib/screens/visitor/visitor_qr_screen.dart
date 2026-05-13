import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/session_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

class VisitorQrScreen extends ConsumerWidget {
  const VisitorQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final now = DateTime.now().toUtc();
    final payload = jsonEncode({
      'visitorId': user?.id ?? 'anonymous',
      'displayName': user?.displayName ?? 'Anonymous',
      'ts': now.toIso8601String(),
      'type': 'visitor_checkin',
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Visitor QR',
            subtitle: 'Show this at the gate for entry logging.',
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                  size: 240,
                  padding: const EdgeInsets.all(12),
                ),
                const SizedBox(height: 10),
                Text(
                  user == null ? 'Anonymous visitor' : user.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Generated ${now.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('What’s inside the QR', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SelectableText(
                  payload,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

