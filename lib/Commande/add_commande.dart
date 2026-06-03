import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../sql_database.dart';
import 'choose_systems.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/show_dialog.dart';
import 'package:flutter/services.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/window_painter.dart';

class CommandePage extends StatefulWidget {
  final SqlDatabase db;

  const CommandePage({super.key, required this.db});

  @override
  State<CommandePage> createState() => _CommandePageState();
}

class _CommandePageState extends State<CommandePage> {
  String? selectedClient;

  TextEditingController clientController = TextEditingController();
  TextEditingController quoteDateController = TextEditingController();
  TextEditingController validDateController = TextEditingController();
  TextEditingController controller = TextEditingController();
  
  List<WindowModel> addedProducts = [];

  String get today => DateFormat('yyyy/MM/dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();

    quoteDateController.text = today;
    validDateController.text = DateFormat(
      'yyyy/MM/dd',
    ).format(DateTime.now().add(Duration(days: 14)));
  }

  Future<void> pickDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );

    if (date != null) {
      controller.text = DateFormat('yyyy/MM/dd').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(Localization.translate("New Quotation", Provider.of<AppSettingsProvider>(context).language)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _buildField(
              label: "${Localization.translate('Customer', Provider.of<AppSettingsProvider>(context).language)} *",
              controller: clientController,
              icon: Icons.person,
              suffix: Icons.search,
              onTap: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => ClientDropdownDialog(db: widget.db),
                );

                if (result != null) {
                  setState(() {
                    selectedClient = result;
                    clientController.text = result;
                  });
                }
              },
            ),

            SizedBox(height: 15),

            _buildField(
              label: "Quote date *",
              controller: quoteDateController,
              icon: Icons.calendar_today,
              onTap: () => pickDate(quoteDateController),
            ),

            SizedBox(height: 15),

            _buildField(
              label: "Valid till Date *",
              controller: validDateController,
              icon: Icons.calendar_today,
              onTap: () => pickDate(validDateController),
            ),
            SizedBox(height: 15),

            ...addedProducts.map((p) => _buildProductCard(p)),
            if (addedProducts.isNotEmpty) SizedBox(height: 15),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 60),
                backgroundColor: Colors.blue,
                elevation: 5,
                shadowColor: Colors.blue.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () async {
                if (selectedClient == null || selectedClient!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(Localization.translate("Please select a client", Provider.of<AppSettingsProvider>(context, listen: false).language))),
                  );
                } else {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChooseSysteme(),
                    ),
                  );
                  if (result != null && result is WindowModel) {
                    setState(() {
                      addedProducts.add(result);
                    });
                  }
                }
              },
              icon: Icon(Icons.add, color: Colors.white),
              label: Text(Localization.translate('Add Product', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            SizedBox(height: 15),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {},
              icon: Icon(Icons.add, color: Colors.white),
              label: Text(Localization.translate('Add Product Special', Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 15),

            TextField(
              controller: controller,
                decoration: InputDecoration(
                  hintText: Localization.translate('Notes', Provider.of<AppSettingsProvider>(context).language),
                  border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 4,
            ),
            SizedBox(height: 15),
            if (Provider.of<AppSettingsProvider>(context).canChangePrices()) ...[
              _buildField(
                label: Localization.translate('Remise', Provider.of<AppSettingsProvider>(context).language),
                controller: controller, // Note: currently sharing the notes controller
                icon: Icons.percent,
              ),
              SizedBox(height: 15),
              _buildField(
                label: Localization.translate('Tax Tva', Provider.of<AppSettingsProvider>(context).language),
                controller: controller,
                icon: Icons.percent,
              ),
              SizedBox(height: 15),
            ],
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              margin: EdgeInsets.all(0),
              decoration: BoxDecoration(
                border: Border.all(width: 1, color: Colors.grey),
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.5),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [],
                  ),
                  SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.description, color: Colors.blue),
                      SizedBox(width: 10),
                      Text(Localization.translate('Description', Provider.of<AppSettingsProvider>(context).language),
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(Localization.translate('Totale Sans Tva :', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(fontSize: 18)),
                      SizedBox(width: 50),
                      Text("0.0 DZD", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(Localization.translate('Tax (Tva) :', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(fontSize: 18)),
                      SizedBox(width: 50),
                      Text("0.0 DZD", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Divider(color: Colors.white, thickness: 1.5, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(Localization.translate('Totale Avec Tva :', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(fontSize: 18)),
                      SizedBox(width: 50),
                      Builder(
                        builder: (context) {
                          final settings = Provider.of<AppSettingsProvider>(context);
                          double rawTotal = addedProducts.fold(0.0, (sum, p) => sum + p.totalCost);
                          double finalTotal = rawTotal;
                          if (settings.costMethod == CostMethod.percentage) {
                            finalTotal = rawTotal * (1 + settings.profitMargin / 100);
                          }
                          return Text('${finalTotal.toStringAsFixed(2)} DZD', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green));
                        }
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 60),
                backgroundColor: Colors.blue,
                elevation: 5,
                shadowColor: Colors.blue.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () async {
                if (selectedClient == null || addedProducts.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(Localization.translate("Please select a client and add products", Provider.of<AppSettingsProvider>(context, listen: false).language))),
                  );
                  return;
                }
                
                final settings = Provider.of<AppSettingsProvider>(context, listen: false);
                double rawTotal = addedProducts.fold(0.0, (sum, p) => sum + p.totalCost);
                double total = rawTotal;
                if (settings.costMethod == CostMethod.percentage) {
                  total = rawTotal * (1 + settings.profitMargin / 100);
                }
                
                int commandeId = await widget.db.insertCommande(
                  int.parse(selectedClient!),
                  "Pending",
                  controller.text,
                  0.0,
                  0.0,
                  total,
                  advancePayment: 0.0,
                );
                
                for (var p in addedProducts) {
                  await widget.db.insertCommandeDetail(
                    idCommande: commandeId,
                    largeur: p.width,
                    hauteur: p.height,
                    windowType: p.zones.any((z) => z.content == ZoneContent.doubleSash) ? 'Double Sash' : 'Single Sash',
                    partitionsJson: '{}', // Can be replaced with actual json serialization if needed
                    price: p.totalCost,
                    color: p.frameColor.toString().split('.').last,
                    glass: p.zones.isNotEmpty && p.zones.first.glass.structure == GlassStructure.double ? 'Double' : 'Single',
                    volet: p.hasShutter ? 'Yes' : 'No',
                  );
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(Localization.translate("Saved successfully!", Provider.of<AppSettingsProvider>(context, listen: false).language))),
                );
                Navigator.pop(context);
              },
              icon: Icon(Icons.save, color: Colors.white),
              label: Text(Localization.translate("Save", Provider.of<AppSettingsProvider>(context).language),
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            SizedBox(height: 250),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    IconData? suffix,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: Colors.blueAccent),
          suffixIcon: suffix != null ? Icon(suffix, color: Colors.blueAccent) : null,
          filled: true,
          fillColor: Colors.transparent,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.blueAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(WindowModel p) {
    String colorStr = p.frameColor.toString().split('.').last;
    if (colorStr == 'white') {
      colorStr = 'أبيض';
    } else if (colorStr == 'brown') colorStr = 'بني فاتح (Faux Bois)';
    else if (colorStr == 'gray') colorStr = 'رمادي';
    else if (colorStr == 'black') colorStr = 'أسود';
    else if (colorStr == 'beige') colorStr = 'بيج / FBM';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'نافذة ${p.zones.any((z) => z.content == ZoneContent.doubleSash) ? 'بضلفتين' : 'بضلفة واحدة'} - ${p.width.toInt()}x${p.height.toInt()} mm',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() { addedProducts.remove(p); });
                  },
                )
              ],
            ),
            const Divider(),
            Center(
              child: Column(
                children: [
                  const Text('شكل النافذة', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Container(
                    height: 120,
                    width: 120,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: const Size(100, 100),
                        painter: WindowPainter(model: p),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Text('اللون: $colorStr', style: const TextStyle(fontSize: 15)),
            Text('الزجاج: ${p.zones.isNotEmpty && p.zones.first.glass.structure == GlassStructure.double ? "مزدوج" : "مفرد"}', style: const TextStyle(fontSize: 15)),
            if (p.hasShutter) const Text('الستار: موجود (Volet)', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('المجموع: ${p.totalCost.toStringAsFixed(2)} دج', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class ClientDropdownDialog extends StatefulWidget {
  final SqlDatabase db;

  const ClientDropdownDialog({super.key, required this.db});

  @override
  State<ClientDropdownDialog> createState() => _ClientDropdownDialogState();
}

class _ClientDropdownDialogState extends State<ClientDropdownDialog> {
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> filtered = [];

  TextEditingController search = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    final data = await widget.db.readClient();

    setState(() {
      clients = data;
      filtered = data;
    });
  }

  // 🔥 Normalize (remove diacritics, tatweel, unify alifs/haas)
  String normalizeArabic(String text) {
    return text.toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0640]'), '');
  }

  // 🔥 Smart match (all words must exist somewhere in the row)
  bool matchClient(Map<String, dynamic> c, String query) {
    if (query.trim().isEmpty) return true;
    
    List<String> qTerms = query.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    
    final first = normalizeArabic(c['firstname'] ?? '');
    final last = normalizeArabic(c['lastname'] ?? '');
    final phone1 = normalizeArabic(c['phone1'] ?? '');
    final phone2 = normalizeArabic(c['phone2'] ?? '');
    
    final full = "$first $last $phone1 $phone2";
    
    return qTerms.every((term) {
      final t = normalizeArabic(term);
      return full.contains(t);
    });
  }

  // 🔥 Safe highlight (no index crash)
  TextSpan highlightText(String text, String query) {
    if (query.trim().isEmpty) {
      return TextSpan(
        text: text,
        style: TextStyle(color: Colors.black),
      );
    }

    List<String> queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (queryWords.isEmpty) return TextSpan(text: text, style: TextStyle(color: Colors.black));

    String pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    RegExp regExp = RegExp('($pattern)', caseSensitive: false);

    List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: TextStyle(color: Colors.black)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, backgroundColor: Colors.yellow.withOpacity(0.3)),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: Colors.black)));
    }

    return TextSpan(children: spans);
  }

  void searchClient(String value) {
    setState(() {
      if (value.isEmpty) {
        filtered = clients;
      } else {
        filtered = clients.where((c) {
          return matchClient(c, value);
        }).toList();
      }
    });
  }

  void _showAddClientDialog() {
    String initialFirst = search.text;
    String initialLast = '';

    if (search.text.contains(' ')) {
      var parts = search.text.split(RegExp(r'\s+'));
      initialFirst = parts.first;
      initialLast = parts.sublist(1).join(' ');
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return DynamicDialog(
          title: "Add Client",
          content: '',
          button: "Add",
          fields: [
            FormFieldConfig(
              label: "First Name",
              type: FieldType.text,
              initialValue: initialFirst,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter a first name";
                }
                return null;
              },
            ),
            FormFieldConfig(
              label: "Last Name",
              type: FieldType.text,
              initialValue: initialLast,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter a last name";
                }
                return null;
              },
            ),
            FormFieldConfig(
              label: "Phone Number 1",
              type: FieldType.text,
              keyboardType: TextInputType.number,
              maxLenght: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter a phone number";
                }
                return null;
              },
            ),
            FormFieldConfig(
              label: "Phone Number 2",
              type: FieldType.text,
              keyboardType: TextInputType.number,
              maxLenght: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            FormFieldConfig(label: "Email", type: FieldType.text),
            FormFieldConfig(label: "Address", type: FieldType.text),
          ],
          onSubmit: (values) async {
            try {
              await widget.db.insertClient(
                values[0],
                values[1],
                values[2],
                values[3],
                values[4],
                values[5],
              );
            } catch (e) {
              print("Error inserting client: $e");
            }

            if (!mounted) return;

            final data = await widget.db.readClient();
            setState(() {
              clients = data;
            });
            searchClient(search.text);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(Localization.translate("Client added", Provider.of<AppSettingsProvider>(context, listen: false).language)),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(30)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Localization.translate("Select Client", Provider.of<AppSettingsProvider>(context).language),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: searchClient,
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.person_add, color: Colors.white),
                    onPressed: _showAddClientDialog,
                    tooltip: Localization.translate('Add Client', Provider.of<AppSettingsProvider>(context).language),
                  ),
                ),
              ],
            ),

            SizedBox(height: 10),

            SizedBox(
              height: 250,
              child: filtered.isEmpty && search.text.isNotEmpty
                  ? Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: _showAddClientDialog,
                        icon: Icon(Icons.person_add, color: Colors.white),
                        label: Text(
                          '${Localization.translate('إضافة', Provider.of<AppSettingsProvider>(context).language)} "${search.text}"',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];

                        return ListTile(
                          title: RichText(
                            text: highlightText("${c['firstname']} ${c['lastname']}",
                              search.text,
                            ),
                          ),
                          trailing: RichText(
                            text: highlightText("${c['phone1']}", search.text),
                          ),
                          onTap: () {
                            Navigator.pop(
                              context,
                              "${c['firstname']} ${c['lastname']}",
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
