import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({Key? key}) : super(key: key);

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  @override
  void initState() {
    super.initState();
    // نحن نركز فقط على مخزون الورشة حالياً، وقسمناه إلى عدة فئات (بروفيلات، زجاج، إكسسوارات)
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('مخزون الورشة')),
        backgroundColor: Colors.teal,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.category), text: _t('البروفيلات')),
            Tab(icon: const Icon(Icons.window), text: _t('الزجاج')),
            Tab(icon: const Icon(Icons.build), text: _t('الإكسسوارات')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPlaceholder(_t('قائمة بروفيلات الألمنيوم/PVC في الورشة')),
          _buildPlaceholder(_t('قائمة الزجاج المتاح في الورشة')),
          _buildPlaceholder(_t('قائمة الإكسسوارات (مقابض، عجلات، الخ)')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: إضافة عنصر جديد للمخزون
        },
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPlaceholder(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 20),
          Text(text, style: const TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 10),
          Text(
            _t('هذه الصفحة مبدئية للنقاش حول التفاصيل'),
            style: TextStyle(fontSize: 14, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
