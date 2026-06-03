import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class JointsScreen extends StatefulWidget {
  final SqlDatabase db;
  const JointsScreen({super.key, required this.db});

  @override
  State<JointsScreen> createState() => _JointsScreenState();
}

class _JointsScreenState extends State<JointsScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readJoints();
    setState(() {
      _items = items;
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final thicknessCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Localization.translate('Ø¥Ø¶Ø§ÙØ© Ø¬ÙˆØ§Ù† Ø¬Ø¯ÙŠØ¯', Provider.of<AppSettingsProvider>(context).language),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: Localization.translate('Ø§Ø³Ù… Ø§Ù„Ø¬ÙˆØ§Ù†', Provider.of<AppSettingsProvider>(context).language))),
            TextField(controller: thicknessCtrl, decoration: InputDecoration(labelText: Localization.translate('Ø§Ù„Ø³Ù…Ø§ÙƒØ©', Provider.of<AppSettingsProvider>(context).language))),
            TextField(controller: priceCtrl, decoration: InputDecoration(labelText: Localization.translate('Ø³Ø¹Ø± Ø§Ù„Ù…ØªØ±', Provider.of<AppSettingsProvider>(context).language))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Localization.translate('Ø¥Ù„ØºØ§Ø¡', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                await widget.db.insertJoint(
                  nameCtrl.text,
                  double.tryParse(thicknessCtrl.text) ?? 0.0,
                  double.tryParse(priceCtrl.text) ?? 0.0,
                );
                _loadItems();
                Navigator.pop(context);
              }
            },
            child: Text(Localization.translate('Ø­ÙØ¸', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item, bool isUserAdmin) {
    final nameCtrl = TextEditingController(text: item['name'].toString());
    final thicknessCtrl = TextEditingController(text: item['thickness'].toString());
    final priceCtrl = TextEditingController(text: item['price_per_meter'].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Localization.translate('ØªØ¹Ø¯ÙŠÙ„', Provider.of<AppSettingsProvider>(context).language),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, enabled: isUserAdmin, decoration: InputDecoration(labelText: Localization.translate('Ø§Ø³Ù… Ø§Ù„Ø¬ÙˆØ§Ù†', Provider.of<AppSettingsProvider>(context).language))),
            TextField(controller: thicknessCtrl, enabled: isUserAdmin, decoration: InputDecoration(labelText: Localization.translate('Ø§Ù„Ø³Ù…Ø§ÙƒØ©', Provider.of<AppSettingsProvider>(context).language))),
            TextField(controller: priceCtrl, decoration: InputDecoration(labelText: Localization.translate('Ø³Ø¹Ø± Ø§Ù„Ù…ØªØ±', Provider.of<AppSettingsProvider>(context).language))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Localization.translate('Ø¥Ù„ØºØ§Ø¡', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                await widget.db.updateJoint(
                  item['id'],
                  nameCtrl.text,
                  double.tryParse(thicknessCtrl.text) ?? 0.0,
                  double.tryParse(priceCtrl.text) ?? 0.0,
                );
                _loadItems();
                Navigator.pop(context);
              }
            },
            child: Text(Localization.translate('Ø­ÙØ¸ ×”×ªØ¹Ø¯ÙŠÙ„', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('Ø§Ù„Ø¬ÙˆØ§Ù†Ø§Øª / Ø§Ù„Ø¬Ù„Ø¯Ø§Øª', Provider.of<AppSettingsProvider>(context).language)),
      ),
      body: _items.isEmpty
          ? Center(child: Text(Localization.translate('Ù„Ø§ ØªÙˆØ¬Ø¯ Ø¨ÙŠØ§Ù†Ø§Øª', Provider.of<AppSettingsProvider>(context).language)))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(item['name'].toString(), style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item.toString()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                          onPressed: () => _showEditDialog(item, isUserAdmin),
                        ),
                        if (isUserAdmin)
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () async {
                              await widget.db.deleteJoint(item['id']);
                              _loadItems();
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: !isUserAdmin ? null : FloatingActionButton(
        onPressed: _showAddDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}
