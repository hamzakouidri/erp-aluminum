import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/algerian_payment_service.dart';
import 'package:database_data/services/supabase_account_service.dart';

class ElectronicPaymentScreen extends StatefulWidget {
  final String? initialPlanId;

  const ElectronicPaymentScreen({super.key, this.initialPlanId});

  @override
  State<ElectronicPaymentScreen> createState() =>
      _ElectronicPaymentScreenState();
}

class _ElectronicPaymentScreenState extends State<ElectronicPaymentScreen> {
  final AlgerianPaymentService _paymentService = AlgerianPaymentService();

  late SubscriptionPlan _selectedPlan;
  PaymentMethodType _selectedMethod = PaymentMethodType.edahabia;
  bool _isLoading = false;
  String? _activeCheckoutId;

  // BaridiMob manual input
  final TextEditingController _baridiMobTxController = TextEditingController();
  final TextEditingController _baridiMobNotesController =
      TextEditingController();
  bool _isSubmittingBaridiMob = false;

  Map<String, dynamic> _gatewayConfig = {};

  @override
  void initState() {
    super.initState();
    final defaultPlan = AlgerianPaymentService.defaultPlans.firstWhere(
      (p) => p.id == widget.initialPlanId,
      orElse: () => AlgerianPaymentService.defaultPlans.firstWhere(
        (p) => p.id == 'quarterly',
        orElse: () => AlgerianPaymentService.defaultPlans.first,
      ),
    );
    _selectedPlan = defaultPlan;
    _loadConfig();
  }

  @override
  void dispose() {
    _baridiMobTxController.dispose();
    _baridiMobNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final cfg = await _paymentService.getPaymentGatewayConfig();
    if (mounted) setState(() => _gatewayConfig = cfg);
  }

  Future<void> _processOnlinePayment() async {
    setState(() => _isLoading = true);

    final currentUser = AppAuthService().currentUser;
    final account = await SupabaseAccountService().loadCurrentAccount();
    final workshopId = account?.workshopId ?? '';
    final userEmail = currentUser?.email ?? '';

    try {
      final session = await _paymentService.createChargilyCheckout(
        plan: _selectedPlan,
        paymentMethod: _selectedMethod,
        workshopId: workshopId,
        userEmail: userEmail,
      );

      if (session != null && session['checkout_url'] != null) {
        _activeCheckoutId = session['checkout_id'];
        final checkoutUrl = session['checkout_url'].toString();

        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            _showAwaitingPaymentDialog();
          }
        } else {
          _showError('تعذر فتح صفحة الدفع البنكية.');
        }
      } else {
        _showError(
          'تعذر إنشاء جلسة الدفع الإلكتروني، يرجى المحاولة لاحقاً أو التحقق من الإعدادات.',
        );
      }
    } catch (e) {
      debugPrint('Payment error: $e');
      _showError('حدث خطأ أثناء الاتصال ببوابة الدفع: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAwaitingPaymentDialog() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: lang == AppLanguage.arabic
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Localization.translate('بانتظار إتمام الدفع...', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Localization.translate(
                  'تم فتح صفحة الدفع الآمنة على المتصفح.\nيرجى إدخال بيانات البطاقة والرمز السري SMS المرسل إلى هاتفك لإتمام المعاملة.',
                  lang,
                ),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _verifyPaymentStatus();
              },
              child: Text(
                Localization.translate('تحقق من تفعيل الدفع', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyPaymentStatus() async {
    if (_activeCheckoutId == null) return;
    setState(() => _isLoading = true);

    try {
      final status = await _paymentService.checkCheckoutStatus(
        _activeCheckoutId!,
      );
      if (status == 'paid') {
        final account = await SupabaseAccountService().loadCurrentAccount(
          forceRefresh: true,
        );
        await _paymentService.activatePaidSubscription(
          workshopId: account?.workshopId ?? '',
          durationDays: _selectedPlan.durationDays,
          planId: _selectedPlan.id,
          transactionReference: _activeCheckoutId!,
          amountDzd: _selectedPlan.priceDzd,
        );

        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        _showError(
          'لم يتم تأكيد الدفع بعد (الحالة الحالية: ${status ?? "قيد المعالجة"}). يرجى إتمام العملية وإعادة المحاولة.',
        );
      }
    } catch (e) {
      _showError('حدث خطأ أثناء فحص حالة المعاملة: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: lang == AppLanguage.arabic
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF10B981),
                size: 70,
              ),
              const SizedBox(height: 16),
              Text(
                Localization.translate('تم الدفع وتفعيل الاشتراك بنجاح!', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${Localization.translate('تم تجديد اشتراك الورشة لـ', lang)} ${_selectedPlan.getTitle(lang)} (${_selectedPlan.getDurationLabel(lang)}). ${Localization.translate('شكراً لثقتكم!', lang)}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: Text(
                Localization.translate('العودة للتطبيق', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitBaridiMobReceipt() async {
    final tx = _baridiMobTxController.text.trim();
    if (tx.isEmpty) {
      _showError('يرجى إدخال رقم المعاملة من تطبيق بريدي موب.');
      return;
    }

    setState(() => _isSubmittingBaridiMob = true);
    try {
      final account = await SupabaseAccountService().loadCurrentAccount();
      final success = await _paymentService.submitBaridiMobReceipt(
        workshopId: account?.workshopId ?? '',
        transactionNumber: tx,
        amountDzd: _selectedPlan.priceDzd,
        durationDays: _selectedPlan.durationDays,
        notes: _baridiMobNotesController.text,
      );

      if (success && mounted) {
        final lang = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).language;
        showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: lang == AppLanguage.arabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                Localization.translate('تم استلام معلومات التحويل', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                Localization.translate(
                  'تم إرسال إشعار الدفع عبر بريدي موب للإدارة.\nسيتم مراجعة رقم المعاملة وتفعيل الاشتراك خلال دقائق معدودة.',
                  lang,
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: Text(
                    Localization.translate('موافق', lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      _showError('حدث خطأ أثناء إرسال الإشعار: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingBaridiMob = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: lang == AppLanguage.arabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            Localization.translate('الدفع الإلكتروني وتجديد الاشتراك', lang),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cards & Logos Showcase Banner
              _buildPaymentLogosBanner(lang, isDark),
              const SizedBox(height: 20),

              // Step 1: Select Plan
              Text(
                Localization.translate('1. اختر باقة الاشتراك', lang),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              ...AlgerianPaymentService.defaultPlans.map(
                (plan) => _buildPlanTile(plan, lang, isDark),
              ),
              const SizedBox(height: 24),

              // Step 2: Select Payment Method
              Text(
                Localization.translate(
                  '2. وسيلة الدفع بالدينار الجزائري',
                  lang,
                ),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              _buildMethodCard(
                type: PaymentMethodType.edahabia,
                title: Localization.translate(
                  'البطاقة الذهبية (Edahabia)',
                  lang,
                ),
                subtitle: Localization.translate(
                  'دفع فوري آمن لبريد الجزائر مع رمز SMS',
                  lang,
                ),
                badge: Localization.translate('الأكثر استخداماً', lang),
                icon: Icons.credit_card_rounded,
                badgeColor: const Color(0xFFF59E0B),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                type: PaymentMethodType.cib,
                title: Localization.translate('بطاقة CIB البنكية', lang),
                subtitle: Localization.translate(
                  'جميع البنوك الجزائرية (BNA, BEA, CPA, BDL, BADR, إلخ)',
                  lang,
                ),
                badge: Localization.translate('شبكة SATIM', lang),
                icon: Icons.account_balance_rounded,
                badgeColor: const Color(0xFF2563EB),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                type: PaymentMethodType.baridiMob,
                title: Localization.translate('بريدي موب (BaridiMob)', lang),
                subtitle: Localization.translate(
                  'تحويل فوري للتطبيق عبر RIP والـ QR',
                  lang,
                ),
                badge: Localization.translate('تحويل مباشر', lang),
                icon: Icons.smartphone_rounded,
                badgeColor: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                type: PaymentMethodType.visaMastercard,
                title: Localization.translate(
                  'كارت فيزا / ماستركارد (Visa / Mastercard)',
                  lang,
                ),
                subtitle: Localization.translate(
                  'البطاقات الدولية والمحلية المعتمدة',
                  lang,
                ),
                badge: Localization.translate('دولي', lang),
                icon: Icons.public_rounded,
                badgeColor: const Color(0xFF8B5CF6),
                isDark: isDark,
              ),
              const SizedBox(height: 24),

              // Specific View per Method
              if (_selectedMethod == PaymentMethodType.baridiMob)
                _buildBaridiMobSection(lang, isDark)
              else
                _buildCardPaySection(lang, isDark),

              const SizedBox(height: 20),
              // Security Guarantee Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      Localization.translate(
                        'دفع مشفر وآمن 100% ومطابق لمعايير الأمان البنكي وبريد الجزائر',
                        lang,
                      ),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentLogosBanner(AppLanguage lang, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF2563EB), const Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            Localization.translate('بوابة الدفع الإلكتروني المعتمدة', lang),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Localization.translate(
              'الدفع متاح الآن مباشرة بالبطاقات الجزائرية دون الحاجة للتنقل',
              lang,
            ),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildBrandBadge(
                Localization.translate('الذهبية', lang),
                Colors.amber[700]!,
              ),
              _buildBrandBadge(
                Localization.translate('CIB', lang),
                Colors.cyan[400]!,
              ),
              _buildBrandBadge(
                Localization.translate('BaridiMob', lang),
                const Color(0xFF10B981),
              ),
              _buildBrandBadge('Visa / MC', Colors.purple[300]!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrandBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPlanTile(SubscriptionPlan plan, AppLanguage lang, bool isDark) {
    final isSelected = _selectedPlan.id == plan.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Radio<String>(
              value: plan.id,
              groupValue: _selectedPlan.id,
              onChanged: (_) => setState(() => _selectedPlan = plan),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        plan.getTitle(lang),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      if (plan.getBadge(lang) != null || plan.isPopular)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber[700],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            plan.getBadge(lang) ??
                                Localization.translate('الأكثر طلباً', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.getDurationLabel(lang),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${NumberFormat('#,###').format(plan.priceDzd)} ${Localization.translate('د.ج', lang)}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF2563EB),
                  ),
                ),
                if (plan.originalPriceDzd != null)
                  Text(
                    '${NumberFormat('#,###').format(plan.originalPriceDzd)} ${Localization.translate('د.ج', lang)}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodCard({
    required PaymentMethodType type,
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required Color badgeColor,
    required bool isDark,
  }) {
    final isSelected = _selectedMethod == type;
    return InkWell(
      onTap: () => setState(() => _selectedMethod = type),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: badgeColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Radio<PaymentMethodType>(
              value: type,
              groupValue: _selectedMethod,
              onChanged: (val) {
                if (val != null) setState(() => _selectedMethod = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPaySection(AppLanguage lang, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  Localization.translate('المبلغ الإجمالي للدفع:', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${NumberFormat('#,###').format(_selectedPlan.priceDzd)} ${Localization.translate('د.ج', lang)}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2563EB),
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _isLoading ? null : _processOnlinePayment,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.payment_rounded, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _isLoading
                        ? Localization.translate(
                            'جاري تجهيز بوابة الدفع...',
                            lang,
                          )
                        : '${Localization.translate('ادفع الآن بالبطاقة', lang)} (${_selectedMethod == PaymentMethodType.edahabia ? Localization.translate('الذهبية', lang) : "CIB"})',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaridiMobSection(AppLanguage lang, bool isDark) {
    final rip = (_gatewayConfig['baridi_mob_rip'] ?? '00799999000000000000')
        .toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            Localization.translate(
              'خطوات الدفع عبر بريدي موب (BaridiMob):',
              lang,
            ),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Localization.translate(
              '1. انسخ رقم الـ RIP أدناه.\n2. افتح تطبيق BaridiMob وقم بإجراء تحويل بالمبلغ المطلوب.\n3. ضع رقم المعاملة (N° de transaction) هنا لتفعيل اشتراكك.',
              lang,
            ),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          // RIP Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Localization.translate(
                          'رقم الحساب البريدي (RIP):',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          rip,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.copy_rounded,
                    color: Color(0xFF2563EB),
                  ),
                  tooltip: Localization.translate('نسخ رقم الـ RIP', lang),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: rip));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            'تم نسخ رقم الـ RIP بنجاح',
                            lang,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Transaction Input
          TextField(
            controller: _baridiMobTxController,
            decoration: InputDecoration(
              labelText: Localization.translate(
                'رقم معاملة بريدي موب (Numéro de transaction)',
                lang,
              ),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.receipt_long_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _baridiMobNotesController,
            decoration: InputDecoration(
              labelText: Localization.translate(
                'ملاحظة إضافية (اختياري - اسم الورشة أو رقم الهاتف)',
                lang,
              ),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _isSubmittingBaridiMob ? null : _submitBaridiMobReceipt,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _isSubmittingBaridiMob
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    Localization.translate(
                      'تأكيد التحويل وإرسال الإشعار',
                      lang,
                    ),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
