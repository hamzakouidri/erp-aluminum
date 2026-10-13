import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/algerian_payment_service.dart';

class PaymentGatewaySettingsScreen extends StatefulWidget {
  const PaymentGatewaySettingsScreen({super.key});

  @override
  State<PaymentGatewaySettingsScreen> createState() =>
      _PaymentGatewaySettingsScreenState();
}

class _PaymentGatewaySettingsScreenState
    extends State<PaymentGatewaySettingsScreen> {
  final TextEditingController _baridiMobRipController = TextEditingController();
  final TextEditingController _chargilySecretKeyController =
      TextEditingController();
  bool _isChargilyLive = false;
  bool _obscureChargilyKey = true;
  bool _isSavingPaymentSettings = false;
  bool _isLoading = true;

  String _t(String key) => Localization.translate(
        key,
        Provider.of<AppSettingsProvider>(context, listen: false).language,
      );

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
  }

  @override
  void dispose() {
    _baridiMobRipController.dispose();
    _chargilySecretKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentSettings() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(SubscriptionPaymentSettings.collectionName)
          .doc(SubscriptionPaymentSettings.documentName)
          .get();
      final gatewayConfig =
          await AlgerianPaymentService().getPaymentGatewayConfig();
      if (!mounted) return;
      final rip = snapshot.data()?['baridiMobRip']?.toString() ??
          (gatewayConfig['baridi_mob_rip']?.toString() ?? '');
      _baridiMobRipController.text = rip;
      _chargilySecretKeyController.text =
          (gatewayConfig['secret_key'] ?? '').toString();
      _isChargilyLive = gatewayConfig['is_live'] == true;
    } catch (error) {
      debugPrint('Could not load subscription payment settings: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePaymentSettings() async {
    if (!isApplicationAdminEmail(AppAuthService().currentUser?.email)) {
      return;
    }
    final rip = _baridiMobRipController.text.trim();
    final secretKey = _chargilySecretKeyController.text.trim();

    setState(() => _isSavingPaymentSettings = true);
    try {
      if (rip.isNotEmpty) {
        await SubscriptionPaymentSettings().saveBaridiMobRip(rip);
      }
      await AlgerianPaymentService().savePaymentGatewayConfig(
        secretKey: secretKey,
        isLive: _isChargilyLive,
        baridiMobRip: rip.isNotEmpty ? rip : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('تم حفظ إعدادات بوابات الدفع (Chargily & BaridiMob) بنجاح.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('تعذر حفظ إعدادات الدفع:')} $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingPaymentSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('إعدادات بوابات الدفع الإلكتروني')),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.payments_rounded,
                                  color: Color(0xFF1E88E5),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _t('بوابات الدفع الإلكتروني والاشتراكات'),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _t(
                                        'تهيئة وسائل الدفع الرقمي بالبطاقة الذهبية، CIB، فيزا / ماستركارد، وبريدي موب.',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32),

                          // BaridiMob RIP
                          Text(
                            _t('بريدي موب BaridiMob'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _baridiMobRipController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _t('رقم CCP / RIP لـ BaridiMob (20 رقماً)'),
                              hintText: '00799999000000000000',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(
                                Icons.account_balance_rounded,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Chargily Pay V2 Config Section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.credit_card_rounded,
                                      color: Color(0xFF1E88E5),
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _t(
                                        'بوابة الدفع Chargily Pay V2 (الذهبية / CIB / Visa / RedotPay)',
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _chargilySecretKeyController,
                                  obscureText: _obscureChargilyKey,
                                  decoration: InputDecoration(
                                    labelText: _t(
                                      'مفتاح السر لـ Chargily (API Secret Key)',
                                    ),
                                    hintText: 'test_sk_... أو live_sk_...',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.vpn_key_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureChargilyKey
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureChargilyKey =
                                              !_obscureChargilyKey;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (_isChargilyLive
                                            ? Colors.green
                                            : Colors.orange)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (_isChargilyLive
                                              ? Colors.green
                                              : Colors.orange)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: SwitchListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      _isChargilyLive
                                          ? _t(
                                              'الوضع المباشر الحقيقي (Live Mode - مدفوعات حقيقية)',
                                            )
                                          : _t(
                                              'وضع التجربة (Test Mode - بيئة اختبار مجانية)',
                                            ),
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: _isChargilyLive
                                            ? Colors.green.shade700
                                            : Colors.orange.shade800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _isChargilyLive
                                          ? _t(
                                              'تتم المعاملات المالية الفعلية مع البنوك وبريد الجزائر',
                                            )
                                          : _t(
                                              'يستخدم بطاقات الاختبار أو بطاقة RedotPay في وضع التجربة دون خصم أموال حقيقية',
                                            ),
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    value: _isChargilyLive,
                                    onChanged: (val) {
                                      setState(() {
                                        _isChargilyLive = val;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FilledButton.icon(
                              onPressed: _isSavingPaymentSettings
                                  ? null
                                  : _savePaymentSettings,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                              ),
                              icon: _isSavingPaymentSettings
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(
                                _t('حفظ إعدادات بوابات الدفع'),
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
