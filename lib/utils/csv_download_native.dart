import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadCsv(String content, String fileName) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(content, flush: true);
  await Share.shareXFiles([
    XFile(file.path, mimeType: 'text/csv'),
  ], subject: fileName);
}
