import 'package:database_data/Cliente/show_client.dart';
import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class Customers extends StatefulWidget {
  const Customers({super.key});

  @override
  State<Customers> createState() => _CustomersState();
}

class _CustomersState extends State<Customers> {
  final SqlDatabase db = SqlDatabase();
  final TextEditingController searchController = TextEditingController();
  String _searchQuery = '';

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
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.yellow.withValues(alpha: 0.3),
        ),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(children: spans);
  }

  @override
  void initState() {
    super.initState();
    _data = db.readClient();
  }

  void _refreshData() {
    setState(() {
      _data = _searchQuery.isEmpty
          ? db.readClient()
          : db.searchClient(_searchQuery);
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
                    Provider.of<AppSettingsProvider>(context, listen: false).language,
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

  void _showUpdateClientDialog(BuildContext context, Map<String, dynamic> client) {
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
              DateTime.now().toIso8601String(),
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          Localization.translate("Customers", lang),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
      ),
      body: Column(
        children: [
          // 🔍 Filter section — matches commande.dart style
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
                          ? db.readClient()
                          : db.searchClient(val);
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
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
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
                                Localization.translate("Error loading data", lang),
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
                                  border: Border.all(color: Colors.red.shade200),
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
                                  side: BorderSide(color: Colors.red.shade200, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                onPressed: _refreshData,
                                icon: const Icon(Icons.refresh_rounded, size: 22),
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

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
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
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                            SizedBox(height: 35),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue.shade600,
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
                              icon: const Icon(Icons.person_add_outlined, size: 24),
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
                  final rawData = snapshot.data!;
                  final data = rawData.where((d) {
                    final q = _searchQuery.toLowerCase().trim();
                    if (q.isEmpty) return true;
                    final first = (d['firstname'] ?? '').toString().toLowerCase();
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

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          phone2.isNotEmpty && phone2 != '0' && phone2 != 'null';

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
                                      builder: (context) => ShowClient(clientId: id),
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
                                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue.shade100,
                            child: const Icon(
                              Icons.person,
                              color: Colors.blue,
                            ),
                          ),
                          title: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).brightness == Brightness.dark
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
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                    children: [
                                      WidgetSpan(
                                        child: Icon(
                                          Icons.phone,
                                          size: 14,
                                          color: Theme.of(context).brightness == Brightness.dark
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
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    _showUpdateClientDialog(context, item);
                                  },
                                ),
                              if (settings.canDeleteClients())
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(
                                          Localization.translate("Delete Client", lang),
                                        ),
                                        content: Text(
                                          Localization.translate(
                                            "Are you sure you want to delete this client?",
                                            lang,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text(
                                              Localization.translate("Cancel", lang),
                                            ),
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
                                      _refreshData();
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

      floatingActionButton: settings.canCreateClients()
          ? FloatingActionButton(
              onPressed: () => _showAddClientDialog(context),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Theme.of(context).floatingActionButtonTheme.backgroundColor ?? Colors.blue,
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
    _phone1Controller = TextEditingController(text: c['phone1']?.toString() ?? '');
    _phone2Controller = TextEditingController(text: c['phone2']?.toString() ?? '');
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
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isEdit = widget.client != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              isEdit ? Localization.translate("Update Client", lang) : Localization.translate("Add Client", lang),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isEdit) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              icon: Icon(_showCompanyDetails ? Icons.keyboard_arrow_up : Icons.business, size: 18),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (value) => value == null || value.isEmpty ? Localization.translate("Please enter a first name", lang) : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastnameController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("Last Name", lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (value) => value == null || value.isEmpty ? Localization.translate("Please enter a last name", lang) : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone1Controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: Localization.translate("Phone Number 1", lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    counterText: '',
                  ),
                  validator: (value) => value == null || value.isEmpty ? Localization.translate("Please enter a phone number", lang) : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone2Controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: Localization.translate("Phone Number 2", lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("Email", lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: Localization.translate("Address", lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                          style: TextStyle(fontSize: 12, color: Colors.blue[800], fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nifController,
                    decoration: InputDecoration(
                      labelText: 'الرقم التعريفي الجبائي / NIF',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nisController,
                    decoration: InputDecoration(
                      labelText: 'الرقم التعريفي الإحصائي / NIS',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rcController,
                    decoration: InputDecoration(
                      labelText: 'السجل التجاري / RC',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _aiController,
                    decoration: InputDecoration(
                      labelText: 'رقم المادة / AI',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
          child: Text(isEdit ? Localization.translate("Update", lang) : Localization.translate("Add", lang)),
        ),
      ],
    );
  }
}
