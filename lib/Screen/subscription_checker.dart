import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'welcom_screen.dart';
import 'subscription_expired_screen.dart';
import '../settings/app_settings.dart';

class SubscriptionChecker extends StatelessWidget {
  const SubscriptionChecker({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('لم يتم تسجيل الدخول')));
    }

    if (isAdmin) {
      return const WelcomScreen();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('حدث خطأ أثناء فحص الاشتراك: ${snapshot.error}')),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // حساب غير موجود أو قديم جداً وليس مدير، يتم حظره
          return const SubscriptionExpiredScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        
        // 1. التحقق من الحظر للعامل
        if (data['isBlocked'] == true) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block, color: Colors.red, size: 80),
                    const SizedBox(height: 20),
                    const Text('تم إيقاف حسابك', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 10),
                    const Text('تم منعك من الدخول للتطبيق من قبل مدير الورشة.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                      child: const Text('تسجيل الخروج'),
                    )
                  ],
                ),
              ),
            ),
          );
        }

        // 2. العمال لا يحتاجون لاشتراك (المدير هو من يدفع)
        if (data['role'] == 'worker') {
          return const WelcomScreen();
        }

        // 3. اشتراك المدير
        // إذا كان الاشتراك مفعلاً بشكل صريح (تم الدفع)
        if (data['subscriptionStatus'] == 'active') {
          return const WelcomScreen();
        }

        // إذا كان حساب تجريبي
        if (data['trialEndDate'] != null) {
          try {
            final trialEnd = DateTime.parse(data['trialEndDate'] as String);
            if (DateTime.now().isBefore(trialEnd)) {
              // ما زال في فترة التجربة
              return const WelcomScreen();
            } else {
              // انتهت فترة التجربة
              return const SubscriptionExpiredScreen();
            }
          } catch (e) {
            // خطأ في صيغة التاريخ
            return const SubscriptionExpiredScreen();
          }
        }

        // افتراضياً الدخول ممنوع لغير المدير إلا إذا كان لديه اشتراك فعال
        return const SubscriptionExpiredScreen();
      },
    );
  }
}
