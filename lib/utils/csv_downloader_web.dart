import 'dart:convert';
import 'dart:html' as html;

/// Triggers a browser download of [csvData] named [filename].
/// Returns a status string (no real filesystem path exists on web).
Future<String> downloadCsv(String csvData, String filename) async {
  final bytes = utf8.encode(csvData);
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return 'downloaded';
}