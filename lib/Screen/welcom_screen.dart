import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../Cliente/client.dart';
import '../Commande/Systeme/model.dart';
import '../Commande/commande.dart';
import '../items_produits/products_menu_screen.dart';
import '../sql_database.dart';
import 'drawer.dart';
import 'settings_screen.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';

class WelcomScreen extends StatefulWidget {
  const WelcomScreen({super.key});

  @override
  State<WelcomScreen> createState() => _WelcomScreenState();
}

class _WelcomScreenState extends State<WelcomScreen> {
  final SqlDatabase db = SqlDatabase();

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _card = Color(0xFFFFFFFF);
  static const _blue = Color(0xFF3B82F6);
  static const _cyan = Color(0xFF06B6D4);
  static const _amber = Color(0xFFF59E0B);
  static const _green = Color(0xFF10B981);
  static const _purple = Color(0xFF8B5CF6);
  static const _text = Color(0xFF1E293B);
  static const _textDim = Color(0xFF94A3B8);
  static const _divider = Color(0xFFE2E8F0);

  //static const _divider = Color(0xFFE2E8F0);

  String _workshopName = 'ورشة النجارة';
  String _userEmail = 'جاري التحميل...';
  String? _logoUrl;
  StreamSubscription? _userSub;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userEmail = user.email ?? 'لا يوجد بريد';
      });
      _userSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
            if (doc.exists && mounted) {
              final data = doc.data() as Map<String, dynamic>;
              setState(() {
                _workshopName = data['workshopName'] ?? 'ورشة النجارة';
                if (data['email'] != null) {
                  _userEmail = data['email'];
                }
                _logoUrl = data['logoUrl'];
              });
            }
          });
          
      // بدء الاستماع لتحديثات الأجهزة الأخرى (المزامنة التلقائية)
      await CloudSyncService().init();
      CloudSyncService().startListeningForUpdates(() {
        if (mounted) {
          // إعادة تحميل الواجهة إذا حصل تغيير من هاتف آخر
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم مزامنة بيانات جديدة من السحابة 🔄'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            )
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    CloudSyncService().stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      drawer: AppDrawer(),
      body: CustomScrollView(
        slivers: [
          _buildSliverHeader(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── إحصائيات ────────────────────────────────────────
                _buildStatsRow(context),
                const SizedBox(height: 24),

                // ── عنوان القسم ──────────────────────────────────────
                _sectionLabel('Navigation rapide'),
                const SizedBox(height: 12),

                // ── شبكة التنقل ──────────────────────────────────────
                _buildNavGrid(context),
                const SizedBox(height: 24),

                // ── عنوان القسم ──────────────────────────────────────
                _sectionLabel('Activité récente'),
                const SizedBox(height: 12),

                // ── قائمة النشاط ─────────────────────────────────────
                _buildActivityCard(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── SliverAppBar ──────────────────────────────────────────────────────────
  Widget _buildSliverHeader(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
          ),
          onPressed: () {},
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // دوائر زخرفية
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                top: 20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              // المحتوى
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // أفاتار الشركة
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_blue, _cyan],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        image: _logoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_logoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _logoUrl == null
                          ? const Icon(
                              Icons.carpenter_rounded,
                              color: Colors.white,
                              size: 28,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _workshopName,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _userEmail,
                          style: const TextStyle(color: _textDim, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // بادج الحالة
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _green.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: _green,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Actif',
                            style: TextStyle(
                              color: _green,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        title: Text(
          _workshopName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
        collapseMode: CollapseMode.pin,
      ),
    );
  }

  // ── صف الإحصائيات ────────────────────────────────────────────────────────
  Widget _buildStatsRow(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.receipt_long_rounded,
            label: Localization.translate('commandes', lang),
            value: '50',
            color: _blue,
            trend: '+12%',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.people_alt_rounded,
            label: Localization.translate('clients', lang),
            value: '35',
            color: _purple,
            trend: '+5%',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.inventory_2_rounded,
            label: Localization.translate('produits', lang),
            value: '18',
            color: _amber,
            trend: '—',
          ),
        ),
      ],
    );
  }

  // ── شبكة التنقل ──────────────────────────────────────────────────────────
  Widget _buildNavGrid(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final items = [
      _NavItem(
        icon: Icons.receipt_long_rounded,
        label: Localization.translate('commandes', lang),
        color: _blue,
        onTap: () => Navigator.push(context, _slide(const Commande())),
      ),
      _NavItem(
        icon: Icons.people_alt_rounded,
        label: Localization.translate('clients', lang),
        color: _purple,
        onTap: () => Navigator.push(context, _slide(const Customers())),
      ),
      _NavItem(
        icon: Icons.inventory_2_rounded,
        label: Localization.translate('produits', lang),
        color: _amber,
        onTap: () {
          Navigator.push(context, _slide(ProductsMenuScreen(db: db)));
        },
      ),
      _NavItem(
        icon: Icons.settings_rounded,
        label: Localization.translate('settings', lang),
        color: const Color(0xFF6B7280),
        onTap: () {
          Navigator.push(context, _slide(const SettingsScreen()));
        },
      ),
      _NavItem(
        icon: Icons.bar_chart_rounded,
        label: Localization.translate('rapports', lang),
        color: _cyan,
        onTap: () {},
      ),
      _NavItem(
        icon: Icons.add_circle_rounded,
        label: Localization.translate('nouveau', lang),
        color: _green,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(
                'اختيار نوع النظام',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.sensor_window,
                      color: Colors.blue,
                      size: 30,
                    ),
                    title: const Text(
                      'نظام فتح (Frappe)',
                      style: TextStyle(fontSize: 18),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WindowView(
                            systemMode: 'french',
                            model: WindowModel(db: db),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.door_sliding,
                      color: Colors.orange,
                      size: 30,
                    ),
                    title: const Text(
                      'نظام منزلق (Coulissant)',
                      style: TextStyle(fontSize: 18),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WindowView(
                            systemMode: 'sliding',
                            model: WindowModel(db: db),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.05,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _NavCard(item: items[i]),
    );
  }

  // ── بطاقة النشاط الأخير ──────────────────────────────────────────────────
  Widget _buildActivityCard() {
    final activities = [
      _Activity(
        'Nouvelle commande #048',
        'Il y a 5 min',
        Icons.add_box_rounded,
        _green,
      ),
      _Activity(
        'Client Ahmed Benali ajouté',
        'Il y a 1h',
        Icons.person_add_rounded,
        _blue,
      ),
      _Activity(
        'Commande #045 terminée',
        'Hier, 16:30',
        Icons.check_circle_rounded,
        _cyan,
      ),
      _Activity(
        'Produit "Porte PVC" modifié',
        'Hier, 11:00',
        Icons.edit_rounded,
        _amber,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: activities.asMap().entries.map((e) {
          final isLast = e.key == activities.length - 1;
          return Column(
            children: [
              _ActivityRow(activity: e.value),
              if (!isLast)
                Divider(height: 1, color: _divider, indent: 56, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  PageRouteBuilder _slide(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, a, _) => page,
      transitionsBuilder: (_, a, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// بطاقة إحصائية
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String trend;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.trend,
  });

  static const _card = Color(0xFFFFFFFF);
  static const _divider = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
          ),
          const SizedBox(height: 6),
          Text(
            trend,
            style: TextStyle(
              color: trend == '—'
                  ? const Color(0xFF64748B)
                  : const Color(0xFF10B981),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// بند التنقل
class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// بطاقة تنقل
class _NavCard extends StatefulWidget {
  final _NavItem item;

  const _NavCard({required this.item});

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _pressed = false;

  static const _card = Color(0xFFFFFFFF);
  static const _divider = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.item.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            color: _pressed ? widget.item.color.withValues(alpha: 0.08) : _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed
                  ? widget.item.color.withValues(alpha: 0.35)
                  : _divider,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  widget.item.icon,
                  color: widget.item.color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.item.label,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بند النشاط
class _Activity {
  final String title;
  final String time;
  final IconData icon;
  final Color color;

  const _Activity(this.title, this.time, this.icon, this.color);
}

class _ActivityRow extends StatelessWidget {
  final _Activity activity;

  const _ActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(activity.icon, color: activity.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.time,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: const Color(0xFFCBD5E1),
            size: 18,
          ),
        ],
      ),
    );
  }
}
