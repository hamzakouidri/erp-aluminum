import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
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

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _isMaximized = false;
  ImageProvider? _workshopLogo;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWindowState());
    _loadWorkshopLogo();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    _readWindowState();
  }

  @override
  void onWindowResize() {
    _readWindowState();
  }

  Future<void> _loadWorkshopLogo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawLogo = prefs.getString('workshop_logo_base64')?.trim() ?? '';
      if (rawLogo.isEmpty) return;

      ImageProvider? logo;
      if (rawLogo.startsWith('http')) {
        logo = NetworkImage(rawLogo);
      } else {
        final encoded = rawLogo.contains(',')
            ? rawLogo.substring(rawLogo.indexOf(',') + 1)
            : rawLogo;
        final bytes = base64Decode(encoded);
        if (bytes.isNotEmpty) logo = MemoryImage(bytes);
      }

      if (mounted && logo != null) setState(() => _workshopLogo = logo);
    } catch (_) {
      // Keep the application icon as a safe fallback when no workshop logo
      // has been saved yet or when an old value is not valid image data.
    }
  }

  Future<void> _readWindowState() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (mounted && _isMaximized != isMax) {
        setState(() => _isMaximized = isMax);
      }
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (isMax) {
        await windowManager.unmaximize();
        if (mounted) setState(() => _isMaximized = false);
      } else {
        await windowManager.maximize();
        if (mounted) setState(() => _isMaximized = true);
      }
    } catch (e) {
      debugPrint('Error toggling maximize: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The custom Windows caption belongs to the authenticated workspace. The
    // login page must be allowed to occupy the whole window after sign-out;
    // otherwise only the caption and its border remain visible above it.
    if (AppAuthService().currentUser == null) return widget.child;

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
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
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
                          if (_workshopLogo != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image(
                                image: _workshopLogo!,
                                width: 20,
                                height: 20,
                                fit: BoxFit.contain,
                              ),
                            )
                          else
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
              // Keep the whole remaining caption area draggable. Interactive
              // tabs are rendered in their own row below it so a tab click can
              // never be interpreted as a native window command.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _toggleMaximize,
                  child: DragToMoveArea(child: const SizedBox.expand()),
                ),
              ),
              _CaptionButton(
                tooltip: Localization.translate('تصغير', lang),
                iconBuilder: (_) => Container(
                  width: 10,
                  height: 1.2,
                  color: foreground,
                ),
                onPressed: () => windowManager.minimize(),
              ),
              _CaptionButton(
                tooltip: Localization.translate(
                  _isMaximized ? 'استعادة الحجم' : 'تكبير',
                  lang,
                ),
                iconBuilder: (_) => _isMaximized
                    ? _buildRestoreIcon(foreground, isDark)
                    : _buildMaximizeIcon(foreground),
                onPressed: _toggleMaximize,
              ),
              _CaptionButton(
                tooltip: Localization.translate('إغلاق', lang),
                closeButton: true,
                iconBuilder: (hovered) => Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: hovered ? Colors.white : const Color(0xFFDC2626),
                ),
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
        ),
        if (widget.topBar != null)
          Container(
            height: 42,
            color: background,
            child: widget.topBar!,
          ),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildMaximizeIcon(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
      ),
    );
  }

  Widget _buildRestoreIcon(Color color, bool isDark) {
    return SizedBox(
      width: 11,
      height: 11,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.2),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : Colors.white,
                border: Border.all(color: color, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final String tooltip;
  final Widget Function(bool isHovered) iconBuilder;
  final VoidCallback onPressed;
  final bool closeButton;

  const _CaptionButton({
    required this.tooltip,
    required this.iconBuilder,
    required this.onPressed,
    this.closeButton = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.tooltip,
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: widget.closeButton && _isHovered
              ? const Color(0xFFE81123)
              : Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            hoverColor: widget.closeButton
                ? const Color(0xFFE81123)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: SizedBox(
              width: 46,
              height: double.infinity,
              child: Center(
                child: widget.iconBuilder(_isHovered),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
