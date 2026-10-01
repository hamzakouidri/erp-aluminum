import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/services/subscription_service.dart';
import 'package:database_data/settings/app_settings.dart';

void main() {
  group('SubscriptionDetails Tests', () {
    test('Arabic formatting of 5 months and 6 days', () {
      final now = DateTime.now();
      final details = SubscriptionDetails(
        planType: SubscriptionPlanType.yearly,
        status: 'active',
        startDate: now.subtract(const Duration(days: 60)),
        endDate: now.add(const Duration(days: 156)), // 156 days = 5 * 30 + 6 days
        totalDays: 216,
        daysRemaining: 156,
        isExpired: false,
        canRenew: false, // 156 > 30
        renewalAvailableFromDate: now.add(const Duration(days: 156 - 30)),
        workshopName: 'ورشة الألمنيوم المميزة',
        userEmail: 'user@example.com',
        joinCode: 'WK1234',
        role: 'manager',
      );

      expect(details.formatRemainingDuration(lang: AppLanguage.arabic), '5 أشهر و 6 أيام');
      expect(details.canRenew, isFalse);
    });

    test('Yearly plan allows renewal when remaining days <= 30', () {
      final now = DateTime.now();
      final details = SubscriptionDetails(
        planType: SubscriptionPlanType.yearly,
        status: 'active',
        startDate: now.subtract(const Duration(days: 335)),
        endDate: now.add(const Duration(days: 30)),
        totalDays: 365,
        daysRemaining: 30,
        isExpired: false,
        canRenew: true,
        renewalAvailableFromDate: now,
        workshopName: 'ورشة النجاح',
        userEmail: 'user@example.com',
        joinCode: 'WK1234',
        role: 'manager',
      );

      expect(details.canRenew, isTrue);
      expect(details.formatRemainingDuration(lang: AppLanguage.arabic), 'شهر واحد');
    });

    test('Monthly plan allows renewal when remaining days <= 7', () {
      final now = DateTime.now();
      final details = SubscriptionDetails(
        planType: SubscriptionPlanType.monthly,
        status: 'active',
        startDate: now.subtract(const Duration(days: 25)),
        endDate: now.add(const Duration(days: 5)),
        totalDays: 30,
        daysRemaining: 5,
        isExpired: false,
        canRenew: true,
        renewalAvailableFromDate: now.subtract(const Duration(days: 2)),
        workshopName: 'ورشة الأمل',
        userEmail: 'user@example.com',
        joinCode: 'WK1234',
        role: 'manager',
      );

      expect(details.canRenew, isTrue);
      expect(details.formatRemainingDuration(lang: AppLanguage.arabic), '5 أيام');
    });

    test('Monthly plan disables renewal when remaining days > 7', () {
      final now = DateTime.now();
      final details = SubscriptionDetails(
        planType: SubscriptionPlanType.monthly,
        status: 'active',
        startDate: now.subtract(const Duration(days: 10)),
        endDate: now.add(const Duration(days: 20)),
        totalDays: 30,
        daysRemaining: 20,
        isExpired: false,
        canRenew: false,
        renewalAvailableFromDate: now.add(const Duration(days: 13)),
        workshopName: 'ورشة الأمل',
        userEmail: 'user@example.com',
        joinCode: 'WK1234',
        role: 'manager',
      );

      expect(details.canRenew, isFalse);
      expect(details.formatRemainingDuration(lang: AppLanguage.arabic), '20 يوماً');
    });

    test('Expired subscription is marked canRenew = true and formatted properly', () {
      final now = DateTime.now();
      final details = SubscriptionDetails(
        planType: SubscriptionPlanType.yearly,
        status: 'expired',
        startDate: now.subtract(const Duration(days: 370)),
        endDate: now.subtract(const Duration(days: 5)),
        totalDays: 365,
        daysRemaining: -5,
        isExpired: true,
        canRenew: true,
        renewalAvailableFromDate: now.subtract(const Duration(days: 35)),
        workshopName: 'ورشة الأمل',
        userEmail: 'user@example.com',
        joinCode: 'WK1234',
        role: 'manager',
      );

      expect(details.isExpired, isTrue);
      expect(details.canRenew, isTrue);
      expect(details.formatRemainingDuration(lang: AppLanguage.arabic), 'منتهي منذ 5 أيام');
    });

    test('Admin Lifetime subscription formatting and properties', () {
      final startDate = DateTime(2023, 5, 15);
      final details = SubscriptionDetails(
        planType: SubscriptionPlanType.lifetime,
        status: 'active',
        startDate: startDate,
        endDate: DateTime(2099, 12, 31),
        totalDays: 36500,
        daysRemaining: 36500,
        isExpired: false,
        canRenew: false,
        renewalAvailableFromDate: DateTime(2099, 12, 31),
        workshopName: 'إدارة التطبيق',
        userEmail: 'admin@system.com',
        joinCode: 'ADMIN01',
        role: 'admin',
        isLifetime: true,
      );

      expect(details.planType, SubscriptionPlanType.lifetime);
      expect(details.planType.displayNameAr, 'اشتراك دائم للورشة (مدى الحياة)');
      expect(details.isLifetime, isTrue);
      expect(details.canRenew, isFalse);
      expect(details.formattedStartDate, '2023/05/15');
      expect(details.formattedEndDate, 'مدى الحياة');
      expect(details.formatRemainingDuration(lang: AppLanguage.arabic), 'غير محدود (مدى الحياة)');
      expect(details.formatRemainingDuration(lang: AppLanguage.french), 'Illimité (À vie)');
      expect(details.remainingRatio, 1.0);
    });
  });
}
