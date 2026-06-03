import 'package:database_data/Cliente/show_client.dart';
import 'package:database_data/Screen/show_dialog.dart';
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

  String formatDate(String date) {
    final parsed = DateTime.parse(date);
    return DateFormat('yyyy-MM-dd').format(parsed);
  }

  TextSpan highlightText(String text, String query) {
    if (query.isEmpty) {
      return TextSpan(text: text);
    }

    List<String> queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (queryWords.isEmpty) return TextSpan(text: text);

    String pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    RegExp regExp = RegExp('($pattern)', caseSensitive: false);

    List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, backgroundColor: Colors.yellow.withOpacity(0.3)),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return TextSpan(children: spans);
  }

  final TextEditingController searchController = TextEditingController();
  String query = '';

  late Future<List<Map<String, dynamic>>> _data;

  @override
  void initState() {
    super.initState();
    _data = db.readClient();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate("Customers", Provider.of<AppSettingsProvider>(context).language),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            margin: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(Localization.translate("Your Clients :", Provider.of<AppSettingsProvider>(context).language),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 5),
            padding: EdgeInsets.all(5),
            child: TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {
                  query = value;

                  if (query.isEmpty) {
                    _data = db.readClient();
                  } else {
                    _data = db.searchClient(query);
                  }
                  highlightText(query, query);
                });
              },
              decoration: InputDecoration(
                hintText: "Search by name or phone",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          //Divider(color: Colors.orangeAccent, thickness: 1),
          Expanded(
            child: FutureBuilder(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  final data = snapshot.data!;
                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final id = data[index]['id'] ?? '';
                      final firstName = data[index]['firstname'] ?? '';
                      final lastName = data[index]['lastname'] ?? '';
                      return Card(
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ShowClient(clientId: id),
                              ),
                            );
                          },
                          onLongPress: () {
                            showDialog(
                              context: context,
                              builder: (dialogContext) {
                                return DynamicDialog(
                                  title: "Update Client",
                                  content: '',
                                  button: "Update",
                                  fields: [
                                    FormFieldConfig(
                                      label: "First Name",
                                      type: FieldType.text,
                                      initialValue: data[index]['firstname'],
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
                                      initialValue: data[index]['lastname'],
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
                                      keyboardType: TextInputType.phone,
                                      maxLenght: 10,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        // 👈 يمنع الحروف
                                      ],
                                      initialValue: data[index]['phone1']
                                          .toString(),
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
                                      keyboardType: TextInputType.phone,
                                      maxLenght: 10,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      initialValue: data[index]['phone2']
                                          .toString(),
                                    ),
                                    FormFieldConfig(
                                      label: "Email",
                                      type: FieldType.text,
                                      initialValue: data[index]['email'],
                                    ),
                                    FormFieldConfig(
                                      label: "Address",
                                      type: FieldType.text,
                                      initialValue: data[index]['address'],
                                    ),
                                  ],
                                  onSubmit: (values) async {
                                    await db.updateClient(
                                      id,
                                      values[0],
                                      values[1],
                                      values[2],
                                      values[3],
                                      values[4],
                                      values[5],
                                      DateTime.now().toIso8601String(),
                                    );
                                    setState(() {
                                      _data = db.readClient();
                                    });
                                  },
                                );
                              },
                            );
                          },
                          leading: CircleAvatar(
                            child: Text((index + 1).toString()),
                          ),
                          title: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                              ),
                              children: [
                                highlightText(lastName, query),
                                const TextSpan(text: " "),
                                highlightText(firstName, query),
                              ],
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                data[index]['phone1'].toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(width: 20),
                              Text(" ${formatDate(data[index]['created_at'])}",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            onPressed: () {
                              db.deleteClient(id);
                              setState(() {
                                _data = db.readClient();
                              });
                            },
                            icon: Icon(Icons.delete),
                          ),
                        ),
                      );
                    },
                  );
                }
                return Center(child: Text(Localization.translate("No Data", Provider.of<AppSettingsProvider>(context).language)));
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
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
                  ),
                  FormFieldConfig(label: "Email", type: FieldType.text),
                  FormFieldConfig(label: "Address", type: FieldType.text),
                ],
                onSubmit: (values) async {
                  try {
                    await db.insertClient(
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
                  
                  if (!context.mounted) return;
                  
                  setState(() {
                    _data = query.isEmpty ? db.readClient() : db.searchClient(query);
                  });
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
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
