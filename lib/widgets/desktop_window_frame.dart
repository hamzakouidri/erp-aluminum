import 'dart:io';

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

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWindowState());
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

  Future<void> _readWindowState() async {
    try {
      final bounds = await windowManager.getBounds();
      final isMax = await windowManager.isMaximized();
      final effectivelyMax =
          isMax && (bounds.width >= 1400 || bounds.height >= 900);
      if (mounted && _isMaximized != effectivelyMax) {
        setState(() => _isMaximized = effectivelyMax);
      }
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    try {
      final bounds = await windowManager.getBounds();
      final isMax = await windowManager.isMaximized();
      final effectivelyMax =
          isMax && (bounds.width >= 1400 || bounds.height >= 900);
      if (effectivelyMax) {
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
  void onWindowClose() async {
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _closeApp() async {
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _toggleFullScreen() async {
    final next = !_isFullScreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullScreen = next);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: Localization.translate(
        'ورشتي',
        Provider.of<AppSettingsProvider>(context, listen: false).language,
      ),
      applicationVersion: Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).appVersion,
      applicationIcon: Image.asset(
        'web/favicon.png',
        width: 54,
        height: 54,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF172033);
    final background = isDark ? const Color(0xFF111827) : Colors.white;

    return Column(
      children: [
        Material(
          color: background,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
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
                  width: 142,
                  child: DragToMoveArea(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _toggleMaximize,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 14),
                        child: Row(
                          children: [
                            Image.asset(
                              'web/favicon.png',
                              width: 23,
                              height: 23,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.window_rounded,
                                size: 18,
                                color: Color(0xFF2563EB),
                              ),
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
                _DesktopMenu(
                  label: 'Fichier',
                  items: [
                    _DesktopMenuItem(
                      label: Localization.translate('إغلاق التطبيق', lang),
                      icon: Icons.logout_rounded,
                      onSelected: _closeApp,
                    ),
                  ],
                ),
                _DesktopMenu(
                  label: 'Modifier',
                  items: [
                    _DesktopMenuItem(
                      label: Localization.translate('تراجع', lang),
                      icon: Icons.undo_rounded,
                      onSelected: () => Actions.maybeInvoke(
                        context,
                        const UndoTextIntent(SelectionChangedCause.keyboard),
                      ),
                    ),
                    _DesktopMenuItem(
                      label: Localization.translate('إعادة', lang),
                      icon: Icons.redo_rounded,
                      onSelected: () => Actions.maybeInvoke(
                        context,
                        const RedoTextIntent(SelectionChangedCause.keyboard),
                      ),
                    ),
                  ],
                ),
                _DesktopMenu(
                  label: 'Affichage',
                  items: [
                    _DesktopMenuItem(
                      label: isDark ? 'Mode clair' : 'Mode sombre',
                      icon: isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      onSelected: () => Provider.of<AppSettingsProvider>(
                        context,
                        listen: false,
                      ).setTheme(isDark ? ThemeMode.light : ThemeMode.dark),
                    ),
                    _DesktopMenuItem(
                      label: _isFullScreen
                          ? 'Quitter le plein écran'
                          : 'Plein écran',
                      icon: _isFullScreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      onSelected: _toggleFullScreen,
                    ),
                  ],
                ),
                _DesktopMenu(
                  label: 'Aide',
                  items: [
                    _DesktopMenuItem(
                      label: 'À propos',
                      icon: Icons.info_outline_rounded,
                      onSelected: _showAbout,
                    ),
                  ],
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
                  iconBuilder: (_) =>
                      Container(width: 10, height: 1.2, color: foreground),
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
                  onPressed: _closeApp,
                ),
              ],
            ),
          ),
        ),
        if (widget.topBar != null)
          Material(
            color: background,
            child: SizedBox(height: 42, child: widget.topBar!),
          ),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildMaximizeIcon(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(border: Border.all(color: color, width: 1.2)),
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

class _DesktopMenuItem {
  const _DesktopMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

class _DesktopMenu extends StatelessWidget {
  const _DesktopMenu({required this.label, required this.items});

  final String label;
  final List<_DesktopMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF475569);
    return PopupMenuButton<int>(
      tooltip: label,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 190),
      onSelected: (index) => items[index].onSelected(),
      itemBuilder: (context) => List.generate(items.length, (index) {
        final item = items[index];
        return PopupMenuItem<int>(
          value: index,
          height: 42,
          child: Row(
            children: [
              Icon(item.icon, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(item.label)),
            ],
          ),
        );
      }),
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
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
              child: Center(child: widget.iconBuilder(_isHovered)),
            ),
          ),
        ),
      ),
    );
  }
}
