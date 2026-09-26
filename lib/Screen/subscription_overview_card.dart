import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'subscription_review_dialog.dart';

class SubscriptionOverviewCard extends StatelessWidget {
  const SubscriptionOverviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.canViewSubscription()) {
      return const SizedBox.shrink();
    }
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF172033) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return StreamBuilder<SubscriptionDetails>(
      stream: SubscriptionService().getSubscriptionStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final details = snapshot.data!;
        final planTitle = switch (lang) {
          AppLanguage.french => details.planType.displayNameFr,
          AppLanguage.english => details.planType.displayNameEn,
          _ => details.planType.displayNameAr,
        };

        final (statusText, statusColor) = details.isLifetime
            ? ('دائم', Colors.purple.shade600)
            : (details.isExpired
                  ? ('منتهي', Colors.red)
                  : (details.canRenew
                        ? ('يقارب على الانتهاء', Colors.orange.shade800)
                        : ('نشط', Colors.green)));

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: details.isLifetime
                              ? const [Color(0xFF8B5CF6), Color(0xFF6D28D9)]
                              : const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        details.isLifetime
                            ? Icons.all_inclusive_rounded
                            : Icons.card_membership_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            planTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            details.workshopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            Localization.translate(statusText, lang),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // ── Key Metrics (Remaining Duration, Start & End Date) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Remaining Duration Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            details.isLifetime
                                ? Icons.all_inclusive_rounded
                                : Icons.timer_outlined,
                            color: details.isLifetime
                                ? Colors.purple.shade600
                                : (details.isExpired
                                      ? Colors.red
                                      : const Color(0xFF2563EB)),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'المدة المتبقية:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  details.formatRemainingDuration(lang: lang),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: details.isLifetime
                                        ? Colors.purple.shade600
                                        : (details.isExpired
                                              ? Colors.red
                                              : (isDark
                                                    ? Colors.white
                                                    : const Color(0xFF0F172A))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!details.isExpired && !details.isLifetime)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF2563EB,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${details.daysRemaining} ${Localization.translate('يوم', lang)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Start and End Date Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateItem(
                            icon: Icons.calendar_today_rounded,
                            label: Localization.translate(
                              'تاريخ الاشتراك:',
                              lang,
                            ),
                            date: details.formattedStartDate,
                            isDark: isDark,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        Expanded(
                          child: _buildDateItem(
                            icon: Icons.event_busy_rounded,
                            label: Localization.translate(
                              'نهاية الاشتراك:',
                              lang,
                            ),
                            date: details.formattedEndDate,
                            isDark: isDark,
                            dateColor: details.isLifetime
                                ? Colors.purple.shade600
                                : (details.isExpired ? Colors.red : null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: details.remainingRatio,
                        minHeight: 5,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.blue.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          details.isLifetime
                              ? Colors.purple.shade600
                              : (details.isExpired
                                    ? Colors.red
                                    : (details.canRenew
                                          ? Colors.orange.shade700
                                          : const Color(0xFF2563EB))),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Action button to review and renew
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => showSubscriptionReviewDialog(context),
                        icon: Icon(
                          details.canRenew
                              ? Icons.autorenew_rounded
                              : Icons.remove_red_eye_rounded,
                          size: 18,
                        ),
                        label: Text(
                          Localization.translate(
                            details.canRenew
                                ? 'مراجعة وتجديد الاشتراك'
                                : 'مراجعة تفاصيل الاشتراك',
                            lang,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: details.isLifetime
                              ? Colors.purple.shade700
                              : (details.canRenew
                                    ? Colors.green.shade700
                                    : const Color(0xFF2563EB)),
                          side: BorderSide(
                            color: details.isLifetime
                                ? Colors.purple.withValues(alpha: 0.4)
                                : (details.canRenew
                                      ? Colors.green.withValues(alpha: 0.5)
                                      : const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.35)),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateItem({
    required IconData icon,
    required String label,
    required String date,
    required bool isDark,
    Color? dateColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                date,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color:
                      dateColor ??
                      (isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
