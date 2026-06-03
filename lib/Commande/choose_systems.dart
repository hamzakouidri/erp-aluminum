import 'package:flutter/material.dart';

import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:database_data/Commande/Systeme/volet.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class ChooseSysteme extends StatefulWidget {
  const ChooseSysteme({super.key});

  @override
  State<ChooseSysteme> createState() => _ChooseSystemeState();
}

class _ChooseSystemeState extends State<ChooseSysteme> {
  late final WindowModel model;
  late final SqlDatabase db = SqlDatabase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          Localization.translate(
            "نظام الورشة - اختيار النظام",
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue,
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
                  Icon(Icons.window, color: Colors.blue, size: 30),
                  SizedBox(height: 10),
                  Text(
                    Localization.translate(
                      'اختر نظام العمل',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(
                      fontSize: 22,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    Localization.translate(
                      'حدد نوع النافذة للبدء في الحسابات',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // قائمة الأنظمة
            Container(
              margin: EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                border: Border.all(width: 1, color: Colors.grey),
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
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
                    title: 'Verre Tremper',
                    iconPath: 'Icon/verre.png',
                    onTap: () {
                      _navigateToSystem(context, '');
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
    double defaultW = 0;
    double defaultH = 0;

    switch (systemType) {
      case 'sliding':
        targetPage = WindowView(
          systemMode: 'sliding',
          model: WindowModel(
            width: defaultW,
            height: defaultH,
            profileThickness: 45,
            db: db,
          ),
        );
        break;
      case 'french':
        targetPage = WindowView(
          systemMode: 'french',
          model: WindowModel(
            width: defaultW,
            height: defaultH,
            profileThickness: 60,
            db: db,
          ),
        );
        break;
      case 'rolling':
        targetPage = WindowView(
          model: WindowModel(
            width: defaultW,
            height: defaultH,
            profileThickness: 30,
            db: db,
          ),
        );
        break;
      default:
        targetPage = SystemRoling(model: WindowModel(db: db));
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
    return Material(
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20, horizontal: 15),
          child: Row(
            children: [
              // تصحيح المسار ليكون مطابقاً لما في الـ pubspec والمجلد
              Image.asset(
                widget.iconPath,
                width: widget.width,
                height: widget.height,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.image_not_supported, color: Colors.grey),
              ),
              SizedBox(width: 20),
              Text(
                widget.title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
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
