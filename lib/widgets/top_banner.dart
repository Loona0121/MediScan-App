import 'package:flutter/material.dart';

/// A brief, auto-dismissing banner that slides in from the TOP of the
/// screen — used in place of the default bottom-anchored SnackBar for
/// success/status messages that should be seen immediately rather than
/// competing with bottom nav bars or FABs.
class TopBanner {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    Color backgroundColor = Colors.green,
    IconData icon = Icons.check_circle,
    Duration duration = const Duration(seconds: 3),
    double? width = 320,                                  // 👈 new
    Alignment alignment = Alignment.topCenter,      // 👈 new
  }) {
    // Replace any banner already showing rather than stacking them.
    _currentEntry?.remove();

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopBannerWidget(
        message: message,
        backgroundColor: backgroundColor,
        icon: icon,
        width: width,
        alignment: alignment,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (_currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
    });
  }
}

class _TopBannerWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final double? width;
  final Alignment alignment;

  const _TopBannerWidget({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    this.width,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outer Positioned spans the full overlay width; the inner Align
    // then decides whether the fixed-width box sits centered or in a
    // corner. When `width` is null, the box stretches full width.
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: widget.alignment,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Container(
                    width: widget.width,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: widget.backgroundColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: widget.width == null
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}