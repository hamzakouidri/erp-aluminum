import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/supabase_account_service.dart';
import '../settings/app_settings.dart';

enum PaymentMethodType {
  edahabia, // البطاقة الذهبية
  cib, // بطاقة CIB البنكية
  baridiMob, // بريدي موب (تحويل فوري / RIP / QR)
  visaMastercard, // كارت فيزا وماستركارد
}

class SubscriptionPlan {
  final String id;
  final String titleAr;
  final String titleFr;
  final String titleEn;
  final String durationLabelAr;
  final String durationLabelFr;
  final String durationLabelEn;
  final String? badgeAr;
  final String? badgeFr;
  final String? badgeEn;
  final int durationDays;
  final double priceDzd;
  final double? originalPriceDzd;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.titleAr,
    required this.titleFr,
    required this.titleEn,
    required this.durationLabelAr,
    required this.durationLabelFr,
    required this.durationLabelEn,
    this.badgeAr,
    this.badgeFr,
    this.badgeEn,
    required this.durationDays,
    required this.priceDzd,
    this.originalPriceDzd,
    this.isPopular = false,
  });

  String getTitle(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return titleFr;
      case AppLanguage.english:
        return titleEn;
      case AppLanguage.arabic:
        return titleAr;
    }
  }

  String getDurationLabel(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return durationLabelFr;
      case AppLanguage.english:
        return durationLabelEn;
      case AppLanguage.arabic:
        return durationLabelAr;
    }
  }

  String? getBadge(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return badgeFr;
      case AppLanguage.english:
        return badgeEn;
      case AppLanguage.arabic:
        return badgeAr;
    }
  }
}

class AlgerianPaymentService {
  static final AlgerianPaymentService _instance = AlgerianPaymentService._internal();
  factory AlgerianPaymentService() => _instance;
  AlgerianPaymentService._internal();

  static const String _defaultTestSecretKey = 'test_sk_sample_chargily_key';

  /// Standard plans offered for workshops
  static const List<SubscriptionPlan> defaultPlans = [
    SubscriptionPlan(
      id: 'monthly',
      titleAr: 'شهر (30 يوما)',
      titleFr: '1 mois (30 jours)',
      titleEn: '1 Month (30 days)',
      durationLabelAr: 'شهر (30 يوما)',
      durationLabelFr: '1 mois (30 jours)',
      durationLabelEn: '1 month (30 days)',
      durationDays: 30,
      priceDzd: 3000.0,
    ),
    SubscriptionPlan(
      id: 'two_months',
      titleAr: 'اشتراك شهرين',
      titleFr: 'Abonnement 2 mois',
      titleEn: '2 Months Subscription',
      durationLabelAr: 'شهران (60 يوما)',
      durationLabelFr: '2 mois (60 jours)',
      durationLabelEn: '2 months (60 days)',
      durationDays: 60,
      priceDzd: 5500.0,
      originalPriceDzd: 6000.0,
    ),
    SubscriptionPlan(
      id: 'quarterly',
      titleAr: 'اشتراك 3 أشهر',
      titleFr: 'Abonnement 3 mois',
      titleEn: '3 Months Subscription',
      durationLabelAr: '3 أشهر (90 يوما)',
      durationLabelFr: '3 mois (90 jours)',
      durationLabelEn: '3 months (90 days)',
      durationDays: 90,
      priceDzd: 8000.0,
      originalPriceDzd: 9000.0,
      isPopular: true,
      badgeAr: 'الأكثر طلباً',
      badgeFr: 'Le plus demandé',
      badgeEn: 'Most Popular',
    ),
    SubscriptionPlan(
      id: 'yearly',
      titleAr: 'اشتراك سنوي (الأفضل قيمة)',
      titleFr: 'Abonnement annuel (Meilleure valeur)',
      titleEn: 'Annual Subscription (Best value)',
      durationLabelAr: '12 شهر (365 يوما)',
      durationLabelFr: '12 mois (365 jours)',
      durationLabelEn: '12 months (365 days)',
      durationDays: 365,
      priceDzd: 25000.0,
      originalPriceDzd: 36000.0,
      badgeAr: 'الأفضل قيمة',
      badgeFr: 'Meilleure valeur',
      badgeEn: 'Best Value',
    ),
    SubscriptionPlan(
      id: 'lifetime',
      titleAr: 'اشتراك دائم للورشة (مدى الحياة)',
      titleFr: 'Abonnement permanent atelier (À vie)',
      titleEn: 'Permanent Workshop Subscription (Lifetime)',
      durationLabelAr: 'مدى الحياة',
      durationLabelFr: 'À vie',
      durationLabelEn: 'Lifetime',
      durationDays: 36500,
      priceDzd: 65000.0,
      badgeAr: 'مدى الحياة',
      badgeFr: 'À vie',
      badgeEn: 'Lifetime',
    ),
  ];

  /// Reads configured Chargily API credentials from Firestore or SharedPreferences
  Future<Map<String, dynamic>> getPaymentGatewayConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('payment_gateway')
          .get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    return {
      'secret_key': prefs.getString('chargily_secret_key') ?? _defaultTestSecretKey,
      'is_live': prefs.getBool('chargily_is_live') ?? false,
      'baridi_mob_rip': prefs.getString('baridi_mob_rip') ?? '00799999000000000000',
    };
  }

  /// Saves Chargily API credentials (Admin only)
  Future<void> savePaymentGatewayConfig({
    required String secretKey,
    required bool isLive,
    String? baridiMobRip,
  }) async {
    final cleanKey = secretKey.trim();
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('payment_gateway')
          .set({
        'secret_key': cleanKey,
        'is_live': isLive,
        if (baridiMobRip != null) 'baridi_mob_rip': baridiMobRip.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chargily_secret_key', cleanKey);
    await prefs.setBool('chargily_is_live', isLive);
    if (baridiMobRip != null) {
      await prefs.setString('baridi_mob_rip', baridiMobRip.trim());
    }
  }

  /// Creates a secure Chargily Pay V2 Checkout session
  Future<Map<String, dynamic>?> createChargilyCheckout({
    required SubscriptionPlan plan,
    required PaymentMethodType paymentMethod,
    required String workshopId,
    required String userEmail,
  }) async {
    final config = await getPaymentGatewayConfig();
    final secretKey = (config['secret_key'] ?? '').toString().trim();
    final isLive = config['is_live'] == true;

    final baseUrl = isLive
        ? 'https://pay.chargily.net/api/v2'
        : 'https://pay.chargily.net/test/api/v2';

    // Map payment method to Chargily V2 payload parameter
    String? chargilyMethod;
    if (paymentMethod == PaymentMethodType.edahabia) {
      chargilyMethod = 'edahabia';
    } else if (paymentMethod == PaymentMethodType.cib) {
      chargilyMethod = 'cib';
    }

    final body = {
      'items': [
        {
          'price_data': {
            'title': '${plan.titleAr} (${plan.durationLabelAr}) - تطبيق الأمنيوم',
            'amount': (plan.priceDzd * 100).toInt(), // Amount in centimes
            'currency': 'dzd',
          },
          'quantity': 1,
        }
      ],
      if (chargilyMethod != null) 'payment_method': chargilyMethod,
      'success_url': 'https://erp-alum.web.app/payment/success',
      'failure_url': 'https://erp-alum.web.app/payment/failure',
      'metadata': {
        'workshop_id': workshopId,
        'plan_id': plan.id,
        'duration_days': plan.durationDays,
        'user_email': userEmail,
      },
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/checkouts'),
        headers: {
          'Authorization': 'Bearer $secretKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'checkout_id': data['id'],
          'checkout_url': data['checkout_url'],
          'status': data['status'],
        };
      } else {
        debugPrint('Chargily checkout error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error creating Chargily checkout: $e');
    }
    return null;
  }

  /// Verifies a Chargily checkout status
  Future<String?> checkCheckoutStatus(String checkoutId) async {
    final config = await getPaymentGatewayConfig();
    final secretKey = (config['secret_key'] ?? '').toString().trim();
    final isLive = config['is_live'] == true;

    final baseUrl = isLive
        ? 'https://pay.chargily.net/api/v2'
        : 'https://pay.chargily.net/test/api/v2';

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/checkouts/$checkoutId'),
        headers: {
          'Authorization': 'Bearer $secretKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status']?.toString();
      }
    } catch (e) {
      debugPrint('Error checking checkout status: $e');
    }
    return null;
  }

  /// Activates the subscription in Supabase and Firestore after successful payment
  Future<bool> activatePaidSubscription({
    required String workshopId,
    required int durationDays,
    required String planId,
    required String transactionReference,
    required double amountDzd,
  }) async {
    final now = DateTime.now();
    final endsAt = now.add(Duration(days: durationDays));

    try {
      // 1. Activate in Supabase
      if (workshopId.isNotEmpty) {
        await SupabaseAccountService().setSubscriptionForWorkshopId(
          workshopId: workshopId,
          status: 'active',
          planType: planId,
          endsAt: endsAt,
        );
      }

      // 2. Record payment in Firestore logs
      await FirebaseFirestore.instance.collection('subscription_payments').add({
        'workshop_id': workshopId,
        'user_id': AppAuthService().currentUser?.uid,
        'user_email': AppAuthService().currentUser?.email,
        'amount_dzd': amountDzd,
        'plan_id': planId,
        'duration_days': durationDays,
        'starts_at': now.toIso8601String(),
        'ends_at': endsAt.toIso8601String(),
        'transaction_ref': transactionReference,
        'status': 'completed',
        'created_at': now.toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error activating paid subscription: $e');
      return false;
    }
  }

  /// Submits a manual BaridiMob transfer notification for review
  Future<bool> submitBaridiMobReceipt({
    required String workshopId,
    required String transactionNumber,
    required double amountDzd,
    required int durationDays,
    String? notes,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('baridimob_submissions').add({
        'workshop_id': workshopId,
        'user_id': AppAuthService().currentUser?.uid,
        'user_email': AppAuthService().currentUser?.email,
        'transaction_number': transactionNumber.trim(),
        'amount_dzd': amountDzd,
        'duration_days': durationDays,
        'notes': notes?.trim() ?? '',
        'status': 'pending_verification',
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error submitting BaridiMob receipt: $e');
      return false;
    }
  }
}
