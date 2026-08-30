import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:database_data/sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/subscription_service.dart';

class SubscriptionExpiredScreen extends StatelessWidget {
  const SubscriptionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(Localization.translate('انتهى الاشتراك', lang)),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 100, color: Colors.redAccent),
              const SizedBox(height: 24),
              const Text(
                'عذراً، لقد انتهت الفترة التجريبية الخاصة بك!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'للاستمرار في استخدام النظام والوصول إلى بياناتك، يرجى تفعيل الاشتراك عن طريق التواصل مع الإدارة.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const Text(
                'للتجديد، يرجى الدفع عبر بريدي موب (BaridiMob) ثم إرسال الوصل عبر واتساب.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              StreamBuilder<String>(
                stream: SubscriptionPaymentSettings().getBaridiMobRipStream(),
                builder: (context, paymentSnapshot) {
                  final rip = paymentSnapshot.data?.trim() ?? '';
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'معلومات الدفع (BaridiMob)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          rip.isEmpty ? 'لم يتم تحديد الرقم بعد' : 'CCP/RIP: $rip',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: rip.isEmpty ? Colors.orange.shade700 : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  // ضع رقم هاتفك هنا مع مفتاح الدولة (مثال للجزائر: 213)
                  final Uri url = Uri.parse(
                    'https://wa.me/213554301484?text=مرحباً، أريد تجديد اشتراكي في تطبيق إدارة الورش.',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(
                  Icons.wechat,
                ), // Using a standard icon for chat
                label: const Text(
                  'تواصل لتجديد الاشتراك (WhatsApp)',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await FirebaseAuth.instance.signOut();
                    await GoogleSignIn().signOut();
                    await SqlDatabase.clearAllLocalData();
                  } catch (e) {
                    debugPrint('Sign out error: $e');
                  }
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
