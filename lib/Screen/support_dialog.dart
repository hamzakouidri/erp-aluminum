import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportDialog extends StatefulWidget {
  const SupportDialog({super.key});

  @override
  _SupportDialogState createState() => _SupportDialogState();
}

class _SupportDialogState extends State<SupportDialog> {
  int _rating = 0;
  final TextEditingController _msgController = TextEditingController();

  void _sendToWhatsApp() async {
    final String message =
        "تقييم التطبيق: $_rating نجوم\nالملاحظة/الشكوى: ${_msgController.text}";
    final String url =
        "whatsapp://send?phone=213554301484&text=${Uri.encodeComponent(message)}";

    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لا يمكن فتح التطبيق. يرجى التأكد من تثبيت واتساب.'),
          ),
        );
      }
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ساعدنا في تحسين التطبيق'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ما هو تقييمك للتطبيق؟'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = index + 1;
                    });
                  },
                );
              }),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _msgController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'اكتب ملاحظتك، شكواك، أو اقتراحك هنا...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: _rating > 0 ? _sendToWhatsApp : null,
          icon: Icon(Icons.send, color: Colors.white),
          label: Text(
            'إرسال عبر واتساب',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
