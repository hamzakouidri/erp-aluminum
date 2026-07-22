import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/localization.dart';
import '../settings/app_settings.dart';
import 'client_ledger_screen.dart';

class ClientChronoSearchScreen extends StatefulWidget {
  const ClientChronoSearchScreen({super.key});

  @override
  State<ClientChronoSearchScreen> createState() => _ClientChronoSearchScreenState();
}

class _ClientChronoSearchScreenState extends State<ClientChronoSearchScreen> {
  final SqlDatabase db = SqlDatabase();
  List<Map<String, dynamic>> _allClients = [];
  List<Map<String, dynamic>> _filteredClients = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final myDb = await db.db;
      final data = await myDb!.query('Client', orderBy: 'lastname ASC');
      setState(() {
        _allClients = data;
        _filteredClients = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterClients(String val) {
    setState(() {
      _searchQuery = val.trim().toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredClients = _allClients;
      } else {
        _filteredClients = _allClients.where((c) {
          final first = (c['firstname'] ?? '').toString().toLowerCase();
          final last = (c['lastname'] ?? '').toString().toLowerCase();
          final phone1 = (c['phone1'] ?? '').toString().toLowerCase();
          final phone2 = (c['phone2'] ?? '').toString().toLowerCase();
          return first.contains(_searchQuery) ||
              last.contains(_searchQuery) ||
              phone1.contains(_searchQuery) ||
              phone2.contains(_searchQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          Localization.translate('كشف حساب الزبائن', lang),
          style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo'),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        foregroundColor: Theme.of(context).cardColor,
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search box
                Container(
                  padding: EdgeInsets.all(12),
                  color: Theme.of(context).cardColor,
                  child: TextField(
                    onChanged: _filterClients,
                    decoration: InputDecoration(
                      hintText: Localization.translate('بحث عن زبون...', lang),
                      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: Colors.blue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  ),
                ),
                Expanded(
                  child: _filteredClients.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                Localization.translate('لا يوجد نتائج مطابقة', lang),
                                style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _filteredClients.length,
                          itemBuilder: (context, index) {
                            final client = _filteredClients[index];
                            final first = client['firstname'] ?? '';
                            final last = client['lastname'] ?? '';
                            final fullName = '$last $first'.trim();
                            final phone = client['phone1']?.toString() ?? '';
                            final address = client['address']?.toString() ?? '';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue[50],
                                  child: Text(
                                    fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                  ),
                                ),
                                title: Text(
                                  fullName,
                                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (phone.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.phone, size: 12, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(phone, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                        ],
                                      ),
                                    if (address.isNotEmpty && address != 'null')
                                      Row(
                                        children: [
                                          const Icon(Icons.place, size: 12, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(address, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                        ],
                                      ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: Colors.blue[300],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ClientLedgerScreen(clientId: client['id'] as int),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
