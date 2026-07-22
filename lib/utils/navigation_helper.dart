import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Providers/workspace_provider.dart';
import '../settings/app_settings.dart';

class NavigationHelper {
  static void openScreen({
    required BuildContext context,
    required String id,
    required String title,
    required IconData icon,
    required Widget screenWidget,
  }) {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);

    if (settings.viewMode == AppViewMode.tabs) {
      // Open as a tab
      final workspace = Provider.of<WorkspaceProvider>(context, listen: false);
      workspace.openTab(
        WorkspaceTab(id: id, title: title, icon: icon, widget: screenWidget),
      );
    } else {
      // Classic Navigation
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, a, _) => screenWidget,
          transitionsBuilder: (_, a, _, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }
}
