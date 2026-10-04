import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/app_settings.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/supabase_account_service.dart';

enum SubscriptionPlanType {
  yearly,
  threeMonths,
  twoMonths,
  monthly,
  trial,
  lifetime;

  String get displayNameAr {
    switch (this) {
      case SubscriptionPlanType.yearly:
        return 'اشتراك سنوي (الأفضل قيمة)';
      case SubscriptionPlanType.threeMonths:
        return 'اشتراك 3 أشهر';
      case SubscriptionPlanType.twoMonths:
        return 'اشتراك شهرين';
      case SubscriptionPlanType.monthly:
        return 'شهر (30 يوما)';
      case SubscriptionPlanType.trial:
        return 'فترة تجريبية';
      case SubscriptionPlanType.lifetime:
        return 'اشتراك دائم للورشة (مدى الحياة)';
    }
  }

  String get displayNameFr {
    switch (this) {
      case SubscriptionPlanType.yearly:
        return 'Abonnement annuel (Meilleure valeur)';
      case SubscriptionPlanType.threeMonths:
        return 'Abonnement 3 mois';
      case SubscriptionPlanType.twoMonths:
        return 'Abonnement 2 mois';
      case SubscriptionPlanType.monthly:
        return '1 mois (30 jours)';
      case SubscriptionPlanType.trial:
        return 'Période d\'essai';
      case SubscriptionPlanType.lifetime:
        return 'Abonnement permanent atelier (À vie)';
    }
  }

  String get displayNameEn {
    switch (this) {
      case SubscriptionPlanType.yearly:
        return 'Annual Subscription (Best value)';
      case SubscriptionPlanType.threeMonths:
        return '3 Months Subscription';
      case SubscriptionPlanType.twoMonths:
        return '2 Months Subscription';
      case SubscriptionPlanType.monthly:
        return '1 Month (30 days)';
      case SubscriptionPlanType.trial:
        return 'Trial Period';
      case SubscriptionPlanType.lifetime:
        return 'Permanent Workshop Subscription (Lifetime)';
    }
  }
}

class SubscriptionDetails {
  final SubscriptionPlanType planType;
  final String status; // 'active', 'trial', 'trialing', 'expired'
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final int daysRemaining;
  final bool isExpired;
  final bool canRenew;
  final DateTime renewalAvailableFromDate;
  final String workshopName;
  final String userEmail;
  final String joinCode;
  final String role;
  final bool isLifetime;

  SubscriptionDetails({
    required this.planType,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.daysRemaining,
    required this.isExpired,
    required this.canRenew,
    required this.renewalAvailableFromDate,
    required this.workshopName,
    required this.userEmail,
    required this.joinCode,
    required this.role,
    this.isLifetime = false,
  });

  /// Percentage of subscription time remaining (0.0 to 1.0)
  double get remainingRatio {
    if (isLifetime) return 1.0;
    if (totalDays <= 0) return 0.0;
    if (isExpired) return 0.0;
    final ratio = daysRemaining / totalDays;
    return ratio.clamp(0.0, 1.0);
  }

  /// Formats the remaining duration nicely in Arabic (e.g. "5 أشهر و 6 أيام")
  String formatRemainingDuration({AppLanguage lang = AppLanguage.arabic}) {
    if (isLifetime) {
      if (lang == AppLanguage.french) return 'Illimité (À vie)';
      if (lang == AppLanguage.english) return 'Unlimited (Lifetime)';
      return 'غير محدود (مدى الحياة)';
    }

    if (isExpired) {
      final daysAgo = daysRemaining.abs();
      if (lang == AppLanguage.french) {
        return daysAgo == 0
            ? 'Expiré aujourd\'hui'
            : 'Expiré depuis $daysAgo jour(s)';
      } else if (lang == AppLanguage.english) {
        return daysAgo == 0 ? 'Expired today' : 'Expired $daysAgo day(s) ago';
      }
      return daysAgo == 0
          ? 'انتهى اليوم'
          : 'منتهي منذ ${_arabicDaysText(daysAgo)}';
    }

    if (daysRemaining == 0) {
      if (lang == AppLanguage.french) return 'Dernier jour aujourd\'hui';
      if (lang == AppLanguage.english) return 'Last day today';
      return 'اليوم هو اليوم الأخير';
    }

    final months = daysRemaining ~/ 30;
    final days = daysRemaining % 30;

    if (lang == AppLanguage.french) {
      if (months > 0 && days > 0) {
        return '$months mois et $days jour(s)';
      } else if (months > 0) {
        return '$months mois';
      } else {
        return '$daysRemaining jour(s)';
      }
    } else if (lang == AppLanguage.english) {
      if (months > 0 && days > 0) {
        return '$months month(s) and $days day(s)';
      } else if (months > 0) {
        return '$months month(s)';
      } else {
        return '$daysRemaining day(s)';
      }
    }

    // Arabic formatting
    if (months > 0 && days > 0) {
      final monthsText = _arabicMonthsText(months);
      final daysText = _arabicDaysText(days);
      return '$monthsText و $daysText';
    } else if (months > 0) {
      return _arabicMonthsText(months);
    } else {
      return _arabicDaysText(daysRemaining);
    }
  }

  static String _arabicMonthsText(int months) {
    if (months == 1) return 'شهر واحد';
    if (months == 2) return 'شهران';
    if (months >= 3 && months <= 10) return '$months أشهر';
    return '$months شهراً';
  }

  static String _arabicDaysText(int days) {
    if (days == 1) return 'يوم واحد';
    if (days == 2) return 'يومان';
    if (days >= 3 && days <= 10) return '$days أيام';
    return '$days يوماً';
  }

  /// Formats Date as YYYY/MM/DD
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  String get formattedStartDate => formatDate(startDate);

  String get formattedEndDate =>
      isLifetime ? 'مدى الحياة' : formatDate(endDate);

  String get formattedRenewalAvailableDate =>
      isLifetime ? 'غير محدود' : formatDate(renewalAvailableFromDate);
}

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();

  factory SubscriptionService() => _instance;

  SubscriptionService._internal();

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return null;
  }

  /// Streams the subscription owned by the current workshop.
  ///
  /// Workers never have an independent subscription: once the manager grants
  /// `view_subscription`, every member reads the same workshop row and gets
  /// its changes through Supabase Realtime.
  Stream<SubscriptionDetails> getSubscriptionStream() async* {
    final user = AppAuthService().currentUser;
    if (user == null) return;

    // Always begin with the current workshop row. A cached account snapshot
    // may legitimately be a couple of minutes old on another phone.
    final account = await SupabaseAccountService().loadCurrentAccount(
      forceRefresh: true,
    );
    if (account == null) return;

    // The synthetic application-administrator account has no workshop row.
    if (account.isApplicationAdminWorkspace) {
      yield _parseSubscriptionData(account.subscriptionData, account.email);
      return;
    }

    if (account.workshopId.isEmpty) return;

    if (account.subscription.isNotEmpty) {
      yield _parseSubscriptionData(account.subscriptionData, account.email);
    }

    final rows = Supabase.instance.client
        .from('workshop_subscriptions')
        .stream(primaryKey: ['workshop_id'])
        .eq('workshop_id', account.workshopId);

    await for (final result in rows) {
      if (result.isEmpty) continue;
      final subscription = Map<String, dynamic>.from(result.first);
      final sharedWorkshopData = <String, dynamic>{
        ...account.subscriptionData,
        ...subscription,
        'subscriptionStatus': subscription['status'],
        'subscriptionType': subscription['plan_type'],
        'subscriptionStartDate': subscription['starts_at'],
        'subscriptionEndDate': subscription['ends_at'],
        'maxUsers': subscription['max_users'],
        'maxSystems': subscription['max_systems'],
        'maxProfiles': subscription['max_profiles'],
      };
      yield _parseSubscriptionData(sharedWorkshopData, account.email);
    }
  }

  SubscriptionDetails _parseSubscriptionData(
    Map<String, dynamic> data,
    String fallbackEmail,
  ) {
    final now = DateTime.now();
    final userEmail = (data['email']?.toString() ?? fallbackEmail).trim();
    final role = data['role']?.toString() ?? 'worker';
    final isAppAdmin =
        isApplicationAdminEmail(userEmail) ||
        isApplicationAdminEmail(AppAuthService().currentUser?.email);
    final isApplicationAdminWorkspace =
        data['isApplicationAdminWorkspace'] == true;

    final workshopName =
        (data['workshopName']?.toString() ?? '').trim().isNotEmpty
        ? data['workshopName'].toString().trim()
        : (isAppAdmin ? 'إدارة التطبيق' : 'الورشة');
    final joinCode = data['joinCode']?.toString() ?? '';

    // 1. Determine Start Date
    DateTime startDate =
        _parseDate(data['subscriptionStartDate']) ??
        _parseDate(data['subscriptionStart']) ??
        _parseDate(data['createdAt']) ??
        _parseDate(data['trialStartDate']) ??
        now.subtract(const Duration(days: 30));

    // فحص نوع باقة الورشة الفعلي من السحابة
    final rawPlan =
        (data['subscriptionType'] ?? data['planType'] ?? data['plan'])
            ?.toString()
            .toLowerCase()
            .trim();

    final isLifetime =
        rawPlan == 'lifetime' ||
        rawPlan == 'دائم' ||
        rawPlan == 'مدى الحياة' ||
        isApplicationAdminWorkspace;

    // A lifetime workshop plan is shared by all members. The global admin
    // workspace is lifetime too, but an admin's real workshop is not.
    if (isLifetime) {
      return SubscriptionDetails(
        planType: SubscriptionPlanType.lifetime,
        status: 'active',
        startDate: startDate,
        endDate: DateTime(2099, 12, 31),
        totalDays: 36500,
        daysRemaining: 36500,
        isExpired: false,
        canRenew: false,
        renewalAvailableFromDate: DateTime(2099, 12, 31),
        workshopName: workshopName,
        userEmail: userEmail,
        joinCode: joinCode,
        role: role,
        isLifetime: true,
      );
    }

    // 2. Determine End Date for regular workshops
    DateTime? endDate =
        _parseDate(data['trialEndDate']) ??
        _parseDate(data['subscriptionEndDate']) ??
        _parseDate(data['subscriptionExpiresAt']) ??
        _parseDate(data['expiresAt']);

    final rawStatus = (data['subscriptionStatus']?.toString() ?? 'trial')
        .toLowerCase()
        .trim();

    SubscriptionPlanType planType;
    if (rawPlan == 'yearly' || rawPlan == 'annual' || rawPlan == 'سنوي') {
      planType = SubscriptionPlanType.yearly;
    } else if (rawPlan == 'quarterly' ||
        rawPlan == 'three_months' ||
        rawPlan == '3_months' ||
        rawPlan == '3 أشهر') {
      planType = SubscriptionPlanType.threeMonths;
    } else if (rawPlan == 'two_months' ||
        rawPlan == '2_months' ||
        rawPlan == 'شهرين') {
      planType = SubscriptionPlanType.twoMonths;
    } else if (rawPlan == 'monthly' ||
        rawPlan == 'شهري' ||
        rawPlan == 'شهر (30 يوما)' ||
        rawPlan == 'شهر') {
      planType = SubscriptionPlanType.monthly;
    } else if (rawPlan == 'trial' ||
        rawStatus == 'trial' ||
        rawStatus == 'trialing') {
      planType = SubscriptionPlanType.trial;
    } else {
      // Deduce from duration between startDate and endDate
      if (endDate != null) {
        final totalSpanDays = endDate.difference(startDate).inDays;
        if (totalSpanDays >= 180) {
          planType = SubscriptionPlanType.yearly;
        } else if (totalSpanDays >= 75 && totalSpanDays < 180) {
          planType = SubscriptionPlanType.threeMonths;
        } else if (totalSpanDays >= 45 && totalSpanDays < 75) {
          planType = SubscriptionPlanType.twoMonths;
        } else if (totalSpanDays >= 25 && totalSpanDays < 45) {
          planType = SubscriptionPlanType.monthly;
        } else {
          planType = SubscriptionPlanType.trial;
        }
      } else {
        planType = rawStatus == 'active'
            ? SubscriptionPlanType.yearly
            : SubscriptionPlanType.trial;
      }
    }

    // Ensure endDate is set
    if (endDate == null) {
      if (planType == SubscriptionPlanType.yearly) {
        endDate = startDate.add(const Duration(days: 365));
      } else if (planType == SubscriptionPlanType.threeMonths) {
        endDate = startDate.add(const Duration(days: 90));
      } else if (planType == SubscriptionPlanType.twoMonths) {
        endDate = startDate.add(const Duration(days: 60));
      } else if (planType == SubscriptionPlanType.monthly) {
        endDate = startDate.add(const Duration(days: 30));
      } else {
        endDate = startDate.add(const Duration(days: 14));
      }
    }

    final totalDays = endDate.difference(startDate).inDays.clamp(1, 3650);
    final daysRemaining = endDate.difference(now).inDays;
    final isExpired = !now.isBefore(endDate) || rawStatus == 'expired';

    // Renewal window rules:
    // - Yearly: renew allowed when remaining days <= 30 (1 month)
    // - Monthly / Trial: renew allowed when remaining days <= 7 (1 week)
    // - If already expired: renew is immediately allowed.
    final renewalThresholdDays = (planType == SubscriptionPlanType.yearly)
        ? 30
        : 7;
    final canRenew = isExpired || (daysRemaining <= renewalThresholdDays);

    final renewalAvailableFromDate = endDate.subtract(
      Duration(days: renewalThresholdDays),
    );

    return SubscriptionDetails(
      planType: planType,
      status: isExpired
          ? 'expired'
          : (rawStatus.isEmpty ? 'active' : rawStatus),
      startDate: startDate,
      endDate: endDate,
      totalDays: totalDays,
      daysRemaining: daysRemaining,
      isExpired: isExpired,
      canRenew: canRenew,
      renewalAvailableFromDate: renewalAvailableFromDate,
      workshopName: workshopName,
      userEmail: userEmail,
      joinCode: joinCode,
      role: role,
      isLifetime: false,
    );
  }
}

/// Payment destination shown to workshops when they request a subscription
/// renewal. It is managed by the application administrator, not by each
/// workshop, and is deliberately separate from workshop data.
class SubscriptionPaymentSettings {
  static const String collectionName = 'app_config';
  static const String documentName = 'subscription';

  Stream<String> getBaridiMobRipStream() {
    return FirebaseFirestore.instance
        .collection(collectionName)
        .doc(documentName)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.data()?['baridiMobRip']?.toString().trim() ?? '',
        );
  }

  Future<void> saveBaridiMobRip(String rip) async {
    await FirebaseFirestore.instance
        .collection(collectionName)
        .doc(documentName)
        .set({
          'baridiMobRip': rip.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}
