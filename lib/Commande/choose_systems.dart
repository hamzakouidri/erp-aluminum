import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/volet.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/selected_systems_screen.dart';
import 'package:database_data/Screen/caisson_tunnel_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChooseSysteme extends StatefulWidget {
  final Map<String, dynamic>? initialSettings;
  const ChooseSysteme({super.key, this.initialSettings});

  @override
  State<ChooseSysteme> createState() => _ChooseSystemeState();
}

class _ChooseSystemeState extends State<ChooseSysteme> {
  late final SqlDatabase db = SqlDatabase();

  Map<String, bool> _activeModes = {
    'sliding': true,
    'french': true,
    'mixed': true,
    'rolling': true,
    'caisson_tunnel': true,
    'precadre': true,
    'verre': true,
  };

  @override
  void initState() {
    super.initState();
    _loadActiveModes();
  }

  Future<void> _loadActiveModes() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _activeModes = {
        'sliding': prefs.getBool('system_active_sliding') ?? true,
        'french': prefs.getBool('system_active_french') ?? true,
        'mixed': prefs.getBool('system_active_mixed') ?? true,
        'rolling': prefs.getBool('system_active_rolling') ?? true,
        'caisson_tunnel': prefs.getBool('system_active_caisson_tunnel') ?? true,
        'precadre': prefs.getBool('system_active_precadre') ?? true,
        'verre': prefs.getBool('system_active_verre') ?? true,
      };
    });
  }

  WindowModel _makeModel({double w = 0, double h = 0, double thickness = 60}) {
    final m = WindowModel(width: w, height: h, profileThickness: thickness, db: db);
    final s = widget.initialSettings;
    if (s != null) {
      if (s['frameColor'] != null)             m.frameColor             = s['frameColor'];
      if (s['selectedDbColor'] != null)        m.selectedDbColor        = s['selectedDbColor'];
      if (s['selectedAccessoryColor'] != null) m.selectedAccessoryColor = s['selectedAccessoryColor'];
      if (s['hasShutter'] == true)             m.hasShutter             = true;
      if (s['shutterLame'] != null)            m.shutterLame            = s['shutterLame'];
      if (s['shutterGlissiere'] != null)       m.shutterGlissiere       = s['shutterGlissiere'];
      if (s['shutterMechanism'] != null)       m.shutterMechanism       = s['shutterMechanism'];
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final systemItems = <Widget>[];

    if (_activeModes['sliding'] ?? true) {
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'System Sliding (جرار)',
          iconPath: 'Icon/sli.png',
          onTap: () => _navigateToSystem(context, 'sliding'),
        ),
      );
    }

    if (_activeModes['french'] ?? true) {
      if (systemItems.isNotEmpty) systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 70,
          height: 70,
          title: 'System Beating (فرنسي)',
          iconPath: 'Icon/french.png',
          onTap: () => _navigateToSystem(context, 'french'),
        ),
      );
    }

    if (_activeModes['mixed'] ?? true) {
      if (systemItems.isNotEmpty) systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'System Mixed (مختلط)',
          iconPath: 'Icon/french.png',
          onTap: () => _navigateToSystem(context, 'mixed'),
        ),
      );
    }

    if (_activeModes['rolling'] ?? true) {
      if (systemItems.isNotEmpty) systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'System Roling',
          iconPath: 'Icon/roling.png',
          onTap: () => _navigateToSystem(context, ''),
        ),
      );
    }

    if (_activeModes['caisson_tunnel'] ?? true) {
      if (systemItems.isNotEmpty) systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'Caisson Tunnel',
          iconPath: 'Icon/caisson_tunnel.jpg',
          onTap: () => _navigateToSystem(context, 'caisson_tunnel'),
        ),
      );
    }

    if (_activeModes['precadre'] ?? true) {
      if (systemItems.isNotEmpty) systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'Pre-cadre',
          iconPath: 'Icon/french.png',
          onTap: () => _navigateToSystem(context, 'precadre'),
        ),
      );
    }

    if (_activeModes['verre'] ?? true) {
      if (systemItems.isNotEmpty) systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'Verre Tremper',
          iconPath: 'Icon/verre.png',
          onTap: () => _navigateToSystem(context, 'verre'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: Text(
          Localization.translate(
            "نظام الورشة - اختيار النظام",
            lang,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: Localization.translate('تعديل الأنظمة المفعلة', lang),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SelectedSystemsScreen()),
              );
              _loadActiveModes();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // قسم العنوان
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.window, color: isDark ? Colors.blue.shade300 : Colors.blue, size: 30),
                  const SizedBox(height: 10),
                  Text(
                    Localization.translate(
                      'اختر نظام العمل',
                      lang,
                    ),
                    style: TextStyle(
                      fontSize: 22,
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    Localization.translate(
                      'حدد نوع النافذة للبدء في الحسابات',
                      lang,
                    ),
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // قائمة الأنظمة المحدثة بناءً على الإعدادات النشطة
            if (systemItems.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 48, color: Colors.orange.shade400),
                    const SizedBox(height: 16),
                    Text(
                      Localization.translate('جميع أنظمة العمل معطلة حالياً بالورشة.', lang),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Localization.translate('يمكنك تفعيل الأنظمة التي تستعملها بالضغط على زر الضبط أعلاه.', lang),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(
                        Localization.translate('تعديل الأنظمة المفعلة', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SelectedSystemsScreen()),
                        );
                        _loadActiveModes();
                      },
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  border: Border.all(width: 1, color: isDark ? Colors.grey.shade800 : Colors.grey),
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.2),
                      spreadRadius: 5,
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: systemItems,
                ),
              ),
            const SizedBox(height: 500),
          ],
        ),
      ),
    );
  }

  void _navigateToSystem(BuildContext context, String systemType) async {
    if (systemType == 'caisson_tunnel') {
      final caissonResult = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CaissonTunnelScreen()),
      );
      if (caissonResult != null && caissonResult is Map<String, dynamic> && context.mounted) {
        final int cBars = (caissonResult['grandTotalCaissonBars'] as int? ?? 0);
        final int bBars = (caissonResult['grandTotalBottomCoverBars'] as int? ?? 0);
        final int pairs = (caissonResult['grandTotalPairs'] as int? ?? 0);

        final model = _makeModel(w: 1000, h: 300);
        model.isCaissonTunnel = true;
        model.isReplaced = false;
        model.manualNameOverride = 'Caisson Tunnel';
        model.description = 'الكيت: ${caissonResult['kitType']} | بارات كيسون: $cBars (6م) | أغطية سفلية: $bBars (6م) | أغطية جانبية: $pairs زوج';
        model.quantity = 1;
        model.caissonPayload = caissonResult;

        Navigator.pop(context, model);
      }
      return;
    }

    Widget targetPage;

    switch (systemType) {
      case 'sliding':
        targetPage = WindowView(
          systemMode: 'sliding',
          model: _makeModel(thickness: 45),
        );
        break;
      case 'french':
        targetPage = WindowView(
          systemMode: 'french',
          model: _makeModel(thickness: 60),
        );
        break;
      case 'mixed':
        targetPage = WindowView(
          systemMode: 'mixed',
          model: _makeModel(thickness: 60),
        );
        break;
      case 'rolling':
        targetPage = WindowView(
          model: _makeModel(thickness: 30),
        );
        break;
      default:
        targetPage = SystemRoling(model: _makeModel());
        break;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => targetPage),
    );

    if (result != null) {
      if (context.mounted) Navigator.pop(context, result);
    }
  }
}

//==========================================ItemBuildSystem================================
class ItemBuildSystem extends StatefulWidget {
  final String title;
  final String iconPath;
  final VoidCallback onTap;
  final double? width;

  final double? height;

  const ItemBuildSystem({
    super.key,
    required this.title,
    required this.iconPath,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  State<ItemBuildSystem> createState() => _ItemBuildSystemState();
}

class _ItemBuildSystemState extends State<ItemBuildSystem> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      borderRadius: BorderRadius.circular(10),
      color: isDark ? Colors.transparent : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
          child: Row(
            children: [
              if (widget.title.toLowerCase().contains('mixed') || widget.title.contains('مختلط'))
                SizedBox(
                  width: widget.width ?? 60,
                  height: widget.height ?? 60,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: (widget.width ?? 60) * 0.65,
                        child: Image.asset(
                          'Icon/french.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.image_not_supported, color: Colors.grey, size: 24),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: (widget.width ?? 60) * 0.65,
                        child: Image.asset(
                          'Icon/sli.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.image_not_supported, color: Colors.grey, size: 24),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Image.asset(
                  widget.iconPath,
                  width: widget.width,
                  height: widget.height,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              const SizedBox(width: 20),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
