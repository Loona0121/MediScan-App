import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Saves [csvData] to the app's documents directory as [filename].
/// Returns the full file path where it was saved.
Future<String> downloadCsv(String csvData, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(csvData);
  return file.path;
}