// import 'package:flutter/material.dart';
// import 'model.dart'; // تأكد من المسار الصحيح
//
// class ShowResultCalcule extends StatefulWidget {
//   final double width;
//   final double height;
//   final WindowModel?
//   model; // تمرير الموديل للحصول على الإعدادات (شتر، بروفايل...)
//
//   const ShowResultCalcule({
//     super.key,
//     required this.width,
//     required this.height,
//     this.model,
//   });
//
//   @override
//   State<ShowResultCalcule> createState() => _ShowResultCalculeState();
// }
//
// class _ShowResultCalculeState extends State<ShowResultCalcule> {
//   late WindowModel myWindowModel;
//
//   @override
//   void initState() {
//     // نستخدم الموديل الممرر أو ننشئ واحداً جديداً بالقيم الأساسية
//     myWindowModel =
//         widget.model ??
//         WindowModel(
//           width: widget.width,
//           height: widget.height,
//           type: WindowType.doubleSash, // افتراضي
//         );
//     super.initState();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // 1. نقوم بحساب البيانات وتخزينها في متغير قبل رسم الواجهة
//     final data = calculateMaterials(myWindowModel);
//
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("حساب الكميات والسلع"),
//         backgroundColor: Colors.blueAccent,
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             // بطاقة عرض ملخص الأبعاد
//             _buildHeaderCard(),
//             const SizedBox(height: 20),
//
//             // عرض النتائج في جدول أنيق بدلاً من Dialog
//             Container(
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(15),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.grey.withValues(alpha: 0.2),
//                     blurRadius: 10,
//                   ),
//                 ],
//               ),
//               child: Table(
//                 border: TableBorder.symmetric(
//                   inside: BorderSide(color: Colors.grey.shade200),
//                 ),
//                 columnWidths: const {
//                   0: FlexColumnWidth(2),
//                   1: FlexColumnWidth(1),
//                 },
//                 children: [
//                   _buildTableRow('Cadre(إطار)', '${data['frame']} pare'),
//                   _buildTableRow('Ouvrante', '${data['sash']} pare'),
//                   _buildTableRow('Verre', '${data['glass']}M2'),
//                   if (myWindowModel.hasShutter)
//                     _buildTableRow('Lame', '${data['volet']} pare'),
//                   _buildTableRow('Paumelle', '${data['hinges']} piece'),
//                   _buildTableRow('Poignee', '${data['handles']} piece'),
//                   _buildTableRow('ESP', '${data['esp']} piece'),
//                   _buildTableRow(
//                     'الوزن الإجمالي التقريبي',
//                     '${data['total_weight_approx'].toStringAsFixed(2)} كغ',
//                     isHighlight: true,
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 30),
//
//             ElevatedButton.icon(
//               onPressed: () {
//                 _showInfoDialog();
//                 ScaffoldMessenger.of(
//                   context,
//                 ).showSnackBar(const SnackBar(content: Text("")));
//               },
//               icon: const Icon(Icons.info),
//               label: const Text("Info"),
//               style: ElevatedButton.styleFrom(
//                 minimumSize: const Size(double.infinity, 50),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//                 backgroundColor: Colors.green[200],
//               ),
//             ),
//             SizedBox(height: 15),
//             ElevatedButton.icon(
//               onPressed: () {
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   const SnackBar(content: Text("تم حفظ تقرير السلع بنجاح")),
//                 );
//               },
//               icon: const Icon(Icons.save_alt),
//               label: const Text("تصدير ملف الكميات"),
//               style: ElevatedButton.styleFrom(
//                 minimumSize: const Size(double.infinity, 50),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//                 backgroundColor: Colors.blue[200],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // بطاقة علوية توضح مقاس النافذة المختار
//   Widget _buildHeaderCard() {
//     return Container(
//       padding: const EdgeInsets.all(15),
//       decoration: BoxDecoration(
//         color: Colors.blue.shade50,
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: Colors.blue.shade200),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceAround,
//         children: [
//           _headerItem("العرض", "${widget.width.toInt()} mm"),
//           const Icon(Icons.close, size: 15, color: Colors.blue),
//           _headerItem("الارتفاع", "${widget.height.toInt()} mm"),
//         ],
//       ),
//     );
//   }
//
//   Widget _headerItem(String title, String value) {
//     return Column(
//       children: [
//         Text(
//           title,
//           style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
//         ),
//         Text(
//           value,
//           style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
//         ),
//       ],
//     );
//   }
//
//   void _showInfoDialog() {
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: const Text('Informations de Conception'),
//           content: SingleChildScrollView(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 _buildInfoRow('Largeur', '${myWindowModel.width.toInt()} mm'),
//                 _buildInfoRow('Hauteur', '${myWindowModel.height.toInt()} mm'),
//                 const Divider(),
//                 _buildInfoRow(
//                   'Type',
//                   myWindowModel.type.toString().split('.')[1],
//                 ),
//                 _buildInfoRow(
//                   'Volet',
//                   myWindowModel.hasShutter ? 'Oui' : 'Non',
//                 ),
//                 _buildInfoRow(
//                   'Couverture',
//                   myWindowModel.showBottomCover ? 'Visible' : 'Cachée',
//                 ),
//                 _buildInfoRow(
//                   'État',
//                   myWindowModel.isOpen ? 'Ouvert' : 'Fermé',
//                 ),
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text('Fermer'),
//             ),
//           ],
//         );
//       },
//     );
//   }
//
//   /// Constructeur pour une ligne d'information
//   Widget _buildInfoRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 8),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
//           Text(value, style: TextStyle(color: Colors.grey.shade700)),
//         ],
//       ),
//     );
//   }
// }
//
// // دالة الحساب المحدثة
// Map<String, dynamic> calculateMaterials(dynamic myWindowModel) {
//   double w = myWindowModel.width / 1000;
//   double h = myWindowModel.height / 1000;
//
//   double frameLength = (h * 2) + (myWindowModel.showFrameBottom ? w * 2 : w);
//   double renfort = frameLength;
//   int esp = 1;
//
//   int sashCount = (myWindowModel.type == WindowType.doubleSash) ? 2 : 1;
//   double sashW = (myWindowModel.type == WindowType.doubleSash) ? (w / 2) : w;
//
//   // حساب دقيق لأطوال الضلفة
//   double sashLength = sashCount * ((h * 4) + (sashW * 4));
//
//   double glassArea = (w - 0.324) * (h - 0.17);
//   double shutterArea = myWindowModel.hasShutter ? (w * (h + 0.2)) : 0;
//
//   int hinges = (h * 1000 < 1000) ? 2 : (h * 1000 < 2100 ? 3 : 4);
//   hinges *= sashCount;
//
//   // حساب الوزن بناءً على نوع البروفايل (ميزة إضافية)
//   // إذا كان 105 يكون أثقل (مثلاً 1.4 كجم للمتر) وإذا 104 يكون (1.2 كجم)
//   double weightFactor =
//       (myWindowModel.sashProfiles.isNotEmpty &&
//           myWindowModel.sashProfiles[0] == 105)
//       ? 1.4
//       : 1.2;
//
//   return {
//     'frame': frameLength.toStringAsFixed(2),
//     'sash': sashLength.toStringAsFixed(2),
//     'renfore': renfort.toStringAsFixed(2),
//     'glass': glassArea.toStringAsFixed(2),
//     'volet': shutterArea.toStringAsFixed(2),
//     'hinges': hinges,
//     'esp': esp,
//     'handles': esp,
//     'total_weight_approx': (frameLength + sashLength) * weightFactor,
//   };
// }
//
// TableRow _buildTableRow(
//   String label,
//   String value, {
//   bool isHighlight = false,
// }) {
//   return TableRow(
//     children: [
//       Padding(
//         padding: const EdgeInsets.all(15.0),
//         child: Text(
//           label,
//           style: TextStyle(
//             fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
//           ),
//         ),
//       ),
//       Padding(
//         padding: const EdgeInsets.all(15.0),
//         child: Text(
//           value,
//           style: TextStyle(
//             fontWeight: FontWeight.bold,
//             color: isHighlight ? Colors.blue.shade900 : Colors.black87,
//           ),
//         ),
//       ),
//     ],
//   );
// }
