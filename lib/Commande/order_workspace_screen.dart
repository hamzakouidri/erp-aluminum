import 'dart:ui' show PointerDeviceKind, PointerScrollEvent, PointerSignalEvent;

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/add_commande.dart';
import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens one order as a real application workspace tab.  It deliberately does
/// not put a second tab strip inside the order editor.
Future<void> openOrderInWorkspaceTab(
  BuildContext context, {
  required SqlDatabase db,
  int? editCommandeId,
  int? projectId,
  List<WindowModel>? initialProducts,
  VoidCallback? onSaved,
}) async {
  final settings = Provider.of<AppSettingsProvider>(context, listen: false);
  final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final usesWorkspace = isWindows || settings.viewMode != AppViewMode.classic;

  if (!usesWorkspace) {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => CommandePage(
          db: db,
          editCommandeId: editCommandeId,
          projectId: projectId,
          initialProducts: initialProducts,
        ),
      ),
    );
    if (saved == true) onSaved?.call();
    return;
  }

  final workspace = Provider.of<WorkspaceController>(context, listen: false);
  final entryId = editCommandeId == null
      ? 'order_draft_${DateTime.now().microsecondsSinceEpoch}'
      : 'order_$editCommandeId';
  final existingIndex = workspace.entries.indexWhere(
    (entry) => entry.id == entryId,
  );
  if (existingIndex != -1) {
    workspace.activate(existingIndex);
    return;
  }

  final openOrders = workspace.entries
      .where((entry) => entry.id.startsWith('order_'))
      .length;
  if (openOrders >= OrderWorkspaceScreen.maximumOpenOrders) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الحد الأقصى هو 3 طلبيات مفتوحة.')),
    );
    return;
  }

  var title = editCommandeId == null
      ? 'طلبية جديدة'
      : 'طلبية #$editCommandeId';
  if (editCommandeId != null) {
    try {
      final order = await db.readCommandeWithClientById(editCommandeId);
      final firstName = order?['firstname']?.toString().trim() ?? '';
      final lastName = order?['lastname']?.toString().trim() ?? '';
      final clientName = '$firstName $lastName'.trim();
      if (clientName.isNotEmpty) title = clientName;
    } catch (_) {
      // Keep the order number as a safe fallback if the local record is absent.
    }
  }
  workspace.open(
    entryId: entryId,
    title: title,
    icon: Icons.receipt_long_outlined,
    content: CommandePage(
      key: ValueKey(entryId),
      db: db,
      editCommandeId: editCommandeId,
      projectId: projectId,
      initialProducts: initialProducts,
      embeddedInWorkspace: true,
      onSavedInWorkspace: () {
        workspace.closeById(entryId);
        onSaved?.call();
      },
    ),
  );
}

/// A small, bounded workspace for working on several order forms without
/// mixing their state. Each tab owns a separate [CommandePage] and therefore
/// a separate customer, drawings, prices and unsaved edits.
class OrderWorkspaceScreen extends StatefulWidget {
  static const int maximumOpenOrders = 3;

  final SqlDatabase db;
  final int? initialEditCommandeId;
  final int? initialProjectId;
  final List<WindowModel>? initialProducts;

  const OrderWorkspaceScreen({
    super.key,
    required this.db,
    this.initialEditCommandeId,
    this.initialProjectId,
    this.initialProducts,
  });

  @override
  State<OrderWorkspaceScreen> createState() => _OrderWorkspaceScreenState();
}

class _OrderWorkspaceTab {
  final String id;
  final int? editCommandeId;
  final int? projectId;
  final List<WindowModel>? initialProducts;
  final GlobalKey tabKey = GlobalKey();
  final String title;

  _OrderWorkspaceTab({
    required this.id,
    required this.title,
    this.editCommandeId,
    this.projectId,
    this.initialProducts,
  });
}

class _OrderWorkspaceScreenState extends State<OrderWorkspaceScreen> {
  final ScrollController _tabsScrollController = ScrollController();
  final List<_OrderWorkspaceTab> _tabs = [];
  int _activeIndex = 0;
  bool _hasSavedOrder = false;

  @override
  void initState() {
    super.initState();
    _tabs.add(
      _createTab(
        editCommandeId: widget.initialEditCommandeId,
        projectId: widget.initialProjectId,
        initialProducts: widget.initialProducts,
      ),
    );
  }

  @override
  void dispose() {
    _tabsScrollController.dispose();
    super.dispose();
  }

  _OrderWorkspaceTab _createTab({
    int? editCommandeId,
    int? projectId,
    List<WindowModel>? initialProducts,
    String? title,
  }) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return _OrderWorkspaceTab(
      id: '${editCommandeId ?? 'new'}_$stamp',
      editCommandeId: editCommandeId,
      projectId: projectId,
      initialProducts: initialProducts,
      title:
          title ??
          (editCommandeId == null ? 'طلبية جديدة' : 'طلبية #$editCommandeId'),
    );
  }

  bool get _atCapacity =>
      _tabs.length >= OrderWorkspaceScreen.maximumOpenOrders;

  void _showCapacityMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الحد الأقصى هو 3 طلبيات مفتوحة.')),
    );
  }

  void _addNewOrder() {
    if (_atCapacity) {
      _showCapacityMessage();
      return;
    }
    setState(() {
      _tabs.add(_createTab());
      _activeIndex = _tabs.length - 1;
    });
    _ensureActiveTabVisible();
  }

  void _openSavedOrder(Map<String, dynamic> order) {
    final orderId = (order['id'] as num?)?.toInt();
    if (orderId == null) return;

    final existing = _tabs.indexWhere((tab) => tab.editCommandeId == orderId);
    if (existing >= 0) {
      _selectTab(existing);
      return;
    }
    if (_atCapacity) {
      _showCapacityMessage();
      return;
    }

    final firstName = order['firstname']?.toString().trim() ?? '';
    final lastName = order['lastname']?.toString().trim() ?? '';
    final clientName = '$firstName $lastName'.trim();
    setState(() {
      _tabs.add(
        _createTab(
          editCommandeId: orderId,
          title: clientName.isEmpty ? 'طلبية #$orderId' : clientName,
        ),
      );
      _activeIndex = _tabs.length - 1;
    });
    _ensureActiveTabVisible();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length || _activeIndex == index) return;
    setState(() => _activeIndex = index);
    _ensureActiveTabVisible();
  }

  void _ensureActiveTabVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeIndex >= _tabs.length) return;
      final context = _tabs[_activeIndex].tabKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    });
  }

  Future<void> _requestCloseTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إغلاق الطلبية؟'),
        content: const Text('أي تعديلات لم تُحفظ في هذه الطلبية ستُفقد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (shouldClose == true && mounted) _removeTab(index);
  }

  void _removeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length == 1) {
      Navigator.of(context).pop(_hasSavedOrder);
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      } else if (index < _activeIndex) {
        _activeIndex -= 1;
      }
    });
    _ensureActiveTabVisible();
  }

  void _onTabSaved(_OrderWorkspaceTab tab) {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    _hasSavedOrder = true;
    // A normal order form closes immediately after saving. Do the same for a
    // tab so a second press cannot accidentally create a duplicate order.
    _removeTab(index);
  }

  Future<void> _showOrderPicker() async {
    if (_atCapacity) {
      _showCapacityMessage();
      return;
    }
    final orders = await widget.db.readCommandesWithClients();
    if (!mounted) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فتح طلبية محفوظة'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: ListView.separated(
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final order = orders[index];
              final id = order['id']?.toString() ?? '';
              final firstName = order['firstname']?.toString().trim() ?? '';
              final lastName = order['lastname']?.toString().trim() ?? '';
              final clientName = '$firstName $lastName'.trim();
              return ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(clientName.isEmpty ? 'طلبية #$id' : clientName),
                subtitle: Text('طلبية #$id'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  Map<String, dynamic>.from(order),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) _openSavedOrder(selected);
  }

  void _handleTabPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_tabsScrollController.hasClients) {
      return;
    }
    final primaryDelta =
        event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (primaryDelta == 0) return;
    final position = _tabsScrollController.position;
    final target = (_tabsScrollController.offset + primaryDelta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - _tabsScrollController.offset).abs() < 0.5) return;

    // Claim the signal before a parent vertical scroll view can consume it.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_tabsScrollController.hasClients) {
        _tabsScrollController.jumpTo(target);
      }
    });
  }

  Future<bool> _onWillPop() async {
    Navigator.of(context).pop(_hasSavedOrder);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الطلبيات المفتوحة'),
          actions: [
            IconButton(
              tooltip: 'فتح طلبية محفوظة',
              onPressed: _showOrderPicker,
              icon: const Icon(Icons.folder_open_outlined),
            ),
            IconButton(
              tooltip: _atCapacity ? 'الحد الأقصى: 3' : 'طلبية جديدة',
              onPressed: _addNewOrder,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: true,
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                    PointerDeviceKind.unknown,
                  },
                ),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: _handleTabPointerSignal,
                  child: SizedBox(
                    height: 52,
                    child: Scrollbar(
                      controller: _tabsScrollController,
                      interactive: true,
                      thumbVisibility: !kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.windows,
                      child: SingleChildScrollView(
                        controller: _tabsScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsetsDirectional.only(
                          start: 8,
                          end: 8,
                        ),
                        child: Row(
                          children: List.generate(_tabs.length, (index) {
                        final tab = _tabs[index];
                        final isActive = index == _activeIndex;
                        return Padding(
                          key: tab.tabKey,
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: Material(
                            color: isActive
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectTab(index),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 12,
                                  end: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 190,
                                      ),
                                      child: Text(
                                        tab.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: isActive
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'إغلاق',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _requestCloseTab(index),
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _activeIndex,
                children: _tabs.map((tab) {
                  return CommandePage(
                    key: ValueKey('order-workspace-${tab.id}'),
                    db: widget.db,
                    editCommandeId: tab.editCommandeId,
                    projectId: tab.projectId,
                    initialProducts: tab.initialProducts,
                    embeddedInWorkspace: true,
                    onSavedInWorkspace: () => _onTabSaved(tab),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
