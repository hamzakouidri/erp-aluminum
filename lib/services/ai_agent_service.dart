import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Commande/order_status_order.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';
import 'ai_controller_service.dart';
import 'gemini_gateway.dart';

/// What the signed-in user may do. The agent works under these rights and
/// never more: a tool the user may not use is not offered to the model, and
/// is refused again when it is called.
class AiAgentPermissions {
  const AiAgentPermissions({
    this.viewOrders = false,
    this.viewOrderDetails = false,
    this.changeOrderStatus = false,
    this.viewClients = false,
    this.createClients = false,
    this.viewClientLedger = false,
    this.accessInventory = false,
    this.viewCostPrice = false,
    this.accessTreasury = false,
    this.userName = '',
  });

  factory AiAgentPermissions.fromSettings(AppSettingsProvider settings) =>
      AiAgentPermissions(
        viewOrders: settings.canViewOrders(),
        viewOrderDetails: settings.canViewOrderDetails(),
        changeOrderStatus: settings.canChangeOrderStatus(),
        viewClients: settings.canViewClients(),
        createClients: settings.canCreateClients(),
        viewClientLedger: settings.canViewClientLedger(),
        accessInventory: settings.canAccessInventory(),
        viewCostPrice: settings.canViewCostPrice(),
        accessTreasury: settings.canAccessTreasury(),
        userName: settings.userDisplayName,
      );

  final bool viewOrders;
  final bool viewOrderDetails;
  final bool changeOrderStatus;
  final bool viewClients;
  final bool createClients;
  final bool viewClientLedger;
  final bool accessInventory;
  final bool viewCostPrice;
  final bool accessTreasury;
  final String userName;
}

/// Asks the user to approve a change before the agent makes it.
typedef AiConfirm = Future<bool> Function(String title, String details);

class AiAgentResult {
  AiAgentResult({
    required this.text,
    this.steps = const [],
    this.model,
    this.navigateTo,
    this.isError = false,
  });

  /// The answer to show and read aloud.
  final String text;

  /// One line per tool the agent used, for the "what I did" trace.
  final List<String> steps;
  final String? model;

  /// A screen the agent asked to open once the answer is shown.
  final String? navigateTo;
  final bool isError;
}

class _Tool {
  const _Tool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.allowed,
    required this.run,
    this.confirm,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final bool Function(AiAgentPermissions p) allowed;

  /// Returns the title (a translation key) and the details to approve, or
  /// null for a read.
  final (String, String) Function(Map<String, dynamic> args)? confirm;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args) run;
}

/// The workshop assistant: a Gemini model that works through the app's own
/// data and actions with native function calling, in as many steps as a
/// question needs, instead of answering from one guessed JSON command.
class AiAgentService {
  AiAgentService({required this.gateway, SqlDatabase? db, this.preferredModel})
    : db = db ?? SqlDatabase();

  /// Reaches Gemini through the server (or the user's own key).
  final GeminiGateway gateway;
  final SqlDatabase db;

  /// A model chosen by the user; otherwise the strongest one available.
  final String? preferredModel;

  static const modelPreferenceKey = 'ai_agent_model';

  /// Used when the model list cannot be read.
  static const fallbackModels = [
    'gemini-3-pro',
    'gemini-2.5-pro',
    'gemini-3.8-flash',
    'gemini-2.5-flash',
  ];

  static List<String>? _cachedModels;

  /// Text models that support generateContent, strongest first.
  Future<List<String>> availableModels() => modelsVia(gateway);

  /// [availableModels] for any gateway, cached for the session; the other
  /// AI services use it to pick the same strongest model.
  static Future<List<String>> modelsVia(GeminiGateway gateway) async {
    if (_cachedModels != null) return _cachedModels!;
    try {
      final decoded = await gateway.listModels();
      if (decoded == null) return fallbackModels;
      final names = <String>[];
      for (final model in (decoded['models'] as List? ?? const [])) {
        final methods = (model['supportedGenerationMethods'] as List? ?? [])
            .map((m) => m.toString());
        if (!methods.contains('generateContent')) continue;
        final name = model['name'].toString().replaceFirst('models/', '');
        if (isConversationModel(name)) names.add(name);
      }
      names.sort((a, b) => modelRank(b).compareTo(modelRank(a)));
      return _cachedModels = names.isEmpty ? fallbackModels : names;
    } catch (error) {
      debugPrint('Could not list Gemini models: $error');
      return fallbackModels;
    }
  }

  /// A Gemini chat model, not an embedding, image, speech or live model.
  @visibleForTesting
  static bool isConversationModel(String name) {
    final n = name.toLowerCase();
    if (!n.startsWith('gemini')) return false;
    const excluded = [
      'embedding',
      'image',
      'tts',
      'audio',
      'live',
      'robotics',
      'computer-use',
      'aqa',
      'learnlm',
    ];
    return !excluded.any(n.contains);
  }

  /// Higher is stronger: pro over flash over lite, newer versions first,
  /// stable releases before previews and experiments.
  @visibleForTesting
  static double modelRank(String name) {
    final n = name.toLowerCase();
    final versionMatch = RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(n);
    final version = double.tryParse(versionMatch?.group(1) ?? '') ?? 0;
    final tier = n.contains('pro')
        ? 3
        : n.contains('lite')
        ? 1
        : n.contains('flash')
        ? 2
        : 1.5;
    final stable = n.contains('preview') || n.contains('exp') ? 0 : 0.5;
    return tier * 100 + version * 10 + stable;
  }

  static Future<String?> savedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(modelPreferenceKey)?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static Future<void> saveModel(String? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null || model.isEmpty) {
      await prefs.remove(modelPreferenceKey);
    } else {
      await prefs.setString(modelPreferenceKey, model);
    }
  }

  // ----------------------------------------------------------------- tools

  static Map<String, dynamic> _object(
    Map<String, Map<String, dynamic>> properties, [
    List<String> required = const [],
  ]) => {
    'type': 'OBJECT',
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
  };

  static Map<String, dynamic> _string(String description, [List<String>? e]) =>
      {'type': 'STRING', 'description': description, 'enum': ?e};

  static Map<String, dynamic> _integer(String description) => {
    'type': 'INTEGER',
    'description': description,
  };

  static Map<String, dynamic> _number(String description) => {
    'type': 'NUMBER',
    'description': description,
  };

  static const screens = [
    'orders',
    'caisse',
    'stock',
    'clients',
    'cutting_optimizer',
    'tempered_glass',
    'settings',
    'purchases',
    'material_sales',
    'projects',
    'reports',
    'worker_tasks',
    'suppliers',
  ];

  String? _navigateTo;

  List<_Tool> _tools(AiAgentPermissions p, AppLanguage language) => [
    _Tool(
      name: 'search_orders',
      description:
          'Find orders (طلبيات / commandes) by client name, phone or order '
          'number, optionally by status. Newest first.',
      parameters: _object({
        'query': _string('Client name, phone or order number. Empty for all.'),
        'status': _string('Order status filter', canonicalOrderStatuses),
        'limit': _integer('Maximum results, default 15, at most 40.'),
      }),
      allowed: (p) => p.viewOrders,
      run: _searchOrders,
    ),
    _Tool(
      name: 'get_order',
      description:
          'Full details of one order: client, status, totals and payments, '
          'every window line with its size, system, glass and colour, and '
          'whether its stock is reserved or already issued.',
      parameters: _object({
        'order_id': _integer('Internal id of the order.'),
        'order_number': _integer('The order number people see.'),
      }),
      allowed: (p) => p.viewOrderDetails,
      run: (args) => _getOrder(args, p),
    ),
    _Tool(
      name: 'search_clients',
      description:
          'Find clients by name or phone, with their balance when allowed.',
      parameters: _object({'query': _string('Name or phone.')}, ['query']),
      allowed: (p) => p.viewClients,
      run: (args) => _searchClients(args, p),
    ),
    _Tool(
      name: 'search_stock',
      description:
          'Stock of materials (profiles, accessories, glass, joints, shutter '
          'parts) by name or code, per warehouse, with the quantity reserved '
          'for orders and the free quantity.',
      parameters: _object(
        {
          'query': _string('Item name, code, series or colour words.'),
          'limit': _integer('Maximum items, default 15.'),
        },
        ['query'],
      ),
      allowed: (p) => p.accessInventory,
      run: (args) => _searchStock(args, p),
    ),
    _Tool(
      name: 'get_product_history',
      description:
          'Movement history of one stock item across the store and the '
          'workshop: purchases, transfers, issues to orders, sales, returns, '
          'with supplier, client, order and who did it. Use the item_id, '
          'item_type and color_id returned by search_stock.',
      parameters: _object(
        {
          'item_id': _integer('Item id from search_stock.'),
          'item_type': _string('Item type from search_stock.'),
          'color_id': _integer('Colour id from search_stock, if any.'),
          'limit': _integer('Latest movements to return, default 20.'),
        },
        ['item_id', 'item_type'],
      ),
      allowed: (p) => p.accessInventory,
      run: (args) => _productHistory(args, p),
    ),
    _Tool(
      name: 'cashbox_summary',
      description: "Today's cashbox (الصندوق / caisse) income and expenses.",
      parameters: _object({
        'target': _string('Which cashbox', ['workshop', 'store', 'all']),
      }),
      allowed: (p) => p.accessTreasury,
      run: (args) async => {
        'summary': await AiControllerService(gateway: gateway)
            .getDailyCaisseSummary(
              targetCaisse: args['target']?.toString(),
              language: language,
            ),
      },
    ),
    _Tool(
      name: 'list_suppliers',
      description: 'Suppliers, with what the workshop owes each of them.',
      parameters: _object({'query': _string('Name filter, optional.')}),
      allowed: (p) => p.accessTreasury,
      run: _listSuppliers,
    ),
    _Tool(
      name: 'workshop_overview',
      description:
          'Overview of the workshop: counts of orders and clients and the '
          'number of orders in each status.',
      parameters: _object({}),
      allowed: (p) => p.viewOrders,
      run: (_) async {
        final stats = await db.getDashboardStats();
        final byStatus = await db.getOrderStatusStats();
        return {
          'stats': _plain(stats),
          'orders_by_status': _plain(byStatus['byStatus']),
        };
      },
    ),
    _Tool(
      name: 'create_client',
      description:
          'Create a new client. Search first to avoid a duplicate. The user '
          'is asked to approve.',
      parameters: _object(
        {
          'first_name': _string('First name.'),
          'last_name': _string('Last name.'),
          'phone': _string('Phone number.'),
          'address': _string('Address, optional.'),
        },
        ['first_name'],
      ),
      allowed: (p) => p.createClients,
      confirm: (args) => (
        'إضافة زبون جديد',
        '${args['first_name'] ?? ''} ${args['last_name'] ?? ''}\n'
            '${args['phone'] ?? ''}',
      ),
      run: _createClient,
    ),
    _Tool(
      name: 'update_order_status',
      description:
          'Move an order to another status in the workshop lifecycle. The '
          'user is asked to approve.',
      parameters: _object(
        {
          'order_id': _integer(
            'Internal id of the order (from search_orders).',
          ),
          'status': _string('New status', canonicalOrderStatuses),
        },
        ['order_id', 'status'],
      ),
      allowed: (p) => p.changeOrderStatus,
      confirm: (args) => (
        'تغيير حالة طلبية',
        '#${args['order_id']} → ${args['status']}',
      ),
      run: _updateOrderStatus,
    ),
    _Tool(
      name: 'record_client_payment',
      description:
          'Record money received from a client for an order, into the '
          'cashbox. The user is asked to approve.',
      parameters: _object(
        {
          'order_id': _integer('Internal id of the order.'),
          'amount': _number('Amount received, in DZD.'),
        },
        ['order_id', 'amount'],
      ),
      allowed: (p) => p.accessTreasury,
      confirm: (args) => (
        'تسجيل دفعة زبون',
        '#${args['order_id']}: ${args['amount']} DZD',
      ),
      run: (args) => _recordPayment(args, p),
    ),
    _Tool(
      name: 'open_screen',
      description:
          'Open a screen of the app for the user after answering, when they '
          'ask to go somewhere.',
      parameters: _object(
        {'screen': _string('Screen to open', screens)},
        ['screen'],
      ),
      allowed: (_) => true,
      run: (args) async {
        _navigateTo = args['screen']?.toString();
        return {'opened': _navigateTo};
      },
    ),
  ].where((tool) => tool.allowed(p)).toList();

  /// JSON-safe copy of database values.
  static Object? _plain(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): _plain(e.value)};
    }
    if (value is List) return value.map(_plain).toList();
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    return value.toString();
  }

  static Map<String, dynamic> _pick(
    Map<String, dynamic> row,
    List<String> keys,
  ) => {
    for (final key in keys)
      if (row[key] != null && row[key].toString().trim().isNotEmpty)
        key: _plain(row[key]),
  };

  static int? _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString().trim() ?? '');

  static const _orderKeys = [
    'id',
    'display_number',
    'status',
    'firstname',
    'lastname',
    'phone',
    'project_name',
    'total',
    'net_payable',
    'advance_payment',
    'payment_status',
    'created_at',
    'updated_by',
    'description',
  ];

  Future<Map<String, dynamic>> _searchOrders(Map<String, dynamic> args) async {
    final query = args['query']?.toString().trim().toLowerCase() ?? '';
    final status = args['status']?.toString().trim().toLowerCase() ?? '';
    final limit = (_int(args['limit']) ?? 15).clamp(1, 40);
    final rows = await db.readCommandesWithClients();
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      final haystack = [
        row['firstname'],
        row['lastname'],
        row['phone'],
        row['display_number'],
        row['order_code'],
        row['id'],
        row['project_name'],
      ].join(' ').toLowerCase();
      if (query.isNotEmpty && !haystack.contains(query)) continue;
      if (status.isNotEmpty &&
          row['status']?.toString().toLowerCase() != status) {
        continue;
      }
      matches.add(_pick(row, _orderKeys));
      if (matches.length >= limit) break;
    }
    return {'count': matches.length, 'orders': matches};
  }

  Future<int?> _resolveOrderId(Map<String, dynamic> args) async {
    final id = _int(args['order_id']);
    if (id != null) return id;
    final number = _int(args['order_number']);
    if (number == null) return null;
    final rows = await db.readCommandesWithClients();
    for (final row in rows) {
      if (_int(row['display_number']) == number ||
          _int(row['order_code']) == number) {
        return _int(row['id']);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _getOrder(
    Map<String, dynamic> args,
    AiAgentPermissions p,
  ) async {
    final id = await _resolveOrderId(args);
    if (id == null) return {'error': 'order not found'};
    final order = await db.readCommandeWithClientById(id);
    if (order == null) return {'error': 'order not found'};
    final lines = await db.readCommandeDetails(id);
    final result = <String, dynamic>{
      'order': _pick(order, _orderKeys),
      'windows': [
        for (final line in lines)
          _pick(line, const [
            'largeur',
            'hauteur',
            'quantity',
            'game',
            'window_type',
            'glass',
            'color',
            'volet',
            'accessories',
            'description',
            'price',
            'delivered_qty',
          ]),
      ],
      'stock_reserved': await db.isOrderStockReserved(id),
      'stock_issued': await db.hasOrderInventoryIssue(id),
    };
    if (p.viewClientLedger || p.accessTreasury) {
      final payments = (await db.readTreasury()).where(
        (row) =>
            _int(row['reference_id']) == id &&
            row['entity_type']?.toString() == 'Client',
      );
      result['payments'] = [
        for (final row in payments)
          _pick(row, const [
            'transaction_type',
            'amount',
            'created_at',
            'payment_method',
            'recorded_by',
          ]),
      ];
    }
    return result;
  }

  Future<Map<String, dynamic>> _searchClients(
    Map<String, dynamic> args,
    AiAgentPermissions p,
  ) async {
    final rows = await db.searchClientsForDisplay(
      args['query']?.toString() ?? '',
    );
    final clients = <Map<String, dynamic>>[];
    for (final row in rows.take(15)) {
      final client = _pick(row, const [
        'id',
        'client_code',
        'firstname',
        'lastname',
        'phone1',
        'phone2',
        'address',
      ]);
      final id = _int(row['id']);
      if (p.viewClientLedger && id != null) {
        client['balance_dzd'] = await db.getClientBalance(id);
      }
      clients.add(client);
    }
    return {'count': clients.length, 'clients': clients};
  }

  Future<Map<String, dynamic>> _searchStock(
    Map<String, dynamic> args,
    AiAgentPermissions p,
  ) async {
    final words = (args['query']?.toString() ?? '')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final limit = (_int(args['limit']) ?? 15).clamp(1, 40);
    final byItem = <String, Map<String, dynamic>>{};
    for (final location in await db.readLocations()) {
      final locationId = _int(location['id']);
      if (locationId == null) continue;
      for (final row in await db.readAllPossibleStock(locationId)) {
        final text = [
          row['item_name'],
          row['item_code'],
          row['series_name'],
          row['profile_name'],
          row['color_name'],
          row['item_type'],
        ].join(' ').toLowerCase();
        if (!words.every(text.contains)) continue;
        final key = '${row['item_type']}|${row['item_id']}|${row['color_id']}';
        final item = byItem.putIfAbsent(
          key,
          () => {
            ..._pick(row, const [
              'item_id',
              'item_type',
              'item_code',
              'item_name',
              'series_name',
              'color_id',
              'color_name',
            ]),
            'warehouses': <Map<String, dynamic>>[],
          },
        );
        final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
        if (quantity != 0) {
          (item['warehouses'] as List).add({
            'warehouse': location['name'],
            'quantity': quantity,
          });
        }
      }
      if (byItem.length >= limit * 3) break;
    }
    final items = byItem.values.take(limit).toList();
    for (final item in items) {
      final availability = await db.readStockAvailability(
        itemId: _int(item['item_id']) ?? 0,
        itemType: item['item_type'].toString(),
        colorId: _int(item['color_id']),
      );
      var reserved = 0.0;
      var free = 0.0;
      for (final row in availability) {
        reserved += (row['reserved_quantity'] as num?)?.toDouble() ?? 0;
        free += (row['quantity'] as num?)?.toDouble() ?? 0;
      }
      item['reserved_for_orders'] = reserved;
      item['free_quantity'] = free;
    }
    return {'count': items.length, 'items': items};
  }

  Future<Map<String, dynamic>> _productHistory(
    Map<String, dynamic> args,
    AiAgentPermissions p,
  ) async {
    final card = await db.readProductMovementCard(
      itemId: _int(args['item_id']) ?? 0,
      itemType: args['item_type']?.toString() ?? '',
      colorId: _int(args['color_id']),
    );
    final limit = (_int(args['limit']) ?? 20).clamp(1, 60);
    final movements = (card['movements'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final latest = movements.reversed.take(limit).map((row) {
      final picked = _pick(row, [
        'moved_at',
        'movement_type',
        'from_location_name',
        'to_location_name',
        'quantity',
        'transfer_quantity',
        'supplier_name',
        'client_name',
        'doc_type',
        'doc_code',
        'order_code',
        'performed_by',
        'reason',
        'running_balance',
        if (p.viewCostPrice) 'unit_cost',
      ]);
      return picked;
    }).toList();
    final last = card['last_purchase'] as Map<String, dynamic>?;
    return {
      'balances': _plain(card['balances']),
      'total_quantity': card['total_quantity'],
      'reserved_quantity': card['reserved_quantity'],
      if (p.viewCostPrice) 'average_cost': card['average_cost'],
      if (last != null)
        'last_purchase': _pick(last, [
          'moved_at',
          'supplier_name',
          'doc_code',
          if (p.viewCostPrice) 'unit_cost',
        ]),
      'latest_movements': latest,
    };
  }

  Future<Map<String, dynamic>> _listSuppliers(Map<String, dynamic> args) async {
    final query = args['query']?.toString().trim().toLowerCase() ?? '';
    final suppliers = <Map<String, dynamic>>[];
    for (final row in await db.readSuppliers()) {
      if (query.isNotEmpty &&
          !(row['name']?.toString().toLowerCase().contains(query) ?? false)) {
        continue;
      }
      final id = _int(row['id']);
      suppliers.add({
        ..._pick(row, const ['id', 'name', 'phone']),
        if (id != null) 'owed_dzd': await db.getSupplierBalance(id),
      });
      if (suppliers.length >= 30) break;
    }
    return {'count': suppliers.length, 'suppliers': suppliers};
  }

  Future<Map<String, dynamic>> _createClient(Map<String, dynamic> args) async {
    final phone = args['phone']?.toString().trim() ?? '';
    if (phone.isNotEmpty) {
      final existing = await db.searchClientsForDisplay(phone);
      if (existing.isNotEmpty) {
        return {
          'error': 'a client with this phone already exists',
          'existing': _plain(existing.first),
        };
      }
    }
    final id = await db.insertClient(
      args['first_name']?.toString().trim() ?? '',
      args['last_name']?.toString().trim() ?? '',
      phone,
      '',
      '',
      args['address']?.toString().trim() ?? '',
    );
    return {'created_client_id': id};
  }

  Future<Map<String, dynamic>> _updateOrderStatus(
    Map<String, dynamic> args,
  ) async {
    final id = _int(args['order_id']);
    final status = args['status']?.toString() ?? '';
    if (id == null || !canonicalOrderStatuses.contains(status)) {
      return {'error': 'unknown order or status'};
    }
    final order = await db.readCommandeWithClientById(id);
    if (order == null) return {'error': 'order not found'};
    await db.updateCommandeStatus(id, status);
    return {
      'order_id': id,
      'old_status': order['status'],
      'new_status': status,
    };
  }

  Future<Map<String, dynamic>> _recordPayment(
    Map<String, dynamic> args,
    AiAgentPermissions p,
  ) async {
    final id = _int(args['order_id']);
    final amount = (args['amount'] as num?)?.toDouble() ?? 0;
    if (id == null || amount <= 0) return {'error': 'invalid order or amount'};
    final order = await db.readCommandeWithClientById(id);
    if (order == null) return {'error': 'order not found'};
    final clientName = '${order['firstname'] ?? ''} ${order['lastname'] ?? ''}'
        .trim();
    final number = order['display_number'] ?? order['order_code'] ?? id;
    await db.insertTreasury(
      'Encaissement',
      amount,
      'دفعة لطلبية رقم $number من الزبون: $clientName',
      referenceId: id,
      entityType: 'Client',
      entityId: _int(order['client_id']),
      recordedBy: p.userName.isEmpty ? 'AI' : p.userName,
    );
    return {'recorded': amount, 'order_id': id, 'client': clientName};
  }

  // ------------------------------------------------------------------ loop

  static String systemInstruction(AppLanguage language, String userName) {
    final lang = switch (language) {
      AppLanguage.french => 'French',
      AppLanguage.english => 'English',
      _ => 'Arabic',
    };
    final now = DateTime.now();
    return '''
You are a senior employee of an aluminium, PVC and glass joinery workshop that
also runs a materials store, working inside its ERP app on behalf of
${userName.isEmpty ? 'the signed-in user' : userName}. Today is ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.

How you work:
- Use the tools for anything about this workshop's orders, clients, stock,
  cash or suppliers. Never guess a number, a name or a status: look it up.
  Chain tools when needed (e.g. find the client, then their orders, then one
  order's details).
- If a tool returns nothing, say so plainly and suggest what to check.
- Changes (new client, order status, payment) are made only through their
  tools; the app asks the user to approve each one. Do not claim a change was
  made unless the tool result confirms it. If the user cancels, accept it.
- Ask one short question when a request is ambiguous (two matching clients,
  missing amount, unclear order).
- You know joinery well: casement (ouvrant/frappe), sliding (coulissant),
  roller shutters, glazing, profiles, hardware, cutting and deductions. Give
  practical, precise answers in millimetres and DZD.

Reply in the user's language (Arabic, Algerian Darija understood, French or
English); default to $lang. Keep answers clear and structured, use short
lists for several items, and do not show raw JSON or internal ids unless
asked.
''';
  }

  /// [systemInstruction] for a spoken Live conversation.
  static String voiceInstruction(AppLanguage language, String userName) =>
      '''
${systemInstruction(language, userName)}
This is a live voice conversation, like a phone call with a colleague:
- Speak naturally and briefly, one or two sentences unless asked for more.
  No lists, tables, symbols or markdown: they are not read aloud.
- Answer in the language and dialect the user speaks (Algerian Darija stays
  Darija, French stays French), switching when they switch.
- Say numbers the way people say them; round money to the dinar.
- Before a tool that may take a moment, say a few words ("I'll check").
- If the user interrupts, stop and listen.
''';

  /// Answers [userText] in the context of [history] (alternating
  /// {'role': 'user'|'model', 'content': text}), using the tools the user's
  /// [permissions] allow and asking [confirm] before every change.
  /// [attachments] are extra parts of the user turn (an image, a sketch).
  Future<AiAgentResult> run({
    required String userText,
    List<Map<String, String>> history = const [],
    required AppLanguage language,
    required AiAgentPermissions permissions,
    required AiConfirm confirm,
    List<Map<String, dynamic>> attachments = const [],
    int maxSteps = 8,
  }) async {
    _navigateTo = null;
    _lastError = null;
    final declarations = functionDeclarations(permissions, language);
    final contents = <Map<String, dynamic>>[
      ..._history(history),
      {
        'role': 'user',
        'parts': [
          ...attachments,
          {'text': userText},
        ],
      },
    ];
    final steps = <String>[];
    final models = preferredModel != null
        ? [preferredModel!, ...(await availableModels())]
        : await availableModels();

    String? usedModel;
    for (var step = 0; step < maxSteps; step++) {
      final (response, model) = await _generate(
        models: usedModel == null ? models : [usedModel],
        body: {
          'systemInstruction': {
            'parts': [
              {'text': systemInstruction(language, permissions.userName)},
            ],
          },
          'contents': contents,
          if (declarations.isNotEmpty)
            'tools': [
              {'functionDeclarations': declarations},
            ],
          'generationConfig': {'temperature': 0.2},
        },
      );
      if (response == null) {
        if (_lastError is GeminiException &&
            (_lastError as GeminiException).isQuota) {
          return AiAgentResult(
            text: switch (language) {
              AppLanguage.french =>
                'La limite quotidienne de l’assistant est atteinte. Réessayez demain.',
              AppLanguage.english =>
                'The assistant\'s daily limit has been reached. Try again tomorrow.',
              _ => 'وصلتَ إلى الحد اليومي لاستعمال المساعد. حاول غداً.',
            },
            steps: steps,
            isError: true,
          );
        }
        return AiAgentResult(
          text: switch (language) {
            AppLanguage.french =>
              'Impossible de joindre le modèle Gemini. Vérifiez la clé et la connexion.',
            AppLanguage.english =>
              'Could not reach the Gemini model. Check the key and the connection.',
            _ =>
              'تعذر الاتصال بنموذج Gemini. تحقق من المفتاح والاتصال بالإنترنت.',
          },
          steps: steps,
          isError: true,
        );
      }
      usedModel = model;
      final candidate = (response['candidates'] as List?)?.firstOrNull as Map?;
      final content = candidate?['content'] as Map?;
      final parts = (content?['parts'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final calls = [
        for (final part in parts)
          if (part['functionCall'] is Map)
            Map<String, dynamic>.from(part['functionCall'] as Map),
      ];
      if (calls.isEmpty) {
        final text = parts
            .where((p) => p['thought'] != true)
            .map((p) => p['text']?.toString() ?? '')
            .join()
            .trim();
        return AiAgentResult(
          text: text.isEmpty
              ? switch (language) {
                  AppLanguage.french => 'Je n’ai pas de réponse à donner.',
                  AppLanguage.english => 'I have no answer to give.',
                  _ => 'لم أجد ما أجيب به.',
                }
              : text,
          steps: steps,
          model: usedModel,
          navigateTo: _navigateTo,
        );
      }

      // Keep the model turn exactly as returned (it may carry thought
      // signatures the next request must echo), then answer every call.
      contents.add(Map<String, dynamic>.from(content!));
      final responses = <Map<String, dynamic>>[];
      for (final call in calls) {
        final name = call['name']?.toString() ?? '';
        final args = Map<String, dynamic>.from(call['args'] as Map? ?? {});
        final (result, step) = await callTool(
          name,
          args,
          permissions: permissions,
          language: language,
          confirm: confirm,
        );
        steps.add(step);
        responses.add({
          'functionResponse': {'name': name, 'response': result},
        });
      }
      contents.add({'role': 'user', 'parts': responses});
    }
    return AiAgentResult(
      text: switch (language) {
        AppLanguage.french =>
          'La demande nécessite trop d’étapes ; précisez-la, s’il vous plaît.',
        AppLanguage.english =>
          'This request needs too many steps; please make it more specific.',
        _ => 'الطلب يحتاج خطوات كثيرة؛ من فضلك حدده أكثر.',
      },
      steps: steps,
      model: usedModel,
      navigateTo: _navigateTo,
    );
  }

  /// The declarations of the tools [permissions] allow, for a request's
  /// `functionDeclarations` (the Live session uses them too).
  List<Map<String, dynamic>> functionDeclarations(
    AiAgentPermissions permissions,
    AppLanguage language,
  ) => [
    for (final t in _tools(permissions, language))
      {'name': t.name, 'description': t.description, 'parameters': t.parameters},
  ];

  /// The screen the last [callTool] of `open_screen` asked for.
  String? get navigateTo => _navigateTo;

  /// Runs the tool [name] under [permissions], asking [confirm] first when it
  /// changes data. Returns the function response and the trace line.
  Future<(Map<String, dynamic>, String)> callTool(
    String name,
    Map<String, dynamic> args, {
    required AiAgentPermissions permissions,
    required AppLanguage language,
    required AiConfirm confirm,
  }) async {
    final tool = _tools(permissions, language)
        .where((t) => t.name == name)
        .firstOrNull;
    if (tool == null) {
      return (<String, dynamic>{'error': 'this tool is not available to this user'}, '⚠️ $name');
    }
    final approval = tool.confirm?.call(args);
    final approved =
        approval == null || await confirm(approval.$1, approval.$2);
    if (!approved) {
      return (<String, dynamic>{'status': 'cancelled by the user'}, '✋ $name');
    }
    try {
      final result = await tool.run(args);
      return (
        Map<String, dynamic>.from(_plain(result) as Map),
        '${approval == null ? '🔎' : '✅'} $name',
      );
    } catch (error) {
      return (<String, dynamic>{'error': error.toString()}, '⚠️ $name');
    }
  }

  static List<Map<String, dynamic>> _history(List<Map<String, String>> turns) {
    final result = <Map<String, dynamic>>[];
    for (final turn in turns.reversed.take(20).toList().reversed) {
      final text = turn['content']?.trim() ?? '';
      if (text.isEmpty) continue;
      final role = turn['role'] == 'user' ? 'user' : 'model';
      if (result.isEmpty && role != 'user') continue;
      if (result.isNotEmpty && result.last['role'] == role) {
        final parts = result.last['parts'] as List;
        parts.add({'text': text});
      } else {
        result.add({
          'role': role,
          'parts': [
            {'text': text},
          ],
        });
      }
    }
    // The new user message follows; history must end on a model turn.
    if (result.isNotEmpty && result.last['role'] == 'user') result.removeLast();
    return result;
  }

  Object? _lastError;

  /// Sends [body] to the first model that answers.
  Future<(Map<String, dynamic>?, String?)> _generate({
    required List<String> models,
    required Map<String, dynamic> body,
  }) async {
    for (final model in models.toSet()) {
      try {
        return (await gateway.generate(model, body), model);
      } catch (error) {
        _lastError = error;
        debugPrint('Gemini $model failed: $error');
        // The daily limit applies to every model.
        if (error is GeminiException && error.isQuota) break;
      }
    }
    return (null, null);
  }
}
