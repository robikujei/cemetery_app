import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://gvvbzkbdqeuyaujqrpcb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd2dmJ6a2JkcWV1eWF1anFycGNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NzM2NTEsImV4cCI6MjA5NDI0OTY1MX0.ZO9VQBSXaLBgr4OXFvMJGsZhd_p2tXYpsgeED-Z9cRA',
  );
  
  runApp(
    const ProviderScope(  // Required for Riverpod
      child: CemeteryApp(),
    ),
  );
}