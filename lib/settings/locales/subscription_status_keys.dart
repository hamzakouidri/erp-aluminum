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
};
