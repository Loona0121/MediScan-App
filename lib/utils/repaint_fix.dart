import 'package:flutter/widgets.dart';

/// Flutter Web's CanvasKit renderer rasterizes text/icon glyphs
/// asynchronously and does not always repaint automatically once they're
/// ready — content can stay blank until the user moves the mouse or
/// clicks (see github.com/flutter/flutter/issues/94318). This is an
/// engine-level bug, not app-specific, and there is no reliable single
/// point in time to know rasterization has finished.
///
/// Call this right after any async setState that populates a list/grid
/// which gets rendered on screen (e.g. after a Supabase fetch finishes).
/// It retries a plain rebuild a few times over ~1 second so at least one
/// of them lands after CanvasKit has actually finished rasterizing.
void forceRepaintUntilPainted(State state) {
  for (final delayMs in [50, 150, 300, 600, 1000]) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (state.mounted) state.setState(() {});
    });
  }
}