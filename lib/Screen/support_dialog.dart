import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class SupportDialog extends StatefulWidget {
  const SupportDialog({super.key});

  @override
  State<SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<SupportDialog> {
  int _rating = 0;
  final TextEditingController _msgController = TextEditingController();
  bool _isSending = false;

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  void _sendToWhatsApp() async {
    final ratingText = _rating > 0 ? '$_rating نجوم' : 'لم يتم تحديد تقييم';
    final userMsg = _msgController.text.trim();
    final String message =
        "مراسلة الإدارة وتقديم شكوى / ملاحظة:\n• تقييم التطبيق: $ratingText\n• الملاحظة أو الشكوى:\n${userMsg.isNotEmpty ? userMsg : 'لا توجد تفاصيل إضافية'}";

    final encodedMessage = Uri.encodeComponent(message);
    final String webUrl = "https://wa.me/213554301484?text=$encodedMessage";
    final String appUrl = "whatsapp://send?phone=213554301484&text=$encodedMessage";

    setState(() => _isSending = true);

    try {
      final webUri = Uri.parse(webUrl);
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        final appUri = Uri.parse(appUrl);
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('تعذر فتح واتساب تلقائياً. يرجى التواصل مباشرة على الرقم: 0554301484')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canSend = _rating > 0 || _msgController.text.trim().isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_rounded, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'مراسلة الإدارة وتقييم التطبيق',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ما هو تقييمك للتطبيق؟',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = index + 1;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            const Text(
              'اكتب ملاحظتك أو شكواك للإدارة:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _msgController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _t('اكتب ملاحظتك، شكواك، أو اقتراحك هنا وسنتابعها مباشرة معك...'),
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_t('إلغاء')),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: canSend && !_isSending ? _sendToWhatsApp : null,
          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          label: Text(
            _isSending ? 'جاري الإرسال...' : 'إرسال عبر واتساب',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
