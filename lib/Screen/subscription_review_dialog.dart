import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

void showSubscriptionReviewDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const SubscriptionReviewDialog(),
  );
}

class SubscriptionReviewDialog extends StatelessWidget {
  const SubscriptionReviewDialog({super.key});

  static const String baridiMobRip = '00799999999999999999';
  static const String adminWhatsAppNumber = '213554301484';

  Future<void> _launchWhatsApp(
    BuildContext context,
    SubscriptionDetails details,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final planName = switch (lang) {
      AppLanguage.french => details.planType.displayNameFr,
      AppLanguage.english => details.planType.displayNameEn,
      _ => details.planType.displayNameAr,
    };

    final message = '''
مرحباً إدارة التطبيق،
أرغب في طلب تجديد اشتراكي في نظام إدارة الورش.
• نوع الباقة: $planName
• اسم الورشة: ${details.workshopName}
• البريد الإلكتروني: ${details.userEmail}
• كود الورشة: ${details.joinCode.isNotEmpty ? details.joinCode : 'غير محدد'}
• تاريخ نهاية الاشتراك الحالي: ${details.formattedEndDate}
''';

    final encodedMessage = Uri.encodeComponent(message.trim());
    final uri = Uri.parse('https://wa.me/$adminWhatsAppNumber?text=$encodedMessage');

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        final fallbackUri = Uri.parse('whatsapp://send?phone=$adminWhatsAppNumber&text=$encodedMessage');
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق واتساب. يرجى التواصل على الرقم: 0554301484'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyRip(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: baridiMobRip));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('تم نسخ رقم RIP الخاص بـ BaridiMob بنجاح'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StreamBuilder<SubscriptionDetails>(
          stream: SubscriptionService().getSubscriptionStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const SizedBox(
                height: 250,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final details = snapshot.data;
            if (details == null) {
              return const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: Text('تعذر تحميل بيانات الاشتراك')),
              );
            }

            final planTitle = switch (lang) {
              AppLanguage.french => details.planType.displayNameFr,
              AppLanguage.english => details.planType.displayNameEn,
              _ => details.planType.displayNameAr,
            };

            final (statusText, statusColor) = details.isLifetime
                ? (lang == AppLanguage.french ? 'Permanent (Admin)' : (lang == AppLanguage.english ? 'Permanent (Admin)' : 'دائم (مدير التطبيق)'), Colors.purple.shade600)
                : (details.isExpired
                    ? (lang == AppLanguage.french ? 'Expiré' : (lang == AppLanguage.english ? 'Expired' : 'منتهي الصلاحية'), Colors.red)
                    : (details.canRenew
                        ? (lang == AppLanguage.french ? 'Expire bientôt' : (lang == AppLanguage.english ? 'Expiring soon' : 'يقارب على الانتهاء'), Colors.amber.shade800)
                        : (lang == AppLanguage.french ? 'Actif' : (lang == AppLanguage.english ? 'Active' : 'سارٍ ونشط'), Colors.green)));

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──────────────────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: details.isLifetime
                              ? Colors.purple.withValues(alpha: 0.12)
                              : const Color(0xFF2563EB).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          details.isLifetime
                              ? Icons.all_inclusive_rounded
                              : Icons.verified_user_rounded,
                          color: details.isLifetime
                              ? Colors.purple.shade600
                              : const Color(0xFF2563EB),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Localization.translate('مراجعة الاشتراك', lang),
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              details.workshopName,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Plan & Status Overview ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: details.isLifetime
                            ? (isDark
                                ? const [Color(0xFF3B0764), Color(0xFF1E1B4B)]
                                : const [Color(0xFFF5F3FF), Color(0xFFEDE9FE)])
                            : (isDark
                                ? const [Color(0xFF1E3A8A), Color(0xFF0F172A)]
                                : const [Color(0xFFEFF6FF), Color(0xFFDBEAFE)]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: details.isLifetime
                            ? Colors.purple.withValues(alpha: 0.3)
                            : const Color(0xFF2563EB).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  details.isLifetime
                                      ? Icons.all_inclusive_rounded
                                      : Icons.star_rounded,
                                  color: details.isLifetime
                                      ? Colors.purple.shade600
                                      : const Color(0xFF2563EB),
                                  size: 22,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  planTitle,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : (details.isLifetime
                                            ? const Color(0xFF581C87)
                                            : const Color(0xFF1E3A8A)),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Time remaining highlight
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                details.isLifetime
                                    ? Icons.all_inclusive_rounded
                                    : Icons.hourglass_top_rounded,
                                color: details.isLifetime
                                    ? Colors.purple.shade600
                                    : (details.isExpired ? Colors.red : const Color(0xFF2563EB)),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      Localization.translate('المدة المتبقية:', lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      details.formatRemainingDuration(lang: lang),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: details.isLifetime
                                            ? Colors.purple.shade600
                                            : (details.isExpired
                                                ? Colors.red
                                                : (isDark ? Colors.white : const Color(0xFF0F172A))),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!details.isExpired && !details.isLifetime)
                                Text(
                                  lang == AppLanguage.french ? '${details.daysRemaining} j' : (lang == AppLanguage.english ? '${details.daysRemaining} d' : '${details.daysRemaining} يوم'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: details.remainingRatio,
                            minHeight: 7,
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.blue.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              details.isLifetime
                                  ? Colors.purple.shade600
                                  : (details.isExpired
                                      ? Colors.red
                                      : (details.canRenew
                                          ? Colors.amber.shade700
                                          : const Color(0xFF2563EB))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Date Details Grid ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          icon: Icons.calendar_today_rounded,
                          title: Localization.translate('تاريخ بداية الاشتراك:', lang),
                          value: details.formattedStartDate,
                          isDark: isDark,
                        ),
                        const Divider(height: 16),
                        _buildInfoRow(
                          icon: Icons.event_busy_rounded,
                          title: Localization.translate('تاريخ نهاية الاشتراك:', lang),
                          value: details.getFormattedEndDate(lang: lang),
                          isDark: isDark,
                          valueColor: details.isLifetime
                              ? Colors.purple.shade600
                              : (details.isExpired ? Colors.red : null),
                        ),
                        if (details.joinCode.isNotEmpty) ...[
                          const Divider(height: 16),
                          _buildInfoRow(
                            icon: Icons.qr_code_rounded,
                            title: Localization.translate('كود الورشة:', lang),
                            value: details.joinCode,
                            isDark: isDark,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Renewal Section ─────────────────────────────────
                  if (details.isLifetime) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: Colors.purple, size: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              Localization.translate('حسابك كمدير للتطبيق يتمتع باشتراك دائم وصلاحيات غير محدودة مدى الحياة دون الحاجة إلى تجديد.', lang),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.grey.shade200 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (details.canRenew) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.autorenew_rounded, color: Colors.green, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                Localization.translate('تجديد الاشتراك متاح الآن', lang),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            details.planType == SubscriptionPlanType.yearly
                                ? 'يمكنك تجديد اشتراكك السنوي الآن نظراً لاقتراب موعد الانتهاء بأقل من شهر.'
                                : 'يمكنك تجديد اشتراكك الآن نظراً لاقتراب موعد الانتهاء بأقل من أسبوع.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.grey.shade300 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // BaridiMob Info
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.payment_rounded, color: Color(0xFF2563EB), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الدفع عبر BaridiMob (RIP):',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        baridiMobRip,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'نسخ رقم RIP',
                                  icon: const Icon(Icons.copy_rounded, color: Color(0xFF2563EB), size: 20),
                                  onPressed: () => _copyRip(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // WhatsApp Contact Button
                          ElevatedButton.icon(
                            onPressed: () => _launchWhatsApp(context, details),
                            icon: const Icon(Icons.wechat_rounded, color: Colors.white, size: 22),
                            label: Text(
                              Localization.translate('طلب تجديد الاشتراك عبر واتساب', lang),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Not ready for renewal yet
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFF2563EB),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Localization.translate('تجديد الاشتراك', lang),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            details.planType == SubscriptionPlanType.yearly
                                ? 'اشتراكك سارٍ حالياً. يُتاح التجديد قبل انتهاء الاشتراك بشهر واحد (30 يوماً)، ابتداءً من تاريخ: ${details.formattedRenewalAvailableDate}.'
                                : 'اشتراكك سارٍ حالياً. يُتاح التجديد قبل انتهاء الاشتراك بأسبوع واحد (7 أيام)، ابتداءً من تاريخ: ${details.formattedRenewalAvailableDate}.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: isDark ? Colors.grey.shade300 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    required bool isDark,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: valueColor ?? const Color(0xFF2563EB)),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
