// import 'package:database_data/show_dialog.dart';
// import 'package:database_data/sql_database.dart';
// import 'package:database_data/widgets/app_material.dart';
//
// class Home extends StatefulWidget {
//   const Home({super.key});
//
//   @override
//   State<Home> createState() => _HomeState();
// }
//
// class _HomeState extends State<Home> {
//   final SqlDatabase db = SqlDatabase();
//   String? name;
//   String? type;
//   final TextEditingController nameController = TextEditingController();
//
//   @override
//   void initState() {
//     super.initState();
//   }
//
//   @override
//   dispose() {
//     nameController.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text(Localization.translate("Home", Provider.of<AppSettingsProvider>(context).language)), centerTitle: true, actions: []),
//
//       body: Column(
//         children: [
//           Expanded(
//             child: FutureBuilder(
//               future: db.readProfile(),
//               builder: (context, snapshot) {
//                 if (snapshot.connectionState == ConnectionState.waiting) {
//                   return Center(child: CircularProgressIndicator());
//                 } else if (snapshot.hasError) {
//                   return Center(child: Text('Error: ${snapshot.error}'));
//                 } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
//                   final data = snapshot.data!;
//
//                   return ListView.builder(
//                     itemCount: data.length,
//                     itemBuilder: (context, index) {
//                       final id = data[index]['id'];
//                       return Card(
//                         child: ListTile(
//                           onTap: () {},
//                           onLongPress: () {
//                             nameController.text = data[index]['name'];
//                             type = data[index]['type'];
//                             showDialog(
//                               context: context,
//                               builder: (context) {
//                                 return DynamicDialog(
//                                   title: "Update Profile",
//                                   button: "Update",
//                                   fields: [
//                                     FormFieldConfig(
//                                       label: "Name",
//                                       type: FieldType.text,
//                                       initialValue: data[index]['name'],
//                                       validator: (value) {
//                                         if (value == null || value.isEmpty) {
//                                           return "Please enter a name";
//                                         }
//                                         return null;
//                                       },
//                                     ),
//                                     FormFieldConfig(
//                                       label: "Type",
//                                       type: FieldType.dropdown,
//                                       dropdownItems: [
//                                         "Pvc",
//                                         "Aluminum",
//                                         "Volet",
//                                       ],
//                                       initialValue: data[index]['type'],
//                                     ),
//                                   ],
//                                   onSubmit: (values) {
//                                     db.updateProfile(id, values[0], values[1]);
//                                     setState(() {});
//                                     ScaffoldMessenger.of(context).showSnackBar(
//                                       SnackBar(
//                                         content: Text(Localization.translate("Profile updated", Provider.of<AppSettingsProvider>(context).language)),
//                                         duration: Duration(seconds: 3),
//                                         behavior: SnackBarBehavior.floating,
//                                         backgroundColor: Colors.green,
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius: BorderRadius.all(
//                                             Radius.circular(20),
//                                           ),
//                                         ),
//                                       ),
//                                     );
//                                   },
//                                 );
//                               },
//                             );
//                           },
//                           textColor: Colors.blue,
//                           iconColor: Colors.red,
//                           enabled: true,
//                           tileColor: Colors.white,
//                           leading: CircleAvatar(
//                             child: Text(data[index]['id'].toString()),
//                           ),
//                           title: Text(data[index]['name'].toString()),
//                           subtitle: Text(data[index]['type'].toString()),
//                           trailing: IconButton(
//                             onPressed: () {
//                               showDialog(
//                                 context: context,
//                                 builder: (context) {
//                                   return AlertDialog(
//                                     title: Text(Localization.translate("Delete Profile", Provider.of<AppSettingsProvider>(context).language)),
//                                     content: Text(
//                                       "Are you sure you want to delete this profile?",
//                                     ),
//                                     actions: [
//                                       TextButton(
//                                         onPressed: () {
//                                           Navigator.pop(context);
//                                         },
//                                         child: Text("Cancel"),
//                                       ),
//                                       TextButton(
//                                         onPressed: () {
//                                           Navigator.pop(context);
//                                           db.deleteProfile(id);
//                                           setState(() {});
//                                         },
//                                         child: Text(Localization.translate("Delete", Provider.of<AppSettingsProvider>(context).language)),
//                                       ),
//                                     ],
//                                   );
//                                 },
//                               );
//                             },
//                             icon: Icon(Icons.delete),
//                           ),
//                         ),
//                       );
//                     },
//                   );
//                 } else {
//                   return Center(child: Text(Localization.translate("No Data", Provider.of<AppSettingsProvider>(context).language)));
//                 }
//               },
//             ),
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           showDialog(
//             context: context,
//             builder: (context) {
//               return DynamicDialog(
//                 title: "Add Profile",
//                 button: "Add",
//                 fields: [
//                   FormFieldConfig(
//                     label: "Name",
//                     type: FieldType.text,
//                     validator: (value) {
//                       if (value == null || value.isEmpty) {
//                         return "Please enter a name";
//                       }
//                       return null;
//                     },
//                   ),
//                   FormFieldConfig(
//                     label: "Type",
//                     type: FieldType.dropdown,
//                     dropdownItems: ["Pvc", "Aluminum", "Volet"],
//                     validator: (value) {
//                       if (value == null || value.isEmpty) {
//                         return "Please select a type";
//                       }
//                       return null;
//                     },
//                   ),
//                 ],
//                 onSubmit: (values) {
//                   db.insertProfile(values[0], values[1]);
//                   setState(() {});
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(
//                       content: Text(Localization.translate("Profile added", Provider.of<AppSettingsProvider>(context).language)),
//                       duration: Duration(seconds: 3),
//                       behavior: SnackBarBehavior.floating,
//                       backgroundColor: Colors.green,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.all(Radius.circular(30)),
//                       ),
//                     ),
//                   );
//                   Navigator.pop(context);
//                 },
//               );
//             },
//           );
//         },
//         child: Icon(Icons.add),
//       ),
//     );
//   }
// }
