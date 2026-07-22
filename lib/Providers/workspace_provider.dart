import 'package:flutter/material.dart';

class WorkspaceTab {
  final String id;
  final String title;
  final IconData icon;
  final Widget widget;

  WorkspaceTab({
    required this.id,
    required this.title,
    required this.icon,
    required this.widget,
  });
}

class WorkspaceProvider extends ChangeNotifier {
  final List<WorkspaceTab> _tabs = [];
  int _activeTabIndex = -1;

  List<WorkspaceTab> get tabs => _tabs;
  int get activeTabIndex => _activeTabIndex;

  WorkspaceTab? get activeTab =>
      (_activeTabIndex >= 0 && _activeTabIndex < _tabs.length)
      ? _tabs[_activeTabIndex]
      : null;

  void openTab(WorkspaceTab tab) {
    // Check if a tab with the same ID already exists
    final index = _tabs.indexWhere((t) => t.id == tab.id);
    if (index != -1) {
      // Just focus on it
      _activeTabIndex = index;
    } else {
      // Add new tab and focus
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  void closeTab(String id) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTabIndex = -1;
      } else if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (_activeTabIndex == index) {
        // If we closed the active tab, switch to the previous one
        if (_activeTabIndex > 0) {
          _activeTabIndex--;
        }
      } else if (_activeTabIndex > index) {
        _activeTabIndex--;
      }
      notifyListeners();
    }
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      _activeTabIndex = index;
      notifyListeners();
    }
  }

  void clearTabs() {
    _tabs.clear();
    _activeTabIndex = -1;
    notifyListeners();
  }
}
