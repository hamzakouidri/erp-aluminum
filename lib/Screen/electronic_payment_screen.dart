import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/algerian_payment_service.dart';

class ElectronicPaymentScreen extends StatefulWidget {
  final String? initialPlanId;

  const ElectronicPaymentScreen({super.key, this.initialPlanId});

  @override
  State<ElectronicPaymentScreen> createState() => _ElectronicPaymentScreenState();
}

class _ElectronicPaymentScreenState extends State<ElectronicPaymentScreen> {
  final AlgerianPaymentService _paymentService = AlgerianPaymentService();

  late SubscriptionPlan _selectedPlan;
  PaymentMethodType _selectedMethod = PaymentMethodType.edahabia;
  bool _isLoading = false;
  String? _activeCheckoutId;

  // BaridiMob manual input
  final TextEditingController _baridiMobTxController = TextEditingController();
  final TextEditingController _baridiMobNotesController = TextEditingController();
  bool _isSubmittingBaridiMob = false;

  Map<String, dynamic> _gatewayConfig = {};

  @override
  void initState() {
    super.initState();
    final defaultPlan = AlgerianPaymentService.defaultPlans.firstWhere(
      (p) => p.id == widget.initialPlanId,
      orElse: () => AlgerianPaymentService.defaultPlans[1], // 3 months default
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
    final workshopId = currentUser?.uid ?? '';
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
        _showError('تعذر إنشاء جلسة الدفع الإلكتروني، يرجى المحاولة لاحقاً أو التحقق من الإعدادات.');
      }
    } catch (e) {
      debugPrint('Payment error: $e');
      _showError('حدث خطأ أثناء الاتصال ببوابة الدفع: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAwaitingPaymentDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.hourglass_top_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 10),
              Text('بانتظار إتمام الدفع...', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'تم فتح صفحة الدفع الآمنة على المتصفح.\nيرجى إدخال بيانات البطاقة والرمز السري SMS المرسل إلى هاتفك لإتمام المعاملة.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.5),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _verifyPaymentStatus();
              },
              child: const Text('تحقق من تفعيل الدفع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
      final status = await _paymentService.checkCheckoutStatus(_activeCheckoutId!);
      if (status == 'paid') {
        final currentUser = AppAuthService().currentUser;
        await _paymentService.activatePaidSubscription(
          workshopId: currentUser?.uid ?? '',
          durationDays: _selectedPlan.durationDays,
          planId: _selectedPlan.id,
          transactionReference: _activeCheckoutId!,
          amountDzd: _selectedPlan.priceDzd,
        );

        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        _showError('لم يتم تأكيد الدفع بعد (الحالة الحالية: ${status ?? "قيد المعالجة"}). يرجى إتمام العملية وإعادة المحاولة.');
      }
    } catch (e) {
      _showError('حدث خطأ أثناء فحص حالة المعاملة: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 70),
              const SizedBox(height: 16),
              const Text(
                'تم الدفع وتفعيل الاشتراك بنجاح!',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'تم تجديد اشتراك الورشة لـ ${_selectedPlan.titleAr} (${_selectedPlan.durationLabelAr}). شكراً لثقتكم!',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('العودة للتطبيق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
      final success = await _paymentService.submitBaridiMobReceipt(
        workshopId: AppAuthService().currentUser?.uid ?? '',
        transactionNumber: tx,
        amountDzd: _selectedPlan.priceDzd,
        durationDays: _selectedPlan.durationDays,
        notes: _baridiMobNotesController.text,
      );

      if (success && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('تم استلام معلومات التحويل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              content: const Text(
                'تم إرسال إشعار الدفع عبر بريدي موب للإدارة.\nسيتم مراجعة رقم المعاملة وتفعيل الاشتراك خلال دقائق معدودة.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: const Text('موافق', style: TextStyle(fontFamily: 'Cairo')),
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
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            Localization.translate('الدفع الإلكتروني وتجديد الاشتراك', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
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
              _buildPaymentLogosBanner(isDark),
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
              ...AlgerianPaymentService.defaultPlans.map((plan) => _buildPlanTile(plan, isDark)),
              const SizedBox(height: 24),

              // Step 2: Select Payment Method
              Text(
                Localization.translate('2. وسيلة الدفع بالدينار الجزائري', lang),
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
                title: 'البطاقة الذهبية (Edahabia)',
                subtitle: 'دفع فوري آمن لبريد الجزائر مع رمز SMS',
                badge: 'الأكثر استخداماً',
                icon: Icons.credit_card_rounded,
                badgeColor: const Color(0xFFF59E0B),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                type: PaymentMethodType.cib,
                title: 'بطاقة CIB البنكية',
                subtitle: 'جميع البنوك الجزائرية (BNA, BEA, CPA, BDL, BADR, إلخ)',
                badge: 'شبكة SATIM',
                icon: Icons.account_balance_rounded,
                badgeColor: const Color(0xFF2563EB),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                type: PaymentMethodType.baridiMob,
                title: 'بريدي موب (BaridiMob)',
                subtitle: 'تحويل فوري للتطبيق عبر RIP والـ QR',
                badge: 'تحويل مباشر',
                icon: Icons.smartphone_rounded,
                badgeColor: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                type: PaymentMethodType.visaMastercard,
                title: 'كارت فيزا / ماستركارد (Visa / Mastercard)',
                subtitle: 'البطاقات الدولية والمحلية المعتمدة',
                badge: 'دولي',
                icon: Icons.public_rounded,
                badgeColor: const Color(0xFF8B5CF6),
                isDark: isDark,
              ),
              const SizedBox(height: 24),

              // Specific View per Method
              if (_selectedMethod == PaymentMethodType.baridiMob)
                _buildBaridiMobSection(isDark)
              else
                _buildCardPaySection(isDark),

              const SizedBox(height: 20),
              // Security Guarantee Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text(
                    'دفع مشفر وآمن 100% ومطابق لمعايير الأمان البنكي وبريد الجزائر',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentLogosBanner(bool isDark) {
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
          const Text(
            'بوابة الدفع الإلكتروني المعتمدة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'الدفع متاح الآن مباشرة بالبطاقات الجزائرية دون الحاجة للتنقل',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildBrandBadge('الذهبية', Colors.amber[700]!),
              _buildBrandBadge('CIB', Colors.cyan[400]!),
              _buildBrandBadge('BaridiMob', const Color(0xFF10B981)),
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

  Widget _buildPlanTile(SubscriptionPlan plan, bool isDark) {
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
                  Row(
                    children: [
                      Text(
                        plan.titleAr,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      if (plan.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber[700],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'الأكثر طلباً',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    plan.durationLabelAr,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${NumberFormat('#,###').format(plan.priceDzd)} د.ج',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF2563EB),
                  ),
                ),
                if (plan.originalPriceDzd != null)
                  Text(
                    '${NumberFormat('#,###').format(plan.originalPriceDzd)} د.ج',
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
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
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

  Widget _buildCardPaySection(bool isDark) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المبلغ الإجمالي للدفع:', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              Text(
                '${NumberFormat('#,###').format(_selectedPlan.priceDzd)} د.ج',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _processOnlinePayment,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                : const Icon(Icons.payment_rounded),
            label: Text(
              _isLoading ? 'جاري تجهيز بوابة الدفع...' : 'ادفع الآن بالبطاقة (${_selectedMethod == PaymentMethodType.edahabia ? "الذهبية" : "CIB"})',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaridiMobSection(bool isDark) {
    final rip = (_gatewayConfig['baridi_mob_rip'] ?? '00799999000000000000').toString();

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
          const Text(
            'خطوات الدفع عبر بريدي موب (BaridiMob):',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. انسخ رقم الـ RIP أدناه.\n2. افتح تطبيق BaridiMob وقم بإجراء تحويل بالمبلغ المطلوب.\n3. ضع رقم المعاملة (N° de transaction) هنا لتفعيل اشتراكك.',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, height: 1.5),
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
                      const Text('رقم الحساب البريدي (RIP):', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey)),
                      Text(
                        rip,
                        style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Color(0xFF2563EB)),
                  tooltip: 'نسخ رقم الـ RIP',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: rip));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ رقم الـ RIP بنجاح')),
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
            decoration: const InputDecoration(
              labelText: 'رقم معاملة بريدي موب (Numéro de transaction)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.receipt_long_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _baridiMobNotesController,
            decoration: const InputDecoration(
              labelText: 'ملاحظة إضافية (اختياري - اسم الورشة أو رقم الهاتف)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isSubmittingBaridiMob ? null : _submitBaridiMobReceipt,
            icon: _isSubmittingBaridiMob
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.send_rounded),
            label: const Text('تأكيد التحويل وإرسال الإشعار', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
