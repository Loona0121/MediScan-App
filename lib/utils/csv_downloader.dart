import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

/// Downloads a CSV string.
///
/// - Web:    triggers a browser download.
/// - Mobile: writes the file to a temp dir and opens the OS share sheet
///           so the user can save it to Files / Drive / email it, etc.
Future<void> downloadCsv(String csvData, String filename) async {
  if (kIsWeb) {
    _downloadOnWeb(csvData, filename);
    return;
  }

  // Mobile (Android / iOS)
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(utf8.encode(csvData), flush: true);

  // share_plus 11.x — instance API.
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MediScan Inventory Report',
      text: 'MediScan inventory export — $filename',
    ),
  );
}

/// Web-only: build a Blob and click a temporary anchor to trigger
/// the browser's "Save file" dialog.
void _downloadOnWeb(String csvData, String filename) {
  final bytes = utf8.encode(csvData);
  final blob = html.Blob(
    [bytes],
    'text/csv;charset=utf-8',
  );
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);
}