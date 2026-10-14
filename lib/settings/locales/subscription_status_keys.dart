import '../app_settings.dart';

const subscriptionStatusKeys = <String, Map<AppLanguage, String>>{
  'تجديد الاشتراك': {
    AppLanguage.arabic: 'تجديد الاشتراك',
    AppLanguage.french: 'Renouvellement de l’abonnement',
    AppLanguage.english: 'Renew subscription',
  },
  'المدة المتبقية:': {
    AppLanguage.arabic: 'المدة المتبقية:',
    AppLanguage.french: 'Durée restante :',
    AppLanguage.english: 'Time remaining:',
  },
  'اشتراكك سارٍ حالياً. يُتاح التجديد قبل انتهاء الاشتراك بشهر واحد (30 يوماً)، ابتداءً من تاريخ:': {
    AppLanguage.arabic: 'اشتراكك سارٍ حالياً. يُتاح التجديد قبل انتهاء الاشتراك بشهر واحد (30 يوماً)، ابتداءً من تاريخ:',
    AppLanguage.french: 'Votre abonnement est actuellement actif. Le renouvellement est possible un mois (30 jours) avant son expiration, à partir du :',
    AppLanguage.english: 'Your subscription is currently active. Renewal is available one month (30 days) before it expires, starting on:',
  },
  'اشتراكك سارٍ حالياً. يُتاح التجديد قبل انتهاء الاشتراك بأسبوع واحد (7 أيام)، ابتداءً من تاريخ:': {
    AppLanguage.arabic: 'اشتراكك سارٍ حالياً. يُتاح التجديد قبل انتهاء الاشتراك بأسبوع واحد (7 أيام)، ابتداءً من تاريخ:',
    AppLanguage.french: 'Votre abonnement est actuellement actif. Le renouvellement est possible une semaine (7 jours) avant son expiration, à partir du :',
    AppLanguage.english: 'Your subscription is currently active. Renewal is available one week (7 days) before it expires, starting on:',
  },
  'توزيع جزئي': {
    AppLanguage.arabic: 'توزيع جزئي',
    AppLanguage.french: 'Distribution partielle',
    AppLanguage.english: 'Partial distribution',
  },
  'توزيع كامل': {
    AppLanguage.arabic: 'توزيع كامل',
    AppLanguage.french: 'Distribution complète',
    AppLanguage.english: 'Full distribution',
  },
  'تحت التحفظ': {
    AppLanguage.arabic: 'تحت التحفظ',
    AppLanguage.french: 'Sous réserve',
    AppLanguage.english: 'On hold',
  },
  'نشط': {
    AppLanguage.arabic: 'نشط',
    AppLanguage.french: 'Actif',
    AppLanguage.english: 'Active',
  },
  'دائم': {
    AppLanguage.arabic: 'دائم',
    AppLanguage.french: 'Permanent',
    AppLanguage.english: 'Lifetime',
  },
  'منتهي': {
    AppLanguage.arabic: 'منتهي',
    AppLanguage.french: 'Expiré',
    AppLanguage.english: 'Expired',
  },
  'يقارب على الانتهاء': {
    AppLanguage.arabic: 'يقارب على الانتهاء',
    AppLanguage.french: 'Expire bientôt',
    AppLanguage.english: 'Expiring soon',
  },
  'دائم (مدير التطبيق)': {
    AppLanguage.arabic: 'دائم (مدير التطبيق)',
    AppLanguage.french: 'Permanent (administrateur)',
    AppLanguage.english: 'Lifetime (administrator)',
  },
  'منتهي الصلاحية': {
    AppLanguage.arabic: 'منتهي الصلاحية',
    AppLanguage.french: 'Expiré',
    AppLanguage.english: 'Expired',
  },
  'سارٍ ونشط': {
    AppLanguage.arabic: 'سارٍ ونشط',
    AppLanguage.french: 'Actif',
    AppLanguage.english: 'Active',
  },
  'يوم': {
    AppLanguage.arabic: 'يوم',
    AppLanguage.french: 'jour(s)',
    AppLanguage.english: 'day(s)',
  },
  'نعم، امسح': {
    AppLanguage.arabic: 'نعم، امسح',
    AppLanguage.french: 'Oui, effacer',
    AppLanguage.english: 'Yes, clear',
  },
  'هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟': {
    AppLanguage.arabic:
        'هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟',
    AppLanguage.french: 'Voulez-vous effacer tout le dessin et recommencer ?',
    AppLanguage.english: 'Clear the entire drawing and start again?',
  },
  'مراجعة وتجديد الاشتراك': {
    AppLanguage.arabic: 'مراجعة وتجديد الاشتراك',
    AppLanguage.french: 'Consulter et renouveler l’abonnement',
    AppLanguage.english: 'Review and renew subscription',
  },
  'مراجعة تفاصيل الاشتراك': {
    AppLanguage.arabic: 'مراجعة تفاصيل الاشتراك',
    AppLanguage.french: 'Consulter l’abonnement',
    AppLanguage.english: 'Review subscription details',
  },
  'اشتراك 3 أشهر': {
    AppLanguage.arabic: 'اشتراك 3 أشهر',
    AppLanguage.french: 'Abonnement 3 mois',
    AppLanguage.english: '3 Months Subscription',
  },
  'اشتراك شهرين': {
    AppLanguage.arabic: 'اشتراك شهرين',
    AppLanguage.french: 'Abonnement 2 mois',
    AppLanguage.english: '2 Months Subscription',
  },
  'شهر (30 يوما)': {
    AppLanguage.arabic: 'شهر (30 يوما)',
    AppLanguage.french: '1 mois (30 jours)',
    AppLanguage.english: '1 Month (30 days)',
  },
  'شهر (30 يوم)': {
    AppLanguage.arabic: 'شهر (30 يوم)',
    AppLanguage.french: '1 mois (30 jours)',
    AppLanguage.english: '1 Month (30 days)',
  },
  '1 شهر (30 يوم)': {
    AppLanguage.arabic: '1 شهر (30 يوم)',
    AppLanguage.french: '1 mois (30 jours)',
    AppLanguage.english: '1 Month (30 days)',
  },
  'شهران (60 يوما)': {
    AppLanguage.arabic: 'شهران (60 يوما)',
    AppLanguage.french: '2 mois (60 jours)',
    AppLanguage.english: '2 Months (60 days)',
  },
  '3 أشهر (90 يوما)': {
    AppLanguage.arabic: '3 أشهر (90 يوما)',
    AppLanguage.french: '3 mois (90 jours)',
    AppLanguage.english: '3 Months (90 days)',
  },
  'اشتراك سنوي (الأفضل قيمة)': {
    AppLanguage.arabic: 'اشتراك سنوي (الأفضل قيمة)',
    AppLanguage.french: 'Abonnement annuel (Meilleure valeur)',
    AppLanguage.english: 'Annual Subscription (Best value)',
  },
  'الأفضل قيمة': {
    AppLanguage.arabic: 'الأفضل قيمة',
    AppLanguage.french: 'Meilleure valeur',
    AppLanguage.english: 'Best Value',
  },
  'اشتراك دائم للورشة (مدى الحياة)': {
    AppLanguage.arabic: 'اشتراك دائم للورشة (مدى الحياة)',
    AppLanguage.french: 'Abonnement permanent atelier (À vie)',
    AppLanguage.english: 'Permanent Workshop Subscription (Lifetime)',
  },
  'اشتراك دائم للورشة': {
    AppLanguage.arabic: 'اشتراك دائم للورشة',
    AppLanguage.french: 'Abonnement permanent atelier',
    AppLanguage.english: 'Permanent Workshop Subscription',
  },
  'مدى الحياة': {
    AppLanguage.arabic: 'مدى الحياة',
    AppLanguage.french: 'À vie',
    AppLanguage.english: 'Lifetime',
  },
  'الأكثر طلباً': {
    AppLanguage.arabic: 'الأكثر طلباً',
    AppLanguage.french: 'Le plus demandé',
    AppLanguage.english: 'Most Popular',
  },
  '1. اختر باقة الاشتراك': {
    AppLanguage.arabic: '1. اختر باقة الاشتراك',
    AppLanguage.french: '1. Choisissez votre abonnement',
    AppLanguage.english: '1. Select Subscription Plan',
  },
  '2. وسيلة الدفع بالدينار الجزائري': {
    AppLanguage.arabic: '2. وسيلة الدفع بالدينار الجزائري',
    AppLanguage.french: '2. Mode de paiement en DZD',
    AppLanguage.english: '2. Payment Method in DZD',
  },
  'البطاقة الذهبية (Edahabia)': {
    AppLanguage.arabic: 'البطاقة الذهبية (Edahabia)',
    AppLanguage.french: 'Carte Edahabia',
    AppLanguage.english: 'Edahabia Card',
  },
  'دفع فوري آمن لبريد الجزائر مع رمز SMS': {
    AppLanguage.arabic: 'دفع فوري آمن لبريد الجزائر مع رمز SMS',
    AppLanguage.french: 'Paiement instantané Algérie Poste sécurisé par SMS',
    AppLanguage.english: 'Instant secure payment via Algérie Poste with SMS OTP',
  },
  'بطاقة CIB البنكية': {
    AppLanguage.arabic: 'بطاقة CIB البنكية',
    AppLanguage.french: 'Carte bancaire CIB',
    AppLanguage.english: 'CIB Bank Card',
  },
  'جميع البنوك الجزائرية (BNA, BEA, CPA, BDL, BADR, إلخ)': {
    AppLanguage.arabic: 'جميع البنوك الجزائرية (BNA, BEA, CPA, BDL, BADR, إلخ)',
    AppLanguage.french: 'Toutes banques algériennes (BNA, BEA, CPA, BDL, BADR, etc.)',
    AppLanguage.english: 'All Algerian banks (BNA, BEA, CPA, BDL, BADR, etc.)',
  },
  'بريدي موب (BaridiMob)': {
    AppLanguage.arabic: 'بريدي موب (BaridiMob)',
    AppLanguage.french: 'BaridiMob',
    AppLanguage.english: 'BaridiMob',
  },
  'تحويل فوري للتطبيق عبر RIP والـ QR': {
    AppLanguage.arabic: 'تحويل فوري للتطبيق عبر RIP والـ QR',
    AppLanguage.french: 'Virement instantané via RIP et QR code',
    AppLanguage.english: 'Instant transfer via RIP and QR code',
  },
  'تحويل مباشر': {
    AppLanguage.arabic: 'تحويل مباشر',
    AppLanguage.french: 'Virement direct',
    AppLanguage.english: 'Direct transfer',
  },
  'كارت فيزا / ماستركارد (Visa / Mastercard)': {
    AppLanguage.arabic: 'كارت فيزا / ماستركارد (Visa / Mastercard)',
    AppLanguage.french: 'Carte Visa / Mastercard',
    AppLanguage.english: 'Visa / Mastercard',
  },
  'البطاقات الدولية والمحلية المعتمدة': {
    AppLanguage.arabic: 'البطاقات الدولية والمحلية المعتمدة',
    AppLanguage.french: 'Cartes nationales et internationales acceptées',
    AppLanguage.english: 'Accepted domestic & international cards',
  },
  'دولي': {
    AppLanguage.arabic: 'دولي',
    AppLanguage.french: 'International',
    AppLanguage.english: 'International',
  },
  'الأكثر استخداماً': {
    AppLanguage.arabic: 'الأكثر استخداماً',
    AppLanguage.french: 'Le plus utilisé',
    AppLanguage.english: 'Most Used',
  },
  'شبكة SATIM': {
    AppLanguage.arabic: 'شبكة SATIM',
    AppLanguage.french: 'Réseau SATIM',
    AppLanguage.english: 'SATIM Network',
  },
  'إعدادات بوابات الدفع الإلكتروني': {
    AppLanguage.arabic: 'إعدادات بوابات الدفع الإلكتروني',
    AppLanguage.french: 'Paramètres des passerelles de paiement',
    AppLanguage.english: 'Payment Gateway Settings',
  },
  'بوابات الدفع الإلكتروني والاشتراكات': {
    AppLanguage.arabic: 'بوابات الدفع الإلكتروني والاشتراكات',
    AppLanguage.french: 'Passerelles de paiement & Abonnements',
    AppLanguage.english: 'Payment Gateways & Subscriptions',
  },
  'تهيئة وسائل الدفع الرقمي بالبطاقة الذهبية، CIB، فيزا / ماستركارد، وبريدي موب.': {
    AppLanguage.arabic: 'تهيئة وسائل الدفع الرقمي بالبطاقة الذهبية، CIB، فيزا / ماستركارد، وبريدي موب.',
    AppLanguage.french: 'Configuration des paiements Edahabia, CIB, Visa / Mastercard et BaridiMob.',
    AppLanguage.english: 'Configure digital payment methods: Edahabia, CIB, Visa / Mastercard, and BaridiMob.',
  },
  'بريدي موب BaridiMob': {
    AppLanguage.arabic: 'بريدي موب BaridiMob',
    AppLanguage.french: 'BaridiMob',
    AppLanguage.english: 'BaridiMob',
  },
  'رقم CCP / RIP لـ BaridiMob (20 رقماً)': {
    AppLanguage.arabic: 'رقم CCP / RIP لـ BaridiMob (20 رقماً)',
    AppLanguage.french: 'Numéro CCP / RIP BaridiMob (20 chiffres)',
    AppLanguage.english: 'BaridiMob CCP / RIP Number (20 digits)',
  },
  'بوابة الدفع Chargily Pay V2 (الذهبية / CIB / Visa / RedotPay)': {
    AppLanguage.arabic: 'بوابة الدفع Chargily Pay V2 (الذهبية / CIB / Visa / RedotPay)',
    AppLanguage.french: 'Passerelle Chargily Pay V2 (Edahabia / CIB / Visa / RedotPay)',
    AppLanguage.english: 'Chargily Pay V2 Gateway (Edahabia / CIB / Visa / RedotPay)',
  },
  'مفتاح السر لـ Chargily (API Secret Key)': {
    AppLanguage.arabic: 'مفتاح السر لـ Chargily (API Secret Key)',
    AppLanguage.french: 'Clé secrète Chargily (API Secret Key)',
    AppLanguage.english: 'Chargily API Secret Key',
  },
  'الوضع المباشر الحقيقي (Live Mode - مدفوعات حقيقية)': {
    AppLanguage.arabic: 'الوضع المباشر الحقيقي (Live Mode - مدفوعات حقيقية)',
    AppLanguage.french: 'Mode Réel (Live Mode - Paiements réels)',
    AppLanguage.english: 'Live Mode (Real payments)',
  },
  'وضع التجربة (Test Mode - بيئة اختبار مجانية)': {
    AppLanguage.arabic: 'وضع التجربة (Test Mode - بيئة اختبار مجانية)',
    AppLanguage.french: 'Mode Test (Test Mode - Environnement de test)',
    AppLanguage.english: 'Test Mode (Free test environment)',
  },
  'تتم المعاملات المالية الفعلية مع البنوك وبريد الجزائر': {
    AppLanguage.arabic: 'تتم المعاملات المالية الفعلية مع البنوك وبريد الجزائر',
    AppLanguage.french: 'Les transactions financières réelles sont traitées avec les banques et Algérie Poste',
    AppLanguage.english: 'Real financial transactions are processed with banks and Algérie Poste',
  },
  'يستخدم بطاقات الاختبار أو بطاقة RedotPay في وضع التجربة دون خصم أموال حقيقية': {
    AppLanguage.arabic: 'يستخدم بطاقات الاختبار أو بطاقة RedotPay في وضع التجربة دون خصم أموال حقيقية',
    AppLanguage.french: 'Utilise les cartes de test ou RedotPay en mode test sans débit réel',
    AppLanguage.english: 'Uses test cards or RedotPay in test mode without real charges',
  },
  'حفظ إعدادات بوابات الدفع': {
    AppLanguage.arabic: 'حفظ إعدادات بوابات الدفع',
    AppLanguage.french: 'Enregistrer les paramètres de paiement',
    AppLanguage.english: 'Save Payment Settings',
  },
  'تم حفظ إعدادات بوابات الدفع (Chargily & BaridiMob) بنجاح.': {
    AppLanguage.arabic: 'تم حفظ إعدادات بوابات الدفع (Chargily & BaridiMob) بنجاح.',
    AppLanguage.french: 'Paramètres des passerelles de paiement (Chargily & BaridiMob) enregistrés avec succès.',
    AppLanguage.english: 'Payment gateway settings (Chargily & BaridiMob) saved successfully.',
  },
  'تعذر حفظ إعدادات الدفع:': {
    AppLanguage.arabic: 'تعذر حفظ إعدادات الدفع:',
    AppLanguage.french: 'Impossible d\'enregistrer les paramètres de paiement :',
    AppLanguage.english: 'Could not save payment settings:',
  },
  'تعذر فتح صفحة الدفع البنكية.': {
    AppLanguage.arabic: 'تعذر فتح صفحة الدفع البنكية.',
    AppLanguage.french: 'Impossible d\'ouvrir la page de paiement bancaire.',
    AppLanguage.english: 'Unable to open the bank payment page.',
  },
  'تعذر إنشاء جلسة الدفع الإلكتروني، يرجى المحاولة لاحقاً أو التحقق من الإعدادات.': {
    AppLanguage.arabic: 'تعذر إنشاء جلسة الدفع الإلكتروني، يرجى المحاولة لاحقاً أو التحقق من الإعدادات.',
    AppLanguage.french: 'Échec de création de la session de paiement. Veuillez réessayer plus tard ou vérifier les paramètres.',
    AppLanguage.english: 'Failed to create payment session. Please try again later or check settings.',
  },
  'حدث خطأ أثناء الاتصال ببوابة الدفع:': {
    AppLanguage.arabic: 'حدث خطأ أثناء الاتصال ببوابة الدفع:',
    AppLanguage.french: 'Une erreur est survenue lors de la connexion à la passerelle de paiement :',
    AppLanguage.english: 'An error occurred while connecting to the payment gateway:',
  },
  'بانتظار إتمام الدفع...': {
    AppLanguage.arabic: 'بانتظار إتمام الدفع...',
    AppLanguage.french: 'En attente de paiement...',
    AppLanguage.english: 'Awaiting payment...',
  },
  'تم فتح صفحة الدفع الآمنة على المتصفح.\nيرجى إدخال بيانات البطاقة والرمز السري SMS المرسل إلى هاتفك لإتمام المعاملة.': {
    AppLanguage.arabic: 'تم فتح صفحة الدفع الآمنة على المتصفح.\nيرجى إدخال بيانات البطاقة والرمز السري SMS المرسل إلى هاتفك لإتمام المعاملة.',
    AppLanguage.french: 'La page sécurisée a été ouverte dans le navigateur.\nVeuillez saisir vos coordonnées de carte et le code SMS reçu pour finaliser la transaction.',
    AppLanguage.english: 'The secure payment page was opened in the browser.\nPlease enter card details and the SMS code sent to your phone to complete.',
  },
  'تحقق من تفعيل الدفع': {
    AppLanguage.arabic: 'تحقق من تفعيل الدفع',
    AppLanguage.french: 'Vérifier l\'activation',
    AppLanguage.english: 'Check Activation',
  },
  'تم الدفع وتفعيل الاشتراك بنجاح!': {
    AppLanguage.arabic: 'تم الدفع وتفعيل الاشتراك بنجاح!',
    AppLanguage.french: 'Paiement effectué et abonnement activé avec succès !',
    AppLanguage.english: 'Payment successful and subscription activated!',
  },
  'تم تجديد اشتراك الورشة لـ': {
    AppLanguage.arabic: 'تم تجديد اشتراك الورشة لـ',
    AppLanguage.french: 'L\'abonnement de l\'atelier a été renouvelé pour',
    AppLanguage.english: 'Workshop subscription renewed for',
  },
  'شكراً لثقتكم!': {
    AppLanguage.arabic: 'شكراً لثقتكم!',
    AppLanguage.french: 'Merci pour votre confiance !',
    AppLanguage.english: 'Thank you for your trust!',
  },
  'العودة للتطبيق': {
    AppLanguage.arabic: 'العودة للتطبيق',
    AppLanguage.french: 'Retour à l\'application',
    AppLanguage.english: 'Back to app',
  },
  'لم يتم تأكيد الدفع بعد (الحالة الحالية: ': {
    AppLanguage.arabic: 'لم يتم تأكيد الدفع بعد (الحالة الحالية: ',
    AppLanguage.french: 'Le paiement n\'est pas encore confirmé (Statut actuel : ',
    AppLanguage.english: 'Payment not confirmed yet (Current status: ',
  },
  '). يرجى إتمام العملية وإعادة المحاولة.': {
    AppLanguage.arabic: '). يرجى إتمام العملية وإعادة المحاولة.',
    AppLanguage.french: '). Veuillez finaliser et réessayer.',
    AppLanguage.english: '). Please complete and retry.',
  },
  'قيد المعالجة': {
    AppLanguage.arabic: 'قيد المعالجة',
    AppLanguage.french: 'En cours de traitement',
    AppLanguage.english: 'Processing',
  },
  'حدث خطأ أثناء فحص حالة المعاملة:': {
    AppLanguage.arabic: 'حدث خطأ أثناء فحص حالة المعاملة:',
    AppLanguage.french: 'Erreur lors de la vérification de la transaction :',
    AppLanguage.english: 'Error checking transaction status:',
  },
  'يرجى إدخال رقم المعاملة من تطبيق بريدي موب.': {
    AppLanguage.arabic: 'يرجى إدخال رقم المعاملة من تطبيق بريدي موب.',
    AppLanguage.french: 'Veuillez saisir le numéro de transaction BaridiMob.',
    AppLanguage.english: 'Please enter the BaridiMob transaction number.',
  },
  'تم استلام معلومات التحويل': {
    AppLanguage.arabic: 'تم استلام معلومات التحويل',
    AppLanguage.french: 'Informations de virement reçues',
    AppLanguage.english: 'Transfer details received',
  },
  'تم إرسال إشعار الدفع عبر بريدي موب للإدارة.\nسيتم مراجعة رقم المعاملة وتفعيل الاشتراك خلال دقائق معدودة.': {
    AppLanguage.arabic: 'تم إرسال إشعار الدفع عبر بريدي موب للإدارة.\nسيتم مراجعة رقم المعاملة وتفعيل الاشتراك خلال دقائق معدودة.',
    AppLanguage.french: 'Notification de paiement BaridiMob envoyée à l\'administration.\nLe numéro sera vérifié et l\'abonnement activé sous peu.',
    AppLanguage.english: 'BaridiMob notification sent to administration.\nThe reference will be verified and subscription activated promptly.',
  },
  'حدث خطأ أثناء إرسال الإشعار:': {
    AppLanguage.arabic: 'حدث خطأ أثناء إرسال الإشعار:',
    AppLanguage.french: 'Erreur lors de l\'envoi de la notification :',
    AppLanguage.english: 'Error sending notification:',
  },
  'الدفع الإلكتروني وتجديد الاشتراك': {
    AppLanguage.arabic: 'الدفع الإلكتروني وتجديد الاشتراك',
    AppLanguage.french: 'Paiement électronique & Renouvellement',
    AppLanguage.english: 'Electronic Payment & Renewal',
  },
  'بوابة الدفع الإلكتروني المعتمدة': {
    AppLanguage.arabic: 'بوابة الدفع الإلكتروني المعتمدة',
    AppLanguage.french: 'Passerelle de paiement certifiée',
    AppLanguage.english: 'Certified Payment Gateway',
  },
  'الدفع متاح الآن مباشرة بالبطاقات الجزائرية دون الحاجة للتنقل': {
    AppLanguage.arabic: 'الدفع متاح الآن مباشرة بالبطاقات الجزائرية دون الحاجة للتنقل',
    AppLanguage.french: 'Le paiement est disponible directement par cartes algériennes sans déplacement',
    AppLanguage.english: 'Payment is directly available with Algerian cards from anywhere',
  },
  'الذهبية': {
    AppLanguage.arabic: 'الذهبية',
    AppLanguage.french: 'Edahabia',
    AppLanguage.english: 'Edahabia',
  },
  'CIB': {
    AppLanguage.arabic: 'CIB',
    AppLanguage.french: 'CIB',
    AppLanguage.english: 'CIB',
  },
  'BaridiMob': {
    AppLanguage.arabic: 'BaridiMob',
    AppLanguage.french: 'BaridiMob',
    AppLanguage.english: 'BaridiMob',
  },
  'المبلغ الإجمالي للدفع:': {
    AppLanguage.arabic: 'المبلغ الإجمالي للدفع:',
    AppLanguage.french: 'Montant total à payer :',
    AppLanguage.english: 'Total amount to pay:',
  },
  'جاري تجهيز بوابة الدفع...': {
    AppLanguage.arabic: 'جاري تجهيز بوابة الدفع...',
    AppLanguage.french: 'Préparation du paiement...',
    AppLanguage.english: 'Preparing payment gateway...',
  },
  'ادفع الآن بالبطاقة': {
    AppLanguage.arabic: 'ادفع الآن بالبطاقة',
    AppLanguage.french: 'Payer par carte',
    AppLanguage.english: 'Pay with card',
  },
  'خطوات الدفع عبر بريدي موب (BaridiMob):': {
    AppLanguage.arabic: 'خطوات الدفع عبر بريدي موب (BaridiMob):',
    AppLanguage.french: 'Étapes de paiement via BaridiMob :',
    AppLanguage.english: 'Payment steps via BaridiMob:',
  },
  '1. انسخ رقم الـ RIP أدناه.\n2. افتح تطبيق BaridiMob وقم بإجراء تحويل بالمبلغ المطلوب.\n3. ضع رقم المعاملة (N° de transaction) هنا لتفعيل اشتراكك.': {
    AppLanguage.arabic: '1. انسخ رقم الـ RIP أدناه.\n2. افتح تطبيق BaridiMob وقم بإجراء تحويل بالمبلغ المطلوب.\n3. ضع رقم المعاملة (N° de transaction) هنا لتفعيل اشتراكك.',
    AppLanguage.french: '1. Copiez le numéro RIP ci-dessous.\n2. Ouvrez BaridiMob et effectuez le virement du montant.\n3. Saisissez ici le N° de transaction pour activer votre abonnement.',
    AppLanguage.english: '1. Copy the RIP number below.\n2. Open BaridiMob and transfer the required amount.\n3. Enter the transaction number here to activate your subscription.',
  },
  'رقم الحساب البريدي (RIP):': {
    AppLanguage.arabic: 'رقم الحساب البريدي (RIP):',
    AppLanguage.french: 'Numéro de compte postal (RIP) :',
    AppLanguage.english: 'Postal Account Number (RIP):',
  },
  'نسخ رقم الـ RIP': {
    AppLanguage.arabic: 'نسخ رقم الـ RIP',
    AppLanguage.french: 'Copier le RIP',
    AppLanguage.english: 'Copy RIP',
  },
  'تم نسخ رقم الـ RIP بنجاح': {
    AppLanguage.arabic: 'تم نسخ رقم الـ RIP بنجاح',
    AppLanguage.french: 'Numéro RIP copié avec succès',
    AppLanguage.english: 'RIP number copied successfully',
  },
  'رقم معاملة بريدي موب (Numéro de transaction)': {
    AppLanguage.arabic: 'رقم معاملة بريدي موب (Numéro de transaction)',
    AppLanguage.french: 'N° de transaction BaridiMob',
    AppLanguage.english: 'BaridiMob Transaction Number',
  },
  'ملاحظة إضافية (اختياري - اسم الورشة أو رقم الهاتف)': {
    AppLanguage.arabic: 'ملاحظة إضافية (اختياري - اسم الورشة أو رقم الهاتف)',
    AppLanguage.french: 'Remarque (Optionnel - nom atelier ou tél)',
    AppLanguage.english: 'Additional Note (Optional - workshop name or phone)',
  },
  'تأكيد التحويل وإرسال الإشعار': {
    AppLanguage.arabic: 'تأكيد التحويل وإرسال الإشعار',
    AppLanguage.french: 'Confirmer le virement & envoyer',
    AppLanguage.english: 'Confirm Transfer & Submit',
  },
  'دفع مشفر وآمن 100% ومطابق لمعايير الأمان البنكي وبريد الجزائر': {
    AppLanguage.arabic: 'دفع مشفر وآمن 100% ومطابق لمعايير الأمان البنكي وبريد الجزائر',
    AppLanguage.french: 'Paiement sécurisé et chiffré à 100% conforme aux normes bancaires et Algérie Poste',
    AppLanguage.english: '100% encrypted & secure payment compliant with banking and Algérie Poste standards',
  },
};
