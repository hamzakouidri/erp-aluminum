import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/Cliente/show_client.dart';
import '../Screen/client_ledger_screen.dart';
import 'package:flutter/material.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/widgets/resizable_columns_table.dart';
import 'package:database_data/widgets/desktop_context_menu.dart';
import 'package:database_data/widgets/numeric_filter_search_field.dart';
import 'package:database_data/widgets/table_date_range_filter.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';

class Customers extends StatefulWidget {
  /// When this page is opened from the dashboard's "Add client" action,
  /// display the existing client form as soon as the page is ready.
  final bool openAddClientOnStart;

  const Customers({super.key, this.openAddClientOnStart = false});

  @override
  State<Customers> createState() => _CustomersState();
}

class _CustomersState extends State<Customers> {
  final SqlDatabase db = SqlDatabase();
  // Explicitly bind the page/table scroll position so the desktop wheel can
  // target this list as soon as the page is opened.
  final ScrollController _clientsScrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<String>? _dbUpdateSubscription;
  Timer? _syncRefreshDebounce;

  final Map<String, TextEditingController> _clientColumnControllers = {
    'id': TextEditingController(),
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'address': TextEditingController(),
    'email': TextEditingController(),
    'fiscal': TextEditingController(),
    'date': TextEditingController(),
    'creator': TextEditingController(),
  };
  final Map<String, NumericFilterState> _clientNumericFilters = {};
  TableDateRange _clientDateRange = const TableDateRange();

  String? _clientSortColumn;
  bool _clientSortAscending = true;

  @override
  void dispose() {
    _syncRefreshDebounce?.cancel();
    _dbUpdateSubscription?.cancel();
    _clientsScrollController.dispose();
    searchController.dispose();
    for (final controller in _clientColumnControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearAllClientColumnFilters() {
    setState(() {
      for (final controller in _clientColumnControllers.values) {
        controller.clear();
      }
      _clientNumericFilters.clear();
      _clientDateRange = const TableDateRange();
      _clientSortColumn = null;
      _clientSortAscending = true;
    });
  }

  bool get _hasActiveClientColumnFilters {
    return _clientSortColumn != null ||
        _clientDateRange.isActive ||
        _clientNumericFilters.values.any((f) => f.isActive) ||
        _clientColumnControllers.values.any((c) => c.text.trim().isNotEmpty);
  }

  List<Map<String, dynamic>> _applyClientFiltersAndSort(
    List<Map<String, dynamic>> rawData,
  ) {
    List<Map<String, dynamic>> filtered = rawData.where((d) {
      // Date Range Filter
      if (_clientDateRange.isActive) {
        final dStr = (d['created_at'] ?? d['date'] ?? '').toString();
        final dt = DateTime.tryParse(dStr);
        if (!_clientDateRange.isWithinRange(dt)) return false;
      }

      // Numeric ID filter
      if (_clientNumericFilters['id']?.isActive == true) {
        final idNum = (d['display_number'] as num?)?.toDouble() ?? (d['id'] as num?)?.toDouble() ?? 0.0;
        if (!_clientNumericFilters['id']!.matches(idNum)) return false;
      }
      final q = _searchQuery.toLowerCase().trim();
      if (q.isNotEmpty) {
        final first = (d['firstname'] ?? '').toString().toLowerCase();
        final last = (d['lastname'] ?? '').toString().toLowerCase();
        final phone = (d['phone1'] ?? '').toString().toLowerCase();
        final full = '$first $last $phone';
        if (!q.split(' ').every((term) => full.contains(term))) {
          return false;
        }
      }

      for (final entry in _clientColumnControllers.entries) {
        final colKey = entry.key;
        final filterVal = entry.value.text.toLowerCase().trim();
        if (filterVal.isEmpty) continue;

        switch (colKey) {
          case 'id':
            final idStr = (d['display_number'] ?? d['id'] ?? '')
                .toString()
                .toLowerCase();
            if (!idStr.contains(filterVal)) return false;
            break;
          case 'name':
            final first = (d['firstname'] ?? '').toString().toLowerCase();
            final last = (d['lastname'] ?? '').toString().toLowerCase();
            final nameStr = '$first $last'.trim();
            if (!nameStr.contains(filterVal)) return false;
            break;
          case 'phone':
            final p1 = (d['phone1'] ?? '').toString().toLowerCase();
            final p2 = (d['phone2'] ?? '').toString().toLowerCase();
            final pStr = '$p1 $p2'.trim();
            if (!pStr.contains(filterVal)) return false;
            break;
          case 'address':
            final addr = (d['address'] ?? '').toString().toLowerCase();
            if (!addr.contains(filterVal)) return false;
            break;
          case 'email':
            final email = (d['email'] ?? '').toString().toLowerCase();
            if (!email.contains(filterVal)) return false;
            break;
          case 'fiscal':
            final nif = (d['nif'] ?? '').toString().toLowerCase();
            final nis = (d['nis'] ?? '').toString().toLowerCase();
            final rc = (d['rc'] ?? '').toString().toLowerCase();
            final ai = (d['ai'] ?? '').toString().toLowerCase();
            final fStr = '$nif $nis $rc $ai'.trim();
            if (!fStr.contains(filterVal)) return false;
            break;
          case 'date':
            final dt = formatDate(d['created_at'] ?? '').toLowerCase();
            if (!dt.contains(filterVal)) return false;
            break;
          case 'creator':
            final cr = _formatCreatorDisplay(
              d['creation_platform']?.toString(),
            ).toLowerCase();
            if (!cr.contains(filterVal)) return false;
            break;
        }
      }

      return true;
    }).toList();

    if (_clientSortColumn != null) {
      filtered.sort((a, b) {
        int cmp = 0;
        switch (_clientSortColumn) {
          case 'id':
            final idA =
                (a['display_number'] as num?)?.toInt() ??
                (a['id'] as num?)?.toInt() ??
                0;
            final idB =
                (b['display_number'] as num?)?.toInt() ??
                (b['id'] as num?)?.toInt() ??
                0;
            cmp = idA.compareTo(idB);
            break;
          case 'name':
            final nameA = '${a['firstname'] ?? ''} ${a['lastname'] ?? ''}'
                .trim();
            final nameB = '${b['firstname'] ?? ''} ${b['lastname'] ?? ''}'
                .trim();
            cmp = nameA.compareTo(nameB);
            break;
          case 'phone':
            final pA = (a['phone1'] ?? '').toString();
            final pB = (b['phone1'] ?? '').toString();
            cmp = pA.compareTo(pB);
            break;
          case 'address':
            final addrA = (a['address'] ?? '').toString();
            final addrB = (b['address'] ?? '').toString();
            cmp = addrA.compareTo(addrB);
            break;
          case 'email':
            final emailA = (a['email'] ?? '').toString();
            final emailB = (b['email'] ?? '').toString();
            cmp = emailA.compareTo(emailB);
            break;
          case 'date':
            final dtA = (a['created_at'] ?? '').toString();
            final dtB = (b['created_at'] ?? '').toString();
            cmp = dtA.compareTo(dtB);
            break;
          case 'creator':
            final crA = _formatCreatorDisplay(
              a['creation_platform']?.toString(),
            );
            final crB = _formatCreatorDisplay(
              b['creation_platform']?.toString(),
            );
            cmp = crA.compareTo(crB);
            break;
        }
        return _clientSortAscending ? cmp : -cmp;
      });
    }

    return filtered;
  }

  late Future<List<Map<String, dynamic>>> _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canViewClients()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  String formatDate(String date) {
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('yyyy-MM-dd').format(parsed);
    } catch (_) {
      return date;
    }
  }

  TextSpan highlightText(String text, String query) {
    if (query.isEmpty) return TextSpan(text: text);

    final queryWords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (queryWords.isEmpty) return TextSpan(text: text);

    final pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    final regExp = RegExp('($pattern)', caseSensitive: false);

    final List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.yellow.withValues(alpha: 0.3),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(children: spans);
  }

  List<Map<String, dynamic>>? _cachedClients;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _dbUpdateSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      _syncRefreshDebounce?.cancel();
      _syncRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
        if (mounted) _refreshData();
      });
    });
    if (widget.openAddClientOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddClientDialog(context);
      });
    }
  }

  void _refreshData() {
    final future = _searchQuery.isEmpty
        ? db.readClientsForDisplay()
        : db.searchClientsForDisplay(_searchQuery);
    _data = future.then((list) {
      if (mounted) {
        setState(() {
          _cachedClients = list;
        });
      }
      return list;
    });
  }

  /// Result lists received from SQLite/FutureBuilder may be read-only.
  /// Keep the current page and scroll position by replacing the displayed
  /// list with a new list instead of mutating the database result in place.
  void _removeClientFromView(Object? clientId) {
    final current = _cachedClients ?? const <Map<String, dynamic>>[];
    final remaining = current
        .where((client) => client['id'].toString() != clientId.toString())
        .map((client) => Map<String, dynamic>.from(client))
        .toList(growable: false);

    setState(() {
      _cachedClients = remaining;
      _data = Future<List<Map<String, dynamic>>>.value(remaining);
    });
  }

  void _showAddClientDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ClientFormDialog(
          onSubmit: (values) async {
            try {
              await db.insertClient(
                values['firstname']!,
                values['lastname']!,
                values['phone1']!,
                values['phone2']!,
                values['email']!,
                values['address']!,
                values['nif']!,
                values['nis']!,
                values['rc']!,
                values['ai']!,
              );
            } catch (e) {
              debugPrint('Error inserting client: $e');
            }

            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
            if (!context.mounted) return;
            _refreshData();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  Localization.translate(
                    "Client added",
                    Provider.of<AppSettingsProvider>(
                      context,
                      listen: false,
                    ).language,
                  ),
                ),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(30)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showUpdateClientDialog(
    BuildContext context,
    Map<String, dynamic> client,
  ) {
    final id = client['id'];
    showDialog(
      context: context,
      builder: (dialogContext) {
        return ClientFormDialog(
          client: client,
          onSubmit: (values) async {
            await db.updateClient(
              id,
              values['firstname']!,
              values['lastname']!,
              values['phone1']!,
              values['phone2']!,
              values['email']!,
              values['address']!,
              DateTime.now().toUtc().toIso8601String(),
              values['nif']!,
              values['nis']!,
              values['rc']!,
              values['ai']!,
            );
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
            _refreshData();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDesktop =
        MediaQuery.of(context).size.width >= 900 || Platform.isWindows;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(Localization.translate("Customers", lang)),
        centerTitle: !isDesktop,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        actions: [
          if (isDesktop && settings.canCreateClients())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () => _showAddClientDialog(context),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(
                  Localization.translate("Add Client", lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0EA5E9),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: DesktopScrollFallback(
        controller: _clientsScrollController,
        child: Column(
          children: [
          // 🔍 Filter section — shown only on Mobile
          if (!(MediaQuery.of(context).size.width >= 900 || Platform.isWindows))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(width: 1, color: Colors.grey),
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          Localization.translate("Filters Clients", lang),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _data = val.isEmpty
                            ? db.readClientsForDisplay()
                            : db.searchClientsForDisplay(val);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: Localization.translate(
                        "Search by name or phone",
                        lang,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

          // 📋 List section
          Expanded(
            child: Container(
              margin: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    _cachedClients = snapshot.data;
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      _cachedClients == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError && _cachedClients == null) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(25),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 70,
                                  color: Colors.red.shade400,
                                ),
                              ),
                              const SizedBox(height: 25),
                              Text(
                                Localization.translate(
                                  "Error loading data",
                                  lang,
                                ),
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 15),
                              Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Text(
                                  Localization.translate(
                                    "Could not load data. Please try again.",
                                    lang,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 15,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(height: 30),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).cardColor,
                                  foregroundColor: Colors.red.shade600,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 30,
                                    vertical: 12,
                                  ),
                                  elevation: 0,
                                  side: BorderSide(
                                    color: Colors.red.shade200,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                onPressed: _refreshData,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 22,
                                ),
                                label: Text(
                                  Localization.translate("Refresh", lang),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final rawData = snapshot.hasData
                      ? snapshot.data!
                      : (_cachedClients ?? <Map<String, dynamic>>[]);

                  if (rawData.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.people_outline,
                                size: 80,
                                color: Colors.blue.shade400,
                              ),
                            ),
                            const SizedBox(height: 25),
                            Text(
                              Localization.translate("No Data", lang),
                              style: TextStyle(
                                color: Colors.blueGrey.shade800,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              Localization.translate(
                                "No clients registered yet. Add your first client.",
                                lang,
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, height: 1.5),
                            ),
                            SizedBox(height: 35),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Theme.of(
                                        context,
                                      ).appBarTheme.backgroundColor
                                    : Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 15,
                                ),
                                elevation: 4,
                                shadowColor: Colors.blue.withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: () => _showAddClientDialog(context),
                              icon: const Icon(
                                Icons.person_add_outlined,
                                size: 24,
                              ),
                              label: Text(
                                Localization.translate("Add Client", lang),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Filter by search query
                  final data = rawData.where((d) {
                    final q = _searchQuery.toLowerCase().trim();
                    if (q.isEmpty) return true;
                    final first = (d['firstname'] ?? '')
                        .toString()
                        .toLowerCase();
                    final last = (d['lastname'] ?? '').toString().toLowerCase();
                    final phone = (d['phone1'] ?? '').toString().toLowerCase();
                    final full = '$first $last $phone';
                    return q.split(' ').every((term) => full.contains(term));
                  }).toList();

                  if (data.isEmpty) {
                    return Center(
                      child: Text(
                        Localization.translate("No matching results", lang),
                        style: const TextStyle(fontSize: 16),
                      ),
                    );
                  }

                  if (MediaQuery.of(context).size.width >= 900 ||
                      Platform.isWindows) {
                    return _buildDesktopClientsTableView(context, data, lang);
                  }

                  return ListView.builder(
                    controller: _clientsScrollController,
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final id = item['id'] ?? '';
                      final firstName = item['firstname'] ?? '';
                      final lastName = item['lastname'] ?? '';
                      final clientName = '$lastName $firstName'.trim();
                      final phone1 = item['phone1']?.toString() ?? '';
                      final phone2 = item['phone2']?.toString() ?? '';
                      final createdAt = item['created_at'] ?? '';

                      final bool hasPhone2 =
                          phone2.isNotEmpty &&
                          phone2 != '0' &&
                          phone2 != 'null';

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(15),
                          onTap: settings.canViewClientDetails()
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ShowClient(clientId: id),
                                    ),
                                  ).then((_) => _refreshData());
                                }
                              : null,
                          onLongPress: settings.canEditClients()
                              ? () {
                                  _showUpdateClientDialog(context, item);
                                }
                              : null,
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).appBarTheme.backgroundColor
                                : Colors.blue.shade100,
                            child: const Icon(Icons.person, color: Colors.blue),
                          ),
                          title: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              children: [
                                highlightText(clientName, _searchQuery),
                              ],
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 5),
                              if (phone1.isNotEmpty)
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                    children: [
                                      WidgetSpan(
                                        child: Icon(
                                          Icons.phone,
                                          size: 14,
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                        alignment: PlaceholderAlignment.middle,
                                      ),
                                      const TextSpan(text: '  '),
                                      highlightText(phone1, _searchQuery),
                                      if (hasPhone2) ...[
                                        const TextSpan(text: '  ·  '),
                                        highlightText(phone2, _searchQuery),
                                      ],
                                    ],
                                  ),
                                ),
                              if (createdAt.isNotEmpty)
                                Text(
                                  formatDate(createdAt),
                                  style: const TextStyle(fontSize: 13),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (settings.canEditClients())
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () {
                                    _showUpdateClientDialog(context, item);
                                  },
                                ),
                              if (settings.canDeleteClients())
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(
                                          Localization.translate(
                                            "Delete Client",
                                            lang,
                                          ),
                                        ),
                                        content: Text(
                                          Localization.translate(
                                            "Are you sure you want to delete this client?",
                                            lang,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text(
                                              Localization.translate(
                                                "Cancel",
                                                lang,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: Text(
                                              Localization.translate(
                                                "Delete",
                                                lang,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        final deletedRows = await db
                                            .deleteClient(id);
                                        if (!mounted) return;
                                        if (deletedRows == 0) {
                                          // A remote sync can remove the record just before
                                          // this action. Remove the stale row locally as well,
                                          // without reloading or moving the current page.
                                          _removeClientFromView(id);
                                          ScaffoldMessenger.of(context)
                                            ..hideCurrentSnackBar()
                                            ..showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'الزبون لم يعد موجوداً في قاعدة البيانات.',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          return;
                                        }
                                        _removeClientFromView(id);
                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'تم حذف الزبون بنجاح.',
                                              ),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'تعذر حذف الزبون: $error',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                      }
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          ],
        ),
      ),

      floatingActionButton: (!isDesktop && settings.canCreateClients())
          ? FloatingActionButton(
              onPressed: () => _showAddClientDialog(context),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Theme.of(
                          context,
                        ).floatingActionButtonTheme.backgroundColor ??
                        Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: Theme.of(context).brightness == Brightness.dark
                    ? const BorderSide(color: Colors.white, width: 1.5)
                    : BorderSide.none,
              ),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Future<void> _deleteClient(dynamic id) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Localization.translate("Delete Client", lang)),
        content: Text(
          Localization.translate(
            "Are you sure you want to delete this client?",
            lang,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate("Cancel", lang)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              Localization.translate("Delete", lang),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await db.deleteClient(id);
      if (mounted) _refreshData();
    }
  }

  Future<void> _showClientContextMenu(
    BuildContext context,
    Map<String, dynamic> client,
    Offset position,
    AppLanguage lang,
  ) async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final clientId = (client['id'] as num?)?.toInt() ?? 0;
    final selected = await showDesktopContextMenu<String>(
      context: context,
      globalPosition: position,
      items: [
        if (settings.canViewClientLedger())
          PopupMenuItem(
            value: 'ledger',
            child: Text(
              Localization.translate(
                'عرض كشف الحساب التفصيلي (Chrono)',
                lang,
              ),
            ),
          ),
        if (settings.canViewClientDetails())
          PopupMenuItem(
            value: 'details',
            child: Text(Localization.translate('عرض بيانات الزبون', lang)),
          ),
        if (settings.canEditClients())
          PopupMenuItem(
            value: 'edit',
            child: Text(Localization.translate('تعديل', lang)),
          ),
        if (settings.canDeleteClients())
          PopupMenuItem(
            value: 'delete',
            child: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'ledger':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClientLedgerScreen(clientId: clientId),
          ),
        );
      case 'details':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ShowClient(clientId: clientId),
          ),
        ).then((_) => _refreshData());
      case 'edit':
        _showUpdateClientDialog(context, client);
      case 'delete':
        await _deleteClient(clientId);
    }
  }

  String _formatCreatorDisplay(String? rawPlatform) {
    String raw = (rawPlatform ?? '').trim();
    raw = raw
        .replaceFirst(
          RegExp(r'\s+\((?:web|phone|computer|هاتف|كمبيوتر|ÙˆÙŠØ¨|ÙƒÙ…Ø¨ÙŠÙˆØªØ±|Ù‡Ø§ØªÙ)\)$', caseSensitive: false),
          '',
        )
        .trim();
    if (raw.isNotEmpty &&
        raw != 'unknown' &&
        raw != 'تطبيق' &&
        raw != 'phone' &&
        raw != 'computer' &&
        raw != 'web' &&
        raw != 'هاتف' &&
        raw != 'كمبيوتر' &&
        raw != 'المدير / عامل الورشة') {
      return raw;
    }
    final user = AppAuthService().currentUser;
    if (user != null) {
      final emailName = user.email?.contains('@') == true
          ? user.email!.split('@').first
          : '';
      final displayName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : emailName;
      if (displayName.isNotEmpty) {
        if (raw.isNotEmpty) {
          return '$displayName ($raw)';
        }
        return displayName;
      }
    }
    return 'المدير / عامل الورشة';
  }

  Widget _buildSortableHeaderCell({
    int flex = 1,
    required String label,
    required String colKey,
    required Color mutedColor,
  }) {
    final isSorted = _clientSortColumn == colKey;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_clientSortColumn == colKey) {
              if (_clientSortAscending) {
                _clientSortAscending = false;
              } else {
                _clientSortColumn = null;
                _clientSortAscending = true;
              }
            } else {
              _clientSortColumn = colKey;
              _clientSortAscending = true;
            }
          });
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSorted ? const Color(0xFF0EA5E9) : mutedColor,
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: isSorted ? FontWeight.w900 : FontWeight.bold,
                  ),
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 2),
                Icon(
                  _clientSortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 13,
                  color: const Color(0xFF0EA5E9),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterInputCell({
    required int flex,
    required TextEditingController controller,
    required String hintText,
    required BuildContext context,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Cairo',
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontFamily: 'Cairo',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF0EA5E9),
                  width: 1.5,
                ),
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? InkWell(
                      onTap: () {
                        controller.clear();
                        setState(() {});
                      },
                      child: const Icon(
                        Icons.close,
                        size: 17,
                        color: Colors.red,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopClientsTableView(
    BuildContext context,
    List<Map<String, dynamic>> rawData,
    AppLanguage lang,
  ) {
    final cardColor = Theme.of(context).cardColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.lightBlue.shade100;

    final data = _applyClientFiltersAndSort(rawData);

    final columns = [
      ResizableTableColumn(
        id: 'id',
        label: _buildSortableHeaderCell(label: '#', colKey: 'id', mutedColor: mutedColor),
        filter: CompactTableFilterField(
          hintText: '#...',
          isNumeric: true,
          lang: lang,
          initialNumericState: _clientNumericFilters['id'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) => setState(() => _clientNumericFilters['id'] = f),
        ),
        initialWidth: 70,
        minWidth: 50,
        maxWidth: 120,
      ),
      ResizableTableColumn(
        id: 'name',
        label: _buildSortableHeaderCell(
          label: Localization.translate('اسم الزبون', lang),
          colKey: 'name',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('بحث بالاسم...', lang),
          controller: _clientColumnControllers['name'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 200,
        minWidth: 130,
        maxWidth: 360,
      ),
      ResizableTableColumn(
        id: 'phone',
        label: _buildSortableHeaderCell(
          label: Localization.translate('رقم الهاتف', lang),
          colKey: 'phone',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('بحث بالهاتف...', lang),
          controller: _clientColumnControllers['phone'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 135,
        minWidth: 100,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'address',
        label: _buildSortableHeaderCell(
          label: Localization.translate('العنوان', lang),
          colKey: 'address',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('بحث بالعنوان...', lang),
          controller: _clientColumnControllers['address'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 150,
        minWidth: 100,
        maxWidth: 260,
      ),
      ResizableTableColumn(
        id: 'email',
        label: _buildSortableHeaderCell(
          label: Localization.translate('البريد الإلكتروني', lang),
          colKey: 'email',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('بحث بالبريد...', lang),
          controller: _clientColumnControllers['email'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 150,
        minWidth: 100,
        maxWidth: 260,
      ),
      ResizableTableColumn(
        id: 'fiscal',
        label: _buildSortableHeaderCell(
          label: Localization.translate('البيانات الجبائية (NIF/RC)', lang),
          colKey: 'fiscal',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('NIF / NIS...', lang),
          controller: _clientColumnControllers['fiscal'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 160,
        minWidth: 100,
        maxWidth: 280,
      ),
      ResizableTableColumn(
        id: 'date',
        label: _buildSortableHeaderCell(
          label: Localization.translate('تاريخ الإضافة', lang),
          colKey: 'date',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('سنة-شهر...', lang),
          controller: _clientColumnControllers['date'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 125,
        minWidth: 95,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'creator',
        label: _buildSortableHeaderCell(
          label: Localization.translate('تم الإدخال بواسطة', lang),
          colKey: 'creator',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('المُضيف...', lang),
          controller: _clientColumnControllers['creator'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'actions',
        label: Center(
          child: Text(
            Localization.translate('إجراءات', lang),
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        filter: _hasActiveClientColumnFilters
            ? Center(
                child: InkWell(
                  onTap: _clearAllClientColumnFilters,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.clear_all, size: 13, color: Colors.red),
                        const SizedBox(width: 2),
                        Text(
                          Localization.translate('مسح', lang),
                          style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        initialWidth: 100,
        minWidth: 80,
        maxWidth: 160,
      ),
    ];

    final rows = data.map((client) {
      final clientId = (client['id'] as num?)?.toInt() ?? 0;
      final clientNumber =
          (client['display_number'] as num?)?.toInt() ?? clientId;
      final firstName = (client['firstname'] ?? '').toString().trim();
      final lastName = (client['lastname'] ?? '').toString().trim();
      final fullName = '$firstName $lastName'.trim();

      final phone1 = (client['phone1'] ?? '').toString().trim();
      final phone2 = (client['phone2'] ?? '').toString().trim();
      final phoneDisplay = phone1.isNotEmpty
          ? (phone2.isNotEmpty && phone2 != '0' ? '$phone1 / $phone2' : phone1)
          : (phone2.isNotEmpty && phone2 != '0' ? phone2 : '—');

      final addressDisplay =
          (client['address'] ?? '').toString().trim().isNotEmpty
          ? client['address'].toString().trim()
          : '—';

      final emailDisplay =
          (client['email'] ?? '').toString().trim().isNotEmpty
          ? client['email'].toString().trim()
          : '—';

      final nif = (client['nif'] ?? '').toString().trim();
      final nis = (client['nis'] ?? '').toString().trim();
      final rc = (client['rc'] ?? '').toString().trim();
      final ai = (client['ai'] ?? '').toString().trim();

      final List<String> taxParts = [];
      if (nif.isNotEmpty) taxParts.add('NIF: $nif');
      if (nis.isNotEmpty) taxParts.add('NIS: $nis');
      if (rc.isNotEmpty) taxParts.add('RC: $rc');
      if (ai.isNotEmpty) taxParts.add('AI: $ai');
      final taxDisplay = taxParts.isNotEmpty ? taxParts.join(' | ') : '—';

      final addedBy = _formatCreatorDisplay(
        client['creation_platform']?.toString(),
      );
      final createdAt = formatDate(client['created_at'] ?? '');

      return ResizableTableRow(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShowClient(clientId: clientId),
            ),
          );
        },
        onSecondaryTapDown: (position) =>
            _showClientContextMenu(context, client, position, lang),
        cells: [
          // ID
          Text(
            '#$clientNumber',
            style: const TextStyle(
              color: Color(0xFF0EA5E9),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Name
          Text(
            fullName.isEmpty ? 'زبون #$clientNumber' : fullName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0EA5E9),
            ),
          ),
          // Phone
          Text(
            phoneDisplay,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: contentColor),
          ),
          // Address
          Text(
            addressDisplay,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: mutedColor),
          ),
          // Email
          Text(
            emailDisplay,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: mutedColor),
          ),
          // Fiscal
          Text(
            taxDisplay,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Color(0xFF8B5CF6)),
          ),
          // Date
          Text(
            createdAt.isEmpty ? '—' : createdAt,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: mutedColor),
          ),
          // Creator
          Text(
            addedBy,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: mutedColor),
          ),
          // Actions
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.blue),
                  onPressed: () => _showUpdateClientDialog(context, client),
                  tooltip: Localization.translate('تعديل', lang),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                  onPressed: () => _deleteClient(client['id']),
                  tooltip: Localization.translate('حذف', lang),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Date Range Filter Bar ──
          TableDateRangeFilterBar(
            initialRange: _clientDateRange,
            lang: lang,
            compact: true,
            onRangeChanged: (range) {
              setState(() => _clientDateRange = range);
            },
          ),
          const SizedBox(height: 8),

          // ── Desktop Resizable Table with zero vertical overflow ──
          Expanded(
            child: data.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Localization.translate("No matching results", lang),
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        if (_hasActiveClientColumnFilters) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _clearAllClientColumnFilters,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text(
                              'إعادة ضبط البحث والتصفية',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ResizableColumnsTable(
                        persistenceKey: 'clients',
                        columns: columns,
                        rows: rows,
                        headerColor: const Color(0xFF0EA5E9).withValues(alpha: 0.08),
                        filterRowColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderColor: borderColor,
                        rowColor: cardColor,
                        verticalController: _clientsScrollController,
                        headerMinHeight: 38,
                        filterRowMinHeight: 34,
                        rowMinHeight: 46,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ClientFormDialog extends StatefulWidget {
  final Map<String, dynamic>? client;
  final void Function(Map<String, String> values) onSubmit;

  const ClientFormDialog({super.key, this.client, required this.onSubmit});

  @override
  State<ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstnameController;
  late final TextEditingController _lastnameController;
  late final TextEditingController _phone1Controller;
  late final TextEditingController _phone2Controller;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _nifController;
  late final TextEditingController _nisController;
  late final TextEditingController _rcController;
  late final TextEditingController _aiController;

  bool _showCompanyDetails = false;

  @override
  void initState() {
    super.initState();
    final c = widget.client ?? {};
    _firstnameController = TextEditingController(text: c['firstname'] ?? '');
    _lastnameController = TextEditingController(text: c['lastname'] ?? '');
    _phone1Controller = TextEditingController(
      text: c['phone1']?.toString() ?? '',
    );
    _phone2Controller = TextEditingController(
      text: c['phone2']?.toString() ?? '',
    );
    _emailController = TextEditingController(text: c['email'] ?? '');
    _addressController = TextEditingController(text: c['address'] ?? '');
    _nifController = TextEditingController(text: c['nif'] ?? '');
    _nisController = TextEditingController(text: c['nis'] ?? '');
    _rcController = TextEditingController(text: c['rc'] ?? '');
    _aiController = TextEditingController(text: c['ai'] ?? '');

    if (widget.client != null ||
        _nifController.text.isNotEmpty ||
        _nisController.text.isNotEmpty ||
        _rcController.text.isNotEmpty ||
        _aiController.text.isNotEmpty) {
      _showCompanyDetails = true;
    }
  }

  @override
  void dispose() {
    _firstnameController.dispose();
    _lastnameController.dispose();
    _phone1Controller.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _nifController.dispose();
    _nisController.dispose();
    _rcController.dispose();
    _aiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isEdit = widget.client != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              isEdit
                  ? Localization.translate("Update Client", lang)
                  : Localization.translate("Add Client", lang),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isEdit) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              icon: Icon(
                _showCompanyDetails ? Icons.keyboard_arrow_up : Icons.business,
                size: 18,
              ),
              label: Text(
                _showCompanyDetails ? 'إخفاء معلومات الشركة' : 'معلومات الشركة',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              onPressed: () {
                setState(() {
                  _showCompanyDetails = !_showCompanyDetails;
                });
              },
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _firstnameController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("First Name", lang),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? Localization.translate(
                          "Please enter a first name",
                          lang,
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastnameController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("Last Name", lang),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? Localization.translate("Please enter a last name", lang)
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone1Controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: Localization.translate("Phone Number 1", lang),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    counterText: '',
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? Localization.translate(
                          "Please enter a phone number",
                          lang,
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone2Controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: Localization.translate("Phone Number 2", lang),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("Email", lang),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("Address", lang),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                if (_showCompanyDetails) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'معلومات الشركة / Enterprise Info',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[800],
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nifController,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'الرقم التعريفي الجبائي / NIF',
                        lang,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nisController,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'الرقم التعريفي الإحصائي / NIS',
                        lang,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rcController,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'السجل التجاري / RC',
                        lang,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _aiController,
                    decoration: InputDecoration(
                      labelText: Localization.translate('رقم المادة / AI', lang),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Localization.translate("Cancel", lang)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onSubmit({
                'firstname': _firstnameController.text.trim(),
                'lastname': _lastnameController.text.trim(),
                'phone1': _phone1Controller.text.trim(),
                'phone2': _phone2Controller.text.trim(),
                'email': _emailController.text.trim(),
                'address': _addressController.text.trim(),
                'nif': _nifController.text.trim(),
                'nis': _nisController.text.trim(),
                'rc': _rcController.text.trim(),
                'ai': _aiController.text.trim(),
              });
            }
          },
          child: Text(
            isEdit
                ? Localization.translate("Update", lang)
                : Localization.translate("Add", lang),
          ),
        ),
      ],
    );
  }
}
