import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// The Windows caption area is drawn by Flutter so the window controls remain
/// visible even when the pointer is not hovering over the title bar.
class DesktopWindowFrame extends StatefulWidget {
  final Widget child;
  final Widget? topBar;

  const DesktopWindowFrame({super.key, required this.child, this.topBar});

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWindowState());
  }

  Future<void> _readWindowState() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = isMaximized);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _readWindowState();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF172033);
    final background = isDark ? const Color(0xFF111827) : Colors.white;

    return Column(
      children: [
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: background,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 132,
                child: DragToMoveArea(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _toggleMaximize,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.window_rounded,
                            size: 18,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            Localization.translate('ورشتي', lang),
                            style: TextStyle(
                              color: foreground,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.topBar != null)
                Expanded(child: widget.topBar!)
              else
                Expanded(child: DragToMoveArea(child: const SizedBox.expand())),
              _CaptionButton(
                tooltip: Localization.translate('تصغير', lang),
                icon: Icons.remove_rounded,
                foreground: foreground,
                onPressed: () => windowManager.minimize(),
              ),
              _CaptionButton(
                tooltip: Localization.translate(
                  _isMaximized ? 'استعادة الحجم' : 'تكبير',
                  lang,
                ),
                icon: _isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                foreground: foreground,
                onPressed: _toggleMaximize,
              ),
              _CaptionButton(
                tooltip: Localization.translate('إغلاق', lang),
                icon: Icons.close_rounded,
                foreground: const Color(0xFFDC2626),
                closeButton: true,
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _CaptionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color foreground;
  final VoidCallback onPressed;
  final bool closeButton;

  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.onPressed,
    this.closeButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // This frame wraps MaterialApp's navigator, so it is intentionally above
    // Flutter's Overlay.  Semantics keeps the buttons accessible without a
    // Tooltip, which would otherwise throw "No Overlay widget found".
    return Semantics(
      label: tooltip,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: closeButton
              ? const Color(0xFFFEE2E2)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          child: SizedBox(
            width: 46,
            height: double.infinity,
            child: Icon(icon, color: foreground, size: 20),
          ),
        ),
      ),
    );
  }
}
