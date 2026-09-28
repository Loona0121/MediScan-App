/// Appends a cache-busting query param so Flutter's ImageCache/browser
/// cache can't serve stale bytes for a URL whose underlying file changed
/// (e.g. profile photos, which get uploaded to the same storage path
/// each time a user picks a new one).
///
/// Without this, screens that render an avatar using the *same* URL
/// string as before will keep showing the old cached image even after
/// a fresh upload succeeds on the server.
String? bustCache(String? url) {
  if (url == null || url.isEmpty) return url;
  final sep = url.contains('?') ? '&' : '?';
  return '$url${sep}v=${DateTime.now().millisecondsSinceEpoch}';
}