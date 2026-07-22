import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/volet.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/selected_systems_screen.dart';

class ChooseSysteme extends StatefulWidget {
  final Map<String, dynamic>? initialSettings;
  const ChooseSysteme({super.key, this.initialSettings});

  @override
  State<ChooseSysteme> createState() => _ChooseSystemeState();
}

class _ChooseSystemeState extends State<ChooseSysteme> {
  late final SqlDatabase db = SqlDatabase();

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
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: Text(
          Localization.translate(
            "نظام الورشة - اختيار النظام",
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: Localization.translate('تعديل الأنظمة المفعلة', Provider.of<AppSettingsProvider>(context).language),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SelectedSystemsScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20),
            // قسم العنوان
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.window, color: isDark ? Colors.blue.shade300 : Colors.blue, size: 30),
                  SizedBox(height: 10),
                  Text(
                    Localization.translate(
                      'اختر نظام العمل',
                      Provider.of<AppSettingsProvider>(context).language,
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
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // قائمة الأنظمة
            Container(
              margin: EdgeInsets.symmetric(horizontal: 15),
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
                children: [
                  // نظام الجرار - Sliding
                  ItemBuildSystem(
                    width: 60,
                    height: 60,
                    title: 'System Sliding (جرار)',
                    iconPath: 'Icon/sli.png',
                    // تم التغيير حسب الصورة السابقة
                    onTap: () {
                      _navigateToSystem(context, 'sliding');
                    },
                  ),
                  Divider(height: 1, indent: 10, endIndent: 10),

                  // نظام الفتح (فرنسي) - Beating/Casement
                  ItemBuildSystem(
                    width: 70,
                    height: 70,
                    title: 'System Beating (فرنسي)',
                    iconPath: 'Icon/french.png',
                    onTap: () {
                      _navigateToSystem(context, 'french');
                    },
                  ),
                  Divider(height: 1, indent: 10, endIndent: 10),

                  // نظام مختلط - Mixed System
                  ItemBuildSystem(
                    width: 60,
                    height: 60,
                    title: 'System Mixed (مختلط)',
                    iconPath: 'Icon/french.png',
                    onTap: () {
                      _navigateToSystem(context, 'mixed');
                    },
                  ),
                  Divider(height: 1, indent: 10, endIndent: 10),

                  ItemBuildSystem(
                    width: 60,
                    height: 60,
                    title: 'System Roling',
                    iconPath: 'Icon/roling.png',
                    onTap: () {
                      _navigateToSystem(context, '');
                    },
                  ),
                  Divider(height: 1, indent: 10, endIndent: 10),
                  ItemBuildSystem(
                    width: 60,
                    height: 60,
                    title: 'Caisson Tunnel',
                    iconPath: 'Icon/caisson_tunnel.jpg',
                    onTap: () {
                      _navigateToSystem(context, 'caisson_tunnel');
                    },
                  ),
                  Divider(height: 1, indent: 10, endIndent: 10),
                  ItemBuildSystem(
                    width: 60,
                    height: 60,
                    title: 'Pre-cadre',
                    iconPath: 'Icon/french.png',
                    onTap: () {
                      _navigateToSystem(context, 'precadre');
                    },
                  ),
                  Divider(height: 1, indent: 10, endIndent: 10),
                  ItemBuildSystem(
                    width: 60,
                    height: 60,
                    title: 'Verre Tremper',
                    iconPath: 'Icon/verre.png',
                    onTap: () {
                      _navigateToSystem(context, 'verre');
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 500),
          ],
        ),
      ),
    );
  }

  void _navigateToSystem(BuildContext context, String systemType) async {
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
          padding: EdgeInsets.symmetric(vertical: 20, horizontal: 15),
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
              SizedBox(width: 20),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Spacer(),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
