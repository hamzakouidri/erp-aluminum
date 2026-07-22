import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Providers/workspace_provider.dart';
import '../Screen/welcom_screen.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final workspace = Provider.of<WorkspaceProvider>(context, listen: false);
      if (workspace.tabs.isEmpty) {
        workspace.openTab(
          WorkspaceTab(
            id: 'dashboard',
            title: 'Home',
            icon: Icons.dashboard_rounded,
            widget: const WelcomScreen(),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkspaceProvider>(
      builder: (context, workspace, child) {
        if (workspace.tabs.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFE2E8F0),
          appBar: AppBar(
            backgroundColor: const Color(
              0xFF1E293B,
            ), // Dark toolbar like Chrome
            elevation: 0,
            titleSpacing: 0,
            toolbarHeight: 50,
            title: SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: workspace.tabs.length,
                padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
                itemBuilder: (context, index) {
                  final tab = workspace.tabs[index];
                  final isActive = index == workspace.activeTabIndex;

                  return GestureDetector(
                    onTap: () => workspace.setActiveTab(index),
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : const Color(0xFF334155),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        boxShadow: isActive
                            ? [
                                const BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, -2),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(
                            tab.icon,
                            size: 16,
                            color: isActive
                                ? const Color(0xFF2563EB)
                                : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              Localization.translate(tab.title, Provider.of<AppSettingsProvider>(context).language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? const Color(0xFF1E293B)
                                    : Colors.white70,
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (tab.id != 'dashboard')
                            InkWell(
                              onTap: () => workspace.closeTab(tab.id),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: isActive
                                      ? const Color(0xFF64748B)
                                      : Colors.white54,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          body: IndexedStack(
            index: workspace.activeTabIndex,
            children: workspace.tabs.map((t) => t.widget).toList(),
          ),
        );
      },
    );
  }
}
