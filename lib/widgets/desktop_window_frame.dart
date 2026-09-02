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

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  bool _isMaximized = false;
  ImageProvider? _workshopLogo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWindowState());
    _loadWorkshopLogo();
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
