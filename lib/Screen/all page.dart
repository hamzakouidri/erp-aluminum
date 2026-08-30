import 'package:database_data/Screen/settings_screen.dart';
import 'package:database_data/Screen/welcom_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'drawer.dart'; // تأكد من مسار ملف AppDrawer الخاص بك

// 🟢 كلاس يمثل علامة التبويب المفتوحة
class AppTab {
  final String id;
  final String title;
  final Widget content;
  final IconData icon;

  AppTab({
    required this.id,
    required this.title,
    required this.content,
    required this.icon,
  });
}

// 🟢 الـ Provider المسؤول عن إدارة التبويبات في الذاكرة من أي مكان في التطبيق
class TabProvider extends ChangeNotifier {
  final List<AppTab> _openTabs = [];
  int _currentIndex = 0;

  List<AppTab> get openTabs => _openTabs;

  int get currentIndex => _currentIndex;

  // تهيئة الشاشة الرئيسية الافتراضية
  void initDefaultTab(Widget defaultScreen) {
    if (_openTabs.isEmpty) {
      _openTabs.add(
        AppTab(
          id: 'home_1',
          title: 'Home',
          icon: Icons.dashboard_rounded,
          content: defaultScreen,
        ),
      );
    }
  }

  // دالة فتح تبوّيبة جديدة من أي مكان
  void openTab(String title, IconData icon, Widget screenContent) {
    int existingIndex = _openTabs.indexWhere((tab) => tab.title == title);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else {
      _openTabs.add(
        AppTab(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          icon: icon,
          content: screenContent,
        ),
      );
      _currentIndex = _openTabs.length - 1;
    }
    notifyListeners();
  }

  // دالة إغلاق التبويبة
  void closeTab(int index) {
    _openTabs.removeAt(index);
    if (_currentIndex >= _openTabs.length) {
      _currentIndex = _openTabs.length - 1;
    }
    notifyListeners();
  }

  // دالة التنقل بين التبويبات المفتوحة
  void changeIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }
}

// 🟢 واجهة العرض الرئيسية للتبويبات
class MultiTabScreen extends StatelessWidget {
  const MultiTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // جلب بيانات التبويبات من الـ Provider
    final tabProvider = Provider.of<TabProvider>(context);
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // تأمين وجود الشاشة الرئيسية الافتراضية عند أول تشغيل
    tabProvider.initDefaultTab(const WelcomScreen());

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          Localization.translate('نظام إدارة الورشة (ERP)', lang),
        ),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: Localization.translate('الإعدادات', lang),
            onPressed: () {
              tabProvider.openTab(
                'الإعدادات',
                Icons.settings,
                const SettingsScreen(),
              );
            },
          ),
        ],
      ),
      drawer: AppDrawer(), // القائمة الجانبية الحقيقية الخاصة بك
      body: tabProvider.openTabs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // شريط علامات التبويب العلوي
                Container(
                  height: 50,
                  color: Colors.blueGrey.shade800,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: tabProvider.openTabs.length,
                    itemBuilder: (context, index) {
                      bool isActive = index == tabProvider.currentIndex;
                      var currentTab = tabProvider.openTabs[index];
                      return GestureDetector(
                        onTap: () => tabProvider.changeIndex(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          margin: const EdgeInsets.only(
                            top: 8,
                            right: 4,
                            left: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.grey.shade100
                                : Colors.blueGrey.shade700,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10),
                              topRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                currentTab.icon,
                                size: 16,
                                color: isActive
                                    ? Colors.blueGrey.shade900
                                    : Colors.white70,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Localization.translate(currentTab.title, Provider.of<AppSettingsProvider>(context).language),
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.blueGrey.shade900
                                      : Colors.white70,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (tabProvider.openTabs.length > 1)
                                InkWell(
                                  onTap: () => tabProvider.closeTab(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isActive
                                          ? Colors.grey.shade300
                                          : Colors.blueGrey.shade600,
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: isActive
                                          ? Colors.black87
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // عرض الشاشة النشطة مع الحفاظ على البقية في الذاكرة المشتركة
                Expanded(
                  child: IndexedStack(
                    index: tabProvider.currentIndex,
                    children: tabProvider.openTabs
                        .map((tab) => tab.content)
                        .toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
