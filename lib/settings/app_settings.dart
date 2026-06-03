import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../sql_database.dart';

bool get isAdmin {
  final user = FirebaseAuth.instance.currentUser;
  return user?.email == 'kouidrihamza45@gmail.com';
}

enum AppLanguage { arabic, french, english }
enum CostMethod { linearMeter, squareMeter, percentage }

class AppSettingsProvider extends ChangeNotifier {
  // Default values
  AppLanguage _language = AppLanguage.arabic;
  ThemeMode _themeMode = ThemeMode.light;
  CostMethod _costMethod = CostMethod.linearMeter;
  double _profitMargin = 0.0;
  double _fontSizeScale = 1.0;
  String _geminiApiKey = 'AQ.Ab8RN6K0VzsqO944GLUZOKqevI4ncAbuewu7Cx8pEUg3O-xVaA';

  String _userRole = 'manager';
  String _workshopCode = '';
  Map<String, dynamic> _workerPermissions = {};

  // Getters
  AppLanguage get language => _language;
  ThemeMode get themeMode => _themeMode;
  CostMethod get costMethod => _costMethod;
  double get profitMargin => _profitMargin;
  double get fontSizeScale => _fontSizeScale;
  String get geminiApiKey => _geminiApiKey;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
  String get userRole => _userRole;
  String get workshopCode => _workshopCode;
  bool get isManager => _userRole == 'manager' || isAdmin;

  AppSettingsProvider() {
    _loadSettings();
  }

  Future<void> reloadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('user_role') ?? 'manager';
    _workshopCode = prefs.getString('workshop_code') ?? '';
    
    if (_userRole == 'worker') {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final db = SqlDatabase();
        final employees = await db.readEmployees();
        try {
          final me = employees.firstWhere((e) => e['uid'] == user.uid);
          _workerPermissions = jsonDecode(me['permissions_json']);
        } catch (e) {
          _workerPermissions = {};
        }
      }
    }
    notifyListeners();
  }

  // RBAC Permission Checkers
  bool canViewClients() => isManager || _workerPermissions['view_clients'] == true;
  bool canCreateClients() => isManager || _workerPermissions['create_clients'] == true;
  bool canViewOrders() => isManager || _workerPermissions['view_orders'] == true;
  bool canCreateOrders() => isManager || _workerPermissions['create_orders'] == true;
  bool canViewClientDetails() => isManager || _workerPermissions['view_client_details'] == true;
  bool canViewOrderDetails() => isManager || _workerPermissions['view_order_details'] == true;
  bool canChangePrices() => isManager || _workerPermissions['change_prices'] == true;
  bool canAccessTreasury() => isManager || _workerPermissions['treasury'] == true;
  bool canManageWorkers() => isManager || _workerPermissions['manage_workers'] == true;
  bool canRegisterPurchases() => isManager || _workerPermissions['purchases'] == true;
  bool canViewStatistics() => isManager || _workerPermissions['statistics'] == true;

  // Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Language
    final langIndex = prefs.getInt('app_language') ?? 0;
    _language = AppLanguage.values[langIndex];

    // Load Theme
    final isDark = prefs.getBool('app_is_dark') ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

    // Load Cost Method
    final costIndex = prefs.getInt('app_cost_method') ?? 0;
    _costMethod = CostMethod.values[costIndex];
    _profitMargin = prefs.getDouble('app_profit_margin') ?? 20.0; // Default 20%

    // Load Font Size
    _fontSizeScale = prefs.getDouble('app_font_scale') ?? 1.0;

    // Load API Key — always use the latest key
    const latestKey = 'AQ.Ab8RN6K0VzsqO944GLUZOKqevI4ncAbuewu7Cx8pEUg3O-xVaA';
    String savedKey = prefs.getString('app_gemini_api_key') ?? '';
    // إذا كان المفتاح المحفوظ هو القديم أو فارغ، استخدم الجديد
    if (savedKey.isEmpty || savedKey == 'AQ.Ab8RN6IG6H5dVvsdAM0aPusDJrTfJ2-SNA22NToPNklSb-27IQ') {
      _geminiApiKey = latestKey;
      await prefs.setString('app_gemini_api_key', latestKey);
    } else {
      _geminiApiKey = savedKey;
    }

    await reloadPermissions();
  }

  // Setters with save functionality
  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_language', lang.index);
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_is_dark', mode == ThemeMode.dark);
  }

  Future<void> setCostMethod(CostMethod method) async {
    _costMethod = method;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_cost_method', method.index);
  }

  Future<void> setProfitMargin(double margin) async {
    _profitMargin = margin;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_profit_margin', margin);
  }

  Future<void> setFontSizeScale(double scale) async {
    _fontSizeScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_font_scale', scale);
  }

  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_gemini_api_key', key);
  }
}
