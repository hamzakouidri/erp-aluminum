import 'dart:convert';
import 'package:database_data/widgets/app_material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_workshop_sync_service.dart';
import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import 'package:database_data/services/auth_service.dart';

String _tr(String ar, String fr, String en, AppLanguage lang) {
  if (lang == AppLanguage.french) return fr;
  if (lang == AppLanguage.english) return en;
  return ar;
}

class WorkersManagementScreen extends StatefulWidget {
  final SqlDatabase db;

  const WorkersManagementScreen({super.key, required this.db});

  @override
  State<WorkersManagementScreen> createState() =>
      _WorkersManagementScreenState();
}

class _WorkersManagementScreenState extends State<WorkersManagementScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;
  String _joinCode = 'جاري التحميل...';

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  /// هل المستخدم الحالي نائب مدير (عامل بصلاحية manage_workers) وليس المدير الأصلي؟
  bool get _isDeputyManager {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    return !settings.isManager && settings.canManageWorkers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    // إغلاق الصفحة فوراً إذا سُحبت صلاحية إدارة الفريق
    if (!settings.isManager && !settings.canManageWorkers()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    setState(() => _isLoading = true);
    try {
      final rawData = await widget.db.readEmployees();
      List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        rawData,
      );

      final user = AppAuthService().currentUser;
      String? workshopId;

      // Remove manager if accidentally added to local DB
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final managerUid =
            (prefs.getString('workshop_code')?.isNotEmpty == true)
            ? prefs.getString('workshop_code')!
            : user.uid;
        workshopId = managerUid;

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(managerUid)
            .get();
        if (doc.exists && doc.data() != null) {
          _joinCode = doc.data()!['joinCode'] ?? managerUid;
        } else {
          _joinCode = managerUid;
        }

        final managerInDb = data.where((w) => w['uid'] == managerUid).toList();
        for (var m in managerInDb) {
          await widget.db.deleteEmployee(m['uid']);
        }
        data.removeWhere((w) => w['uid'] == managerUid || w['uid'] == user.uid);
      }

      // ✅ فلترة وتصفية القائمة: لا نعرض العمال المحليين (local_worker_) ولا من ليس لديهم إيميل حقيقي
      data.removeWhere((w) {
        final uid = w['uid']?.toString() ?? '';
        final email = (w['email'] ?? '').toString().trim().toLowerCase();
        return uid.startsWith('local_worker_') ||
            email.isEmpty ||
            email == 'no email' ||
            email == 'no_email';
      });

      if (workshopId != null && workshopId.isNotEmpty) {
        await _repairWorkerWorkshopLinks(data, workshopId);
      }

      data = await _applySupabaseMembershipFilter(data);

      setState(() {
        _workers = data;
      });
    } catch (e) {
      print('Error loading workers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Repairs older worker documents that were created without the manager's
  /// workshop id. Without this value a worker would upload to a private path
  /// instead of the shared workshop backup.
  Future<void> _repairWorkerWorkshopLinks(
    List<Map<String, dynamic>> workers,
    String workshopId,
  ) async {
    try {
      var batch = FirebaseFirestore.instance.batch();
      var count = 0;
      for (final worker in workers) {
        final uid = worker['uid']?.toString() ?? '';
        if (uid.isEmpty || uid.startsWith('local_worker_')) continue;
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(uid),
          {'workshopId': workshopId},
          SetOptions(merge: true),
        );
        count++;
        if (count == 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      debugPrint('Unable to repair worker workshop links: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _applySupabaseMembershipFilter(
    List<Map<String, dynamic>> localWorkers,
  ) async {
    final service = SupabaseWorkshopSyncService();
    if (!service.isSignedIn) return localWorkers;

    List<Map<String, dynamic>> members;
    try {
      members = await service.fetchWorkshopMembers();
    } catch (error) {
      debugPrint('Unable to load Supabase workshop members: $error');
      return localWorkers;
    }
    // The signed-in account manages this list and is never one of its
    // workers, whatever its role in the workshop: listing it let the owner
    // edit, block or delete their own access. The first filter in
    // [_loadWorkers] used local uids only, so the Supabase rows brought the
    // account back.
    final currentUser = AppAuthService().currentUser;
    final currentEmail = currentUser?.email?.trim().toLowerCase() ?? '';
    final currentUid = currentUser?.uid.trim() ?? '';
    bool isCurrentAccount(String uid, String email) =>
        (currentEmail.isNotEmpty && email == currentEmail) ||
        (currentUid.isNotEmpty &&
            (uid == currentUid || uid == 'supabase_$currentUid'));
    members = members
        .where((member) {
          final email =
              member['email']?.toString().trim().toLowerCase() ?? '';
          final userId = member['user_id']?.toString().trim() ?? '';
          return !isCurrentAccount(userId, email);
        })
        .toList(growable: false);
    if (members.isEmpty) {
      return localWorkers
          .where(
            (worker) => !isCurrentAccount(
              worker['uid']?.toString() ?? '',
              worker['email']?.toString().trim().toLowerCase() ?? '',
            ),
          )
          .toList(growable: false);
    }

    await _upsertSupabaseMembersIntoLocal(members, localWorkers);
    final refreshed = List<Map<String, dynamic>>.from(
      await widget.db.readEmployees(),
    );

    final allowedEmails = members
        .map((member) => member['email']?.toString().trim().toLowerCase() ?? '')
        .where((email) => email.isNotEmpty && email != 'no email')
        .toSet();
    final allowedGeneratedUids = members
        .map((member) {
          final email = member['email']?.toString().trim().toLowerCase() ?? '';
          return _uidForSupabaseMember(member, email);
        })
        .where((uid) => uid.isNotEmpty)
        .toSet();

    refreshed.removeWhere((worker) {
      final uid = worker['uid']?.toString() ?? '';
      final email = worker['email']?.toString().trim().toLowerCase() ?? '';
      return uid.startsWith('local_worker_') ||
          email.isEmpty ||
          email == 'no email' ||
          email == 'no_email' ||
          isCurrentAccount(uid, email) ||
          (!allowedEmails.contains(email) &&
              !allowedGeneratedUids.contains(uid));
    });

    return refreshed;
  }

  Future<void> _upsertSupabaseMembersIntoLocal(
    List<Map<String, dynamic>> members,
    List<Map<String, dynamic>> existingWorkers,
  ) async {
    final byEmail = <String, Map<String, dynamic>>{};
    final byUid = <String, Map<String, dynamic>>{};
    for (final worker in existingWorkers) {
      final uid = worker['uid']?.toString() ?? '';
      final email = worker['email']?.toString().trim().toLowerCase() ?? '';
      if (uid.isNotEmpty) byUid[uid] = worker;
      if (email.isNotEmpty) byEmail[email] = worker;
    }

    for (final member in members) {
      final email = member['email']?.toString().trim().toLowerCase() ?? '';
      if (email.isEmpty) continue;
      final uid = _uidForSupabaseMember(member, email);
      if (uid.isEmpty) continue;

      final permissions = member['permissions'] is Map
          ? Map<String, dynamic>.from(member['permissions'])
          : <String, dynamic>{};
      if (member['blocked'] == true) {
        permissions['isBlocked'] = true;
      }
      final permissionsJson = jsonEncode(permissions);
      final existing = byEmail[email] ?? byUid[uid];

      if (existing == null) {
        final name = email.split('@').first.trim();
        await widget.db.insertEmployee(
          uid,
          email,
          name.isEmpty ? 'عامل جديد' : name,
          permissionsJson,
        );
      } else {
        final existingUid = existing['uid']?.toString() ?? '';
        final isSupabaseBacked =
            existingUid.startsWith('supabase_') ||
            existingUid.startsWith('pending_supabase_');
        // Firebase worker documents are the authoritative permission source
        // for legacy/dual-auth accounts. A stale Supabase membership row must
        // not overwrite a freshly saved deputy-manager permission locally.
        if (isSupabaseBacked) {
          await widget.db.updateEmployeePermissions(
            existingUid,
            permissionsJson,
          );
        }
      }
    }
  }

  String _uidForSupabaseMember(Map<String, dynamic> member, String email) {
    final userId = member['user_id']?.toString().trim() ?? '';
    if (userId.isNotEmpty) return 'supabase_$userId';
    if (email.isEmpty) return '';
    final key = base64Url.encode(utf8.encode(email)).replaceAll('=', '');
    return 'pending_supabase_$key';
  }

  Future<void> _fetchWorkersFromCloud() async {
    setState(() => _isLoading = true);
    try {
      final service = SupabaseWorkshopSyncService();
      if (service.isSignedIn) {
        final localWorkers = List<Map<String, dynamic>>.from(
          await widget.db.readEmployees(),
        );
        final workers = await _applySupabaseMembershipFilter(localWorkers);
        if (mounted) {
          setState(() {
            _workers = workers;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('تم تحديث العمال من Supabase بنجاح')),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      final user = AppAuthService().currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final targetWorkshopId =
          (prefs.getString('workshop_code')?.isNotEmpty == true)
          ? prefs.getString('workshop_code')!
          : user.uid;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('workshopId', isEqualTo: targetWorkshopId)
          .get();

      final existingWorkers = await widget.db.readEmployees();
      final existingUids = existingWorkers
          .map((w) => w['uid'].toString())
          .toSet();

      for (var doc in snapshot.docs) {
        if (doc.id == targetWorkshopId || doc.id == user.uid)
          continue; // Exclude manager & self

        final data = doc.data();
        if (!existingUids.contains(doc.id)) {
          final cloudEmail = (data['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          Map<String, dynamic>? matchingLocalWorker;
          if (cloudEmail.isNotEmpty && cloudEmail != 'no email') {
            for (var ew in existingWorkers) {
              final ewUid = ew['uid'].toString();
              final ewEmail = (ew['email'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (ewUid.startsWith('local_worker_') && ewEmail == cloudEmail) {
                matchingLocalWorker = ew;
                break;
              }
            }
          }

          if (matchingLocalWorker != null) {
            // Link local worker to the Firebase account automatically
            await widget.db.linkLocalWorker(
              matchingLocalWorker['uid'].toString(),
              doc.id,
              data['email'] ?? 'No Email',
            );
          } else {
            // New worker found in cloud, preserve their cloud permissions if present, else use default
            String workerPermissionsJson;
            if (data['permissions_json'] is String &&
                (data['permissions_json'] as String).isNotEmpty) {
              workerPermissionsJson = data['permissions_json'];
            } else if (data['permissions'] is Map) {
              workerPermissionsJson = jsonEncode(data['permissions']);
            } else {
              workerPermissionsJson = jsonEncode({
                'view_clients': true,
                'create_clients': false,
                'view_orders': true,
                'create_orders': false,
                'view_client_details': true,
                'view_order_details': true,
                'view_my_tasks': true,
                'view_my_accreditations': true,
                'isBlocked': false,
              });
            }

            await widget.db.insertEmployee(
              doc.id,
              data['email'] ?? 'No Email',
              (data['displayName'] as String?)?.trim().isNotEmpty == true
                  ? data['displayName'].toString().trim()
                  : (data['name'] as String?)?.trim().isNotEmpty == true
                  ? data['name'].toString().trim()
                  : 'عامل جديد',
              workerPermissionsJson,
            );
          }
        } else {
          // ✅ العامل موجود مسبقاً — نحدّث اسمه إذا كان "عامل جديد" أو فارغاً
          final cloudDisplayName =
              (data['displayName'] as String?)?.trim() ?? '';
          final cloudName = (data['name'] as String?)?.trim() ?? '';
          final resolvedName = cloudDisplayName.isNotEmpty
              ? cloudDisplayName
              : cloudName.isNotEmpty
              ? cloudName
              : '';
          if (resolvedName.isNotEmpty) {
            final existingWorker = existingWorkers.firstWhere(
              (w) => w['uid'].toString() == doc.id,
              orElse: () => {},
            );
            final currentName = (existingWorker['name'] ?? '')
                .toString()
                .trim();
            if (currentName.isEmpty || currentName == 'عامل جديد') {
              final dbInstance = await widget.db.db;
              await dbInstance?.update(
                'Employees',
                {'name': resolvedName},
                where: 'uid = ?',
                whereArgs: [doc.id],
              );
            }
          }
        }
      }

      await _loadWorkers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('تم مزامنة العمال بنجاح')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_t('خطأ في الاتصال بالسحابة')}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _parsePermissions(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  bool _isWorkerPending(Map<String, dynamic> worker) {
    final perms = _parsePermissions(worker['permissions_json'] ?? worker['permissions']);
    if (perms['is_rejected'] == true) return false;
    if (perms['is_pending'] == true) return true;
    if (perms['isBlocked'] == true &&
        (perms['view_clients'] != true && perms['view_orders'] != true)) {
      return true;
    }
    return false;
  }

  Future<void> _approveWorker(Map<String, dynamic> worker) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final workerUid = worker['uid']?.toString() ?? '';
    final workerEmail = (worker['email'] ?? '').toString().trim();
    final workerName = (worker['name'] ?? '').toString().trim();

    if (workerEmail.isEmpty && workerUid.isEmpty) return;

    final standardPerms = <String, dynamic>{
      'view_clients': true,
      'view_orders': true,
      'view_client_details': true,
      'view_order_details': true,
      'view_my_tasks': true,
      'view_my_accreditations': true,
      'access_workshop': true,
      'access_store': true,
      'isBlocked': false,
      'is_pending': false,
      'is_approved': true,
    };

    final permsJson = jsonEncode(standardPerms);

    try {
      // 1. Update SQLite
      if (workerUid.isNotEmpty) {
        await widget.db.updateEmployeePermissions(workerUid, permsJson);
      }

      // 2. Update Supabase
      if (workerEmail.isNotEmpty) {
        try {
          await SupabaseWorkshopSyncService().updateMemberPermissionsByEmail(
            email: workerEmail,
            role: 'worker',
            permissions: standardPerms,
          );
        } catch (e) {
          debugPrint('Supabase member approval sync: $e');
        }
      }

      // 3. Update Firebase if needed
      final isFirebaseWorker =
          !workerUid.startsWith('supabase_') &&
          !workerUid.startsWith('pending_supabase_') &&
          workerUid.isNotEmpty;
      if (isFirebaseWorker) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(workerUid).update({
            'isBlocked': false,
            'is_pending': false,
            'role': 'worker',
            'permissions': standardPerms,
            'permissions_json': permsJson,
          });
        } catch (e) {
          debugPrint('Firebase worker approval sync: $e');
        }
      }

      await _loadWorkers();

      if (mounted) {
        final successMsg = switch (lang) {
          AppLanguage.french => 'Ouvrier "$workerName" accepté avec succès !',
          AppLanguage.english => 'Worker "$workerName" approved successfully!',
          _ => 'تم قبول طلب انضمام "$workerName" وتفعيل حسابه بنجاح!',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    successMsg,
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء قبول الطلب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectWorker(Map<String, dynamic> worker) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final workerEmail = (worker['email'] ?? '').toString().trim();
    final workerName = (worker['name'] ?? '').toString().trim();
    if (workerEmail.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(switch (lang) {
              AppLanguage.french => 'Refuser la demande',
              AppLanguage.english => 'Reject request',
              _ => 'رفض طلب الانضمام',
            }),
            content: Text(switch (lang) {
              AppLanguage.french => 'Voulez-vous vraiment refuser la demande de $workerEmail ?',
              AppLanguage.english => 'Do you really want to reject the request from $workerEmail?',
              _ => 'هل تريد فعلاً رفض طلب الانضمام من $workerEmail؟',
            }),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(switch (lang) {
                  AppLanguage.french => 'Annuler',
                  AppLanguage.english => 'Cancel',
                  _ => 'إلغاء',
                }),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: Text(switch (lang) {
                  AppLanguage.french => 'Refuser',
                  AppLanguage.english => 'Reject',
                  _ => 'رفض',
                }),
              ),
            ],
          ),
        ) ?? false;
    if (!confirmed || !mounted) return;

    try {
      await SupabaseWorkshopSyncService().rejectPendingMemberByEmail(email: workerEmail);
      await _loadWorkers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(switch (lang) {
          AppLanguage.french => 'Demande de "$workerName" refusée.',
          AppLanguage.english => 'Request from "$workerName" rejected.',
          _ => 'تم رفض طلب انضمام "$workerName".',
        }),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('تعذر رفض طلب الانضمام: $error'),
      ));
    }
  }

  Widget _buildPendingRequestsCard(
    List<Map<String, dynamic>> pendingWorkers,
    AppLanguage lang,
    bool isDark,
  ) {
    if (pendingWorkers.isEmpty) return const SizedBox.shrink();

    final title = switch (lang) {
      AppLanguage.french => 'Nouvelles demandes d\'adhésion (${pendingWorkers.length})',
      AppLanguage.english => 'New Join Requests (${pendingWorkers.length})',
      _ => 'طلبات الانضمام الجديدة إلى ورشتك (${pendingWorkers.length})',
    };

    final hint = switch (lang) {
      AppLanguage.french =>
        'Ces ouvriers ont saisi votre code d\'atelier. Appuyez sur "Accepter" pour leur donner accès.',
      AppLanguage.english =>
        'These workers entered your workshop code. Tap "Accept" to grant them access.',
      _ =>
        'قام هؤلاء العمال بإدخال كود ورشتك. اضغط على "قبول" لفتح حساباتهم وتفعيل صلاحياتهم فوراً.',
    };

    final acceptLabel = switch (lang) {
      AppLanguage.french => 'Accepter',
      AppLanguage.english => 'Accept',
      _ => 'قبول',
    };
    final rejectLabel = switch (lang) {
      AppLanguage.french => 'Refuser',
      AppLanguage.english => 'Reject',
      _ => 'رفض',
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFF059669),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      hint,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: isDark ? Colors.white70 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...pendingWorkers.map((worker) {
            final name = (worker['name'] ?? '').toString().trim();
            final email = (worker['email'] ?? '').toString().trim();
            final displayName = name.isNotEmpty && name != 'عامل جديد'
                ? name
                : email.split('@').first;

            return Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _rejectWorker(worker),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: Text(rejectLabel),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _approveWorker(worker),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text(
                          acceptLabel,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDeputy = _isDeputyManager;
    final appSettings = Provider.of<AppSettingsProvider>(context);
    final lang = appSettings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pendingWorkers = _workers.where((w) => _isWorkerPending(w)).toList(growable: false);
    final activeWorkers = _workers.where((w) => !_isWorkerPending(w)).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(
            'إدارة شؤون وأجور العمال',
            'Gestion du Personnel & Salaires',
            'Personnel & Payroll Management',
            lang,
          ),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: _fetchWorkersFromCloud,
            tooltip: _t('تحديث من السحابة'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── بطاقة طلبات الانضمام الجديدة إن وجدت ──
          if (pendingWorkers.isNotEmpty)
            _buildPendingRequestsCard(pendingWorkers, lang, isDark),

          if (_workers.isEmpty)
            Container(
              padding: EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).primaryColor,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr(
                        'لكي ينضم إليك أي عامل، اطلب منه تحميل التطبيق والتسجيل كعامل، ثم إدخال "كود الورشة" الخاص بك:\n$_joinCode',
                        'Pour qu\'un ouvrier vous rejoigne, demandez-lui de télécharger l\'application, de s\'inscrire comme ouvrier, puis de saisir votre "Code Atelier" :\n${_joinCode == 'جاري التحميل...' ? 'Chargement...' : _joinCode}',
                        'To have a worker join you, ask them to download the app, register as a worker, then enter your "Workshop Code":\n${_joinCode == 'جاري التحميل...' ? 'Loading...' : _joinCode}',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _workers.isEmpty
                ? Center(child: Text(_t('لا يوجد عمال مسجلين في ورشتك حالياً')))
                : activeWorkers.isEmpty && pendingWorkers.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        switch (lang) {
                          AppLanguage.french =>
                            'Tous les ouvriers sont actuellement en attente d\'approbation ci-dessus.',
                          AppLanguage.english =>
                            'All workers are currently pending approval above.',
                          _ =>
                            'جميع العمال الحاليين بانتظار قبولك في بطاقة الطلبات المعلقة أعلاه.',
                        },
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: activeWorkers.length,
                    itemBuilder: (context, index) {
                      final worker = activeWorkers[index];
                      return WorkerCard(
                        key: ValueKey(worker['uid']?.toString() ?? index),
                        worker: worker,
                        db: widget.db,
                        isDeputyManager: isDeputy,
                        onRefresh: _loadWorkers,
                        onDelete: () async {
                          bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(
                                'تأكيد الحذف',
                                style: TextStyle(color: Colors.red),
                              ),
                              content: const Text(
                                'هل أنت متأكد من أنك تريد طرد/حذف هذا العامل نهائياً من ورشتك؟ لن يتمكن من الدخول إلى التطبيق كعامل لديك بعد الآن.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(_t('إلغاء')),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    'حذف',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            // Disconnect from Firebase so they don't get fetched again
                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(worker['uid'])
                                  .delete();
                            } catch (e) {
                              debugPrint(
                                'Failed to delete worker from cloud: $e',
                              );
                            }
                            // Delete from local SQLite
                            await widget.db.deleteEmployee(worker['uid']);
                            _loadWorkers();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم حذف العامل بنجاح',
                                  style: TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class WorkerCard extends StatefulWidget {
  final Map<String, dynamic> worker;
  final SqlDatabase db;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  /// إذا كان true، فالمستخدم الحالي نائب مدير (صلاحية محدودة)
  final bool isDeputyManager;

  const WorkerCard({
    super.key,
    required this.worker,
    required this.db,
    required this.onDelete,
    required this.onRefresh,
    this.isDeputyManager = false,
  });

  @override
  _WorkerCardState createState() => _WorkerCardState();
}

class _WorkerCardState extends State<WorkerCard> {
  static const _fullManagerJobRole = 'نائب مدير (صلاحيات كاملة)';

  late Map<String, dynamic> perms;
  int _selectedCategoryIndex = 0;
  double _splitRatio = 0.35;
  bool _useSplitView = true;
  Future<void> _permissionSaveChain = Future<void>.value();

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRatio = prefs.getDouble('permissions_split_ratio');
    final savedMode = prefs.getBool('permissions_use_split_view');
    if (mounted) {
      setState(() {
        if (savedRatio != null) _splitRatio = savedRatio.clamp(0.20, 0.75);
        if (savedMode != null) _useSplitView = savedMode;
      });
    }
  }

  Future<void> _setUseSplitView(bool value) async {
    setState(() => _useSplitView = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_use_split_view', value);
  }



  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  String _localizedJobRole(String value, AppLanguage lang) {
    if (value.trim() == _fullManagerJobRole) {
      return _tr(
        'نائب مدير (صلاحيات كاملة)',
        'Directeur adjoint (droits complets)',
        'Deputy manager (full permissions)',
        lang,
      );
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    _initPerms();
    _loadPreferences();
  }

  @override
  void didUpdateWidget(WorkerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = oldWidget.worker['uid']?.toString();
    final newUid = widget.worker['uid']?.toString();
    // Parent refreshes rebuild the employee maps even for the same worker.
    // Re-reading permissions here used to replace the just-toggled local
    // state with the previous cloud snapshot, making every switch jump back.
    // A card is keyed by uid, so only initialise again for a different worker.
    if (oldUid != newUid) {
      _initPerms();
    }
  }

  void _initPerms() {
    perms = {};
    try {
      final rawPermissions = widget.worker['permissions_json'];
      if (rawPermissions is String && rawPermissions.isNotEmpty) {
        final decoded = jsonDecode(rawPermissions);
        if (decoded is Map) {
          perms = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (e) {
      perms = {};
    }
    if (perms.isEmpty && widget.worker['permissions'] is Map) {
      perms = Map<String, dynamic>.from(widget.worker['permissions'] as Map);
    }
    final defaults = {
      'view_clients': false,
      'view_client_ledger': false,
      'create_clients': false,
      'edit_clients': false,
      'delete_clients': false,
      'view_orders': false,
      'view_projects': false,
      'distribution_tracking': false,
      'sales': false,
      'inventory': false,
      'inventory_adjustment': false,
      'global_consumption': false,
      'worker_finances': false,
      'worker_settlement': false,
      'create_orders': false,
      'edit_orders': false,
      'change_order_dates': false,
      'delete_orders': false,
      'access_trash': false,
      'view_client_details': false,
      'view_order_details': false,
      'view_order_documents': false,
      'fiche_de_coupe': false,
      'view_order_materials': false,
      'confirm_measurements': false,
      'measurements_card': false,
      'change_order_status': false,
      'pass_to_next_stage': false,
      'duplicate_orders': false,
      'view_my_tasks': false,
      'view_all_worker_tasks': false,
      'view_all_tasks': false,
      'view_my_accreditations': false,
      'view_profiles': false,
      'view_glass': false,
      'view_shutters': false,
      'view_colors': false,
      'view_accessories': false,
      'view_series_requirements_report': false,
      'view_joints': false,
      'view_kit_bundles': false,
      'external_operations': false,
      'order_allocation': false,
      'settings': false,
      'view_subscription': false,
      'select_systems': false,
      'change_prices': false,
      'view_cost_price': false,
      'change_transaction_dates': false,
      'change_payment_dates': false,
      'treasury': false,
      'manage_workers': false,
      'edit_worker': false,
      'delete_worker': false,
      'purchases': false,
      'add_purchases': false,
      'edit_purchases': false,
      'change_purchase_dates': false,
      'delete_purchases': false,
      'edit_payments': false,
      'delete_payments': false,
      'manage_caisses': false,
      'add_caisses': false,
      'add_warehouses': false,
      'statistics': false,
      'accelerate_confirmed_invoices': false,
      'isBlocked': false,
      'view_suppliers': false,
      'cloud_backup': false,
      'sync_global_catalog': false,
      'local_json_backup': false,
      'full_manager_permissions': false,
      'co_manager': false,
      'access_workshop': true,
      'access_store': true,
      'access_management': false,
      'workshop_purchases': true,
      'store_purchases': true,
      'store_sales': true,
      'view_store_sales': true,
      'create_store_sales': false,
      'edit_store_sales': false,
      'confirm_store_sales': false,
      'delete_store_sales': false,
      'register_store_payments': false,
      'return_store_sales': false,
      'view_document_history': false,
      'restore_deleted_documents': false,
      'close_business_day': false,
      'internal_sales': true,
    };
    // A full co-manager already has every permission in the app. A key added
    // to the application after that grant must not show up as disabled.
    final fullManager = _hasFullManagerPermissions;
    defaults.forEach((key, value) {
      if (perms.containsKey(key)) return;
      perms[key] = fullManager && key != 'isBlocked' ? true : value;
    });
  }

  bool _isPermissionEnabled(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  bool get _hasFullManagerPermissions =>
      _isPermissionEnabled(perms['full_manager_permissions']) ||
      _isPermissionEnabled(perms['co_manager']);

  String _roleForPermissions(Map<String, dynamic> permissions) {
    return _isPermissionEnabled(permissions['full_manager_permissions']) ||
            _isPermissionEnabled(permissions['co_manager'])
        ? 'co_manager'
        : 'worker';
  }

  Future<bool> _syncSupabaseWorkerPermissions(
    Map<String, dynamic> permissions, {
    String? role,
  }) async {
    final email = widget.worker['email']?.toString().trim() ?? '';
    if (email.isEmpty) return false;

    try {
      await SupabaseWorkshopSyncService().updateMemberPermissionsByEmail(
        email: email,
        role: role ?? _roleForPermissions(permissions),
        permissions: permissions,
      );
      return true;
    } catch (error) {
      debugPrint('Supabase worker permissions sync failed: $error');
      return false;
    }
  }

  void _cachePermissionsOnWorker(Map<String, dynamic> updatedPerms) {
    // Keep the model handed to this card in sync with its state. Otherwise a
    // parent rebuild can call didUpdateWidget with the old JSON and visually
    // undo a switch that was already saved in SQLite.
    widget.worker['permissions'] = Map<String, dynamic>.from(updatedPerms);
    widget.worker['permissions_json'] = jsonEncode(updatedPerms);
  }

  Future<void> _persistPermissionsInOrder(
    Map<String, dynamic> updatedPerms, {
    String? role,
  }) {
    final snapshot = Map<String, dynamic>.from(updatedPerms);
    final operation = _permissionSaveChain.then((_) async {
      final workerUid = widget.worker['uid']?.toString() ?? '';
      if (workerUid.isEmpty) return;
      final isFirebaseWorker =
          !workerUid.startsWith('supabase_') &&
          !workerUid.startsWith('pending_supabase_');
      final prefs = await SharedPreferences.getInstance();
      final workshopId = prefs.getString('workshop_code') ?? '';

      final changedRows = await widget.db.updateEmployeePermissions(
        workerUid,
        jsonEncode(snapshot),
      );
      if (changedRows == 0) {
        throw StateError('لم يتم العثور على العامل محلياً: $workerUid');
      }

      var firebaseSaved = false;
      if (isFirebaseWorker) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(workerUid).set({
            'role': role ?? _roleForPermissions(snapshot),
            'isBlocked': snapshot['isBlocked'] ?? false,
            'permissions': snapshot,
            'permissions_json': jsonEncode(snapshot),
            'permissions_updated_at': FieldValue.serverTimestamp(),
            if (workshopId.isNotEmpty) 'workshopId': workshopId,
          }, SetOptions(merge: true));
          firebaseSaved = true;
        } catch (error) {
          debugPrint('Firebase permission sync failed: $error');
        }
      }

      final supabaseSaved = await _syncSupabaseWorkerPermissions(
        snapshot,
        role: role,
      );
      // Employees is also a synchronized workshop table. Upload it now so
      // another desktop/phone receives the same JSON even before reopening.
      try {
        await CloudSyncService().notifyChangeImmediate();
      } catch (error) {
        debugPrint('Immediate employee permission upload failed: $error');
      }

      if (!firebaseSaved && !supabaseSaved) {
        throw StateError('تعذر رفع الصلاحيات إلى حساب المستخدم');
      }
    });
    _permissionSaveChain = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Queued permission save failed: $error');
      },
    );
    return operation;
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  DateTime? _parsePermissionDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _inventoryAdjustmentWindowLabel(AppLanguage lang) {
    if (!_isPermissionEnabled(perms['inventory_adjustment'])) {
      return _tr('غير مفعلة', 'Non activée', 'Disabled', lang);
    }
    final from = _parsePermissionDate(perms['inventory_adjustment_valid_from']);
    final to = _parsePermissionDate(perms['inventory_adjustment_valid_to']);
    if (from == null && to == null) {
      return _tr(
        'مفعلة بدون مدة محددة',
        'Activée sans période définie',
        'Enabled without a defined period',
        lang,
      );
    }
    final fromText = from == null ? '...' : _dateOnly(from);
    final toText = to == null ? '...' : _dateOnly(to);
    return '${_tr('صالحة من', 'Valable du', 'Valid from', lang)} $fromText '
        '${_tr('إلى', 'au', 'to', lang)} $toText';
  }

  bool _inventoryAdjustmentMatchesDays(int days) {
    if (!_isPermissionEnabled(perms['inventory_adjustment'])) return false;
    final from = _parsePermissionDate(perms['inventory_adjustment_valid_from']);
    final to = _parsePermissionDate(perms['inventory_adjustment_valid_to']);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return from == today && to == today.add(Duration(days: days - 1));
  }

  Future<void> _saveInventoryAdjustmentPermission(
    Map<String, dynamic> updatedPerms,
  ) async {
    setState(() {
      perms = updatedPerms;
    });
    _cachePermissionsOnWorker(updatedPerms);
    try {
      await _persistPermissionsInOrder(updatedPerms);
    } catch (e) {
      debugPrint('Cloud sync failed for inventory adjustment (local saved): $e');
    }
  }

  Future<void> _setInventoryAdjustmentPreset(int days) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: days - 1));
    final updatedPerms = Map<String, dynamic>.from(perms)
      ..['inventory_adjustment'] = true
      ..['inventory_adjustment_valid_from'] = _dateOnly(start)
      ..['inventory_adjustment_valid_to'] = _dateOnly(end);
    await _saveInventoryAdjustmentPermission(updatedPerms);
  }

  Future<void> _disableInventoryAdjustment() async {
    final updatedPerms = Map<String, dynamic>.from(perms)
      ..['inventory_adjustment'] = false
      ..remove('inventory_adjustment_valid_from')
      ..remove('inventory_adjustment_valid_to');
    await _saveInventoryAdjustmentPermission(updatedPerms);
  }

  Future<void> _pickInventoryAdjustmentRange(AppLanguage lang) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentStart =
        _parsePermissionDate(perms['inventory_adjustment_valid_from']) ?? today;
    final currentEnd =
        _parsePermissionDate(perms['inventory_adjustment_valid_to']) ??
        today.add(const Duration(days: 6));
    final range = await showDateRangePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today.add(const Duration(days: 730)),
      initialDateRange: DateTimeRange(start: currentStart, end: currentEnd),
      helpText: _tr(
        'مدة صلاحية الجرد السنوي',
        'Période de validité de l’inventaire',
        'Inventory adjustment permission period',
        lang,
      ),
      cancelText: _tr('إلغاء', 'Annuler', 'Cancel', lang),
      confirmText: _tr('اعتماد', 'Valider', 'Apply', lang),
    );
    if (range == null) return;
    final updatedPerms = Map<String, dynamic>.from(perms)
      ..['inventory_adjustment'] = true
      ..['inventory_adjustment_valid_from'] = _dateOnly(range.start)
      ..['inventory_adjustment_valid_to'] = _dateOnly(range.end);
    await _saveInventoryAdjustmentPermission(updatedPerms);
  }

  Future<void> _updatePermission(String key, bool val) async {
    final updatedPerms = Map<String, dynamic>.from(perms)..[key] = val;

    // A co-manager can be converted to a limited manager by turning off an
    // individual permission.  Keep their other selected permissions, but
    // remove the bypass that previously granted every page on Windows.
    if (!val &&
        key != 'full_manager_permissions' &&
        key != 'co_manager' &&
        _hasFullManagerPermissions) {
      updatedPerms['full_manager_permissions'] = false;
      updatedPerms['co_manager'] = false;
    }

    setState(() {
      perms = updatedPerms;
    });
    _cachePermissionsOnWorker(updatedPerms);
    try {
      await _persistPermissionsInOrder(updatedPerms);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحفظ محلياً، لكن تعذرت مزامنة الصلاحية: $error'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
  }

  Future<void> _updatePermissionGroup(
    Iterable<String> keys,
    Iterable<String> enabledKeys,
  ) async {
    final enabled = enabledKeys.toSet();
    final updatedPerms = Map<String, dynamic>.from(perms);
    for (final key in keys) {
      updatedPerms[key] = enabled.contains(key);
    }
    if (updatedPerms['inventory_adjustment'] == true) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      updatedPerms['inventory_adjustment_valid_from'] ??= _dateOnly(start);
      updatedPerms['inventory_adjustment_valid_to'] ??= _dateOnly(
        start.add(const Duration(days: 6)),
      );
    } else {
      updatedPerms.remove('inventory_adjustment_valid_from');
      updatedPerms.remove('inventory_adjustment_valid_to');
    }

    if (_hasFullManagerPermissions) {
      updatedPerms['full_manager_permissions'] = false;
      updatedPerms['co_manager'] = false;
    }

    setState(() {
      perms = updatedPerms;
    });
    _cachePermissionsOnWorker(updatedPerms);

    try {
      await _persistPermissionsInOrder(updatedPerms);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحفظ محلياً، لكن تعذرت مزامنة المجموعة: $error'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
  }

  bool _groupHasExactly(Iterable<String> keys, Iterable<String> enabledKeys) {
    final enabled = enabledKeys.toSet();
    for (final key in keys) {
      if (_isPermissionEnabled(perms[key]) != enabled.contains(key)) {
        return false;
      }
    }
    return true;
  }

  Widget _buildPermissionGroupActions({
    required AppLanguage lang,
    required Iterable<String> allKeys,
    required Iterable<String> viewOnlyKeys,
  }) {
    final keys = allKeys.toList(growable: false);
    final viewKeys = viewOnlyKeys.toList(growable: false);
    final allSelected = _groupHasExactly(keys, keys);
    final viewOnlySelected = _groupHasExactly(keys, viewKeys);
    final noneSelected = _groupHasExactly(keys, const <String>[]);

    Widget actionChip({
      required IconData icon,
      required String label,
      required bool selected,
      required Color color,
      required VoidCallback onTap,
    }) {
      return FilterChip(
        avatar: Icon(icon, size: 16, color: selected ? Colors.white : color),
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : color,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: color,
        backgroundColor: color.withValues(alpha: 0.09),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        onSelected: (_) => onTap(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            actionChip(
              icon: Icons.visibility_outlined,
              label: _tr('رؤية فقط', 'Lecture seule', 'View only', lang),
              selected: viewOnlySelected,
              color: const Color(0xFF2563EB),
              onTap: () => _updatePermissionGroup(keys, viewKeys),
            ),
            actionChip(
              icon: Icons.done_all_rounded,
              label: _tr(
                'كل الصلاحيات',
                'Toutes les permissions',
                'Full access',
                lang,
              ),
              selected: allSelected,
              color: const Color(0xFF059669),
              onTap: () => _updatePermissionGroup(keys, keys),
            ),
            actionChip(
              icon: Icons.block_rounded,
              label: _tr('إلغاء الكل', 'Tout désactiver', 'Disable all', lang),
              selected: noneSelected,
              color: const Color(0xFFDC2626),
              onTap: () => _updatePermissionGroup(keys, const <String>[]),
            ),
          ],
        ),
      ),
    );
  }

  /// 👑 منح أو إلغاء صلاحيات كمدير بالكامل لهذا الشخص
  Future<void> _toggleFullManagerPermissions(bool grant) async {
    final Map<String, dynamic> updatedPerms = Map<String, dynamic>.from(perms);

    updatedPerms['full_manager_permissions'] = grant;
    updatedPerms['co_manager'] = grant;

    if (grant) {
      updatedPerms.forEach((k, v) {
        if (k != 'isBlocked' &&
            !k.endsWith('_valid_from') &&
            !k.endsWith('_valid_to')) {
          updatedPerms[k] = true;
        }
      });
      updatedPerms.remove('inventory_adjustment_valid_from');
      updatedPerms.remove('inventory_adjustment_valid_to');
    } else {
      // A demoted co-manager must not retain the individual permissions that
      // were enabled when full access was granted.
      updatedPerms.updateAll(
        (key, value) =>
            key == 'isBlocked' ||
                key.endsWith('_valid_from') ||
                key.endsWith('_valid_to')
            ? value
            : false,
      );
      updatedPerms.remove('inventory_adjustment_valid_from');
      updatedPerms.remove('inventory_adjustment_valid_to');
    }

    setState(() {
      perms = updatedPerms;
    });
    _cachePermissionsOnWorker(updatedPerms);

    final uid = widget.worker['uid'].toString();
    final isFirebaseWorker =
        !uid.startsWith('supabase_') && !uid.startsWith('pending_supabase_');
    final currentJobRole = widget.worker['job_role']?.toString().trim() ?? '';
    final nextJobRole = grant
        ? _fullManagerJobRole
        : (currentJobRole == _fullManagerJobRole ? '' : currentJobRole);

    try {
      await widget.db.updateEmployeeFullInfo(
        uid,
        name: widget.worker['name']?.toString() ?? '',
        email: widget.worker['email']?.toString() ?? '',
        phone: widget.worker['phone']?.toString() ?? '',
        address: widget.worker['address']?.toString() ?? '',
        jobRole: nextJobRole,
      );
    } catch (e) {
      debugPrint('Error updating local co-manager records: $e');
    }

    var cloudSaved = false;
    try {
      await _persistPermissionsInOrder(
        updatedPerms,
        role: grant ? 'co_manager' : 'worker',
      );
      cloudSaved = true;
      if (isFirebaseWorker) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'job_role': nextJobRole,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Cloud sync failed for co-manager (local saved): $e');
    }

    // A Supabase refresh replaces the local row with the server row. Do not
    // refresh after a failed upload, because that immediately restores the
    // old permissions and makes the switch appear unable to stay enabled.
    if (cloudSaved) widget.onRefresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            grant
                ? '✅ تم إعطاء مهام وصلاحيات المدير بالكامل لهذا الشخص 👑'
                : 'ℹ️ تم إلغاء صلاحيات المدير وإعادة الحساب كعامل عادي',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: grant ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  /// ─── حوار تعديل بيانات العامل ────────────────────────────────────────────
  Future<void> _showEditDialog() async {
    final nameCtrl = TextEditingController(text: widget.worker['name'] ?? '');
    final emailCtrl = TextEditingController(text: widget.worker['email'] ?? '');
    final phoneCtrl = TextEditingController(text: widget.worker['phone'] ?? '');
    final roleCtrl = TextEditingController(
      text: widget.worker['job_role'] ?? '',
    );
    final addressCtrl = TextEditingController(
      text: widget.worker['address'] ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF2563EB),
              radius: 18,
              child: Icon(Icons.edit, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              _t('تعديل بيانات العامل'),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الاسم
                TextFormField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: _t('الاسم الكامل'),
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 12),
                // البريد الإلكتروني
                TextFormField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: _t('البريد الإلكتروني'),
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                // رقم الهاتف
                TextFormField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: _t('رقم الهاتف (واتساب)'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: _t('0555 123 456 أو +213555123456'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                // المنصب
                TextFormField(
                  controller: roleCtrl,
                  decoration: InputDecoration(
                    labelText: _t('المنصب / الدور'),
                    prefixIcon: const Icon(Icons.work_outline),
                    hintText: _t('مثال: نجار، مركّب، مندوب...'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 12),
                // العنوان
                TextFormField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: _t('العنوان'),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _t('إلغاء'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(_t('حفظ'), style: const TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final uid = widget.worker['uid'].toString();
      final name = nameCtrl.text.trim();
      final email = emailCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      final address = addressCtrl.text.trim();
      final jobRole = roleCtrl.text.trim();

      await widget.db.updateEmployeeFullInfo(
        uid,
        name: name,
        email: email,
        phone: phone,
        address: address,
        jobRole: jobRole,
      );

      // Update Firestore immediately to prevent revert on sync
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
          'job_role': jobRole,
        });
      } catch (e) {
        debugPrint('Error updating worker in Firestore: $e');
      }

      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ تم تحديث بيانات العامل',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  int _activeCountForCategory(List<String> keys) {
    int count = 0;
    for (final k in keys) {
      if (perms[k] == true) count++;
    }
    return count;
  }

  List<Map<String, dynamic>> _getCategoriesMetadata(AppLanguage lang) {
    return [
      {
        'index': 0,
        'title': _tr('صلاحيات الزبائن (Clients)', 'Permissions Clients', 'Client Permissions', lang),
        'icon': Icons.people_alt_rounded,
        'color': const Color(0xFF7C3AED),
        'keys': const [
          'view_clients',
          'view_client_ledger',
          'create_clients',
          'edit_clients',
          'delete_clients',
          'view_client_details',
        ],
      },
      {
        'index': 1,
        'title': _tr('صلاحيات الطلبيات والمشاريع (Commandes & Projets)', 'Commandes & Projets', 'Orders & Projects', lang),
        'icon': Icons.receipt_long_rounded,
        'color': const Color(0xFF2563EB),
        'keys': const [
          'view_orders',
          'view_projects',
          'distribution_tracking',
          'sales',
          'create_orders',
          'edit_orders',
          'change_order_dates',
          'delete_orders',
          'access_trash',
          'view_order_details',
          'view_order_documents',
          'fiche_de_coupe',
          'view_order_materials',
          'change_order_status',
          'pass_to_next_stage',
          'duplicate_orders',
          'order_allocation',
          'view_all_worker_tasks',
        ],
      },
      {
        'index': 2,
        'title': _tr('رفع القياسات الذكية (الموقع)', 'Prise de Mesures (Site)', 'Smart Site Measurements', lang),
        'icon': Icons.architecture_rounded,
        'color': const Color(0xFF0EA5E9),
        'keys': const [
          'measurements_card',
          'confirm_measurements',
        ],
      },
      {
        'index': 3,
        'title': _tr('مهامي وتصنيع اعتماداتي والكتالوج', 'Mes Tâches & Catalogue', 'My Tasks & Catalogue', lang),
        'icon': Icons.assignment_turned_in_rounded,
        'color': const Color(0xFF14B8A6),
        'keys': const [
          'view_my_tasks',
          'view_my_accreditations',
          'view_profiles',
          'view_glass',
          'view_shutters',
          'view_colors',
          'view_accessories',
          'view_series_requirements_report',
          'view_joints',
          'view_kit_bundles',
          'external_operations',
        ],
      },
      {
        'index': 4,
        'title': _tr('إدارة صلاحيات الفريق (نائب المدير)', 'Gestion d\'Équipe (Co-Directeur)', 'Team Management (Co-Manager)', lang),
        'icon': Icons.admin_panel_settings_rounded,
        'color': const Color(0xFFD97706),
        'keys': const [
          'manage_workers',
          'edit_worker',
          'delete_worker',
          'cloud_backup',
          'local_json_backup',
        ],
      },
      {
        'index': 5,
        'title': _tr('الإعدادات وأنظمة الورشة (Paramètres & Systèmes)', 'Paramètres & Systèmes', 'Settings & Systems', lang),
        'icon': Icons.settings_rounded,
        'color': const Color(0xFF64748B),
        'keys': const [
          'settings',
          'view_subscription',
          'select_systems',
        ],
      },
      {
        'index': 6,
        'title': _tr('المالية والصناديق والأسعار والأجور (Trésorerie & Paie)', 'Trésorerie, Prix & Paie', 'Financials & Wages', lang),
        'icon': Icons.account_balance_wallet_rounded,
        'color': const Color(0xFF059669),
        'keys': const [
          'change_prices',
          'view_cost_price',
          'change_payment_dates',
          'treasury',
          'manage_caisses',
          'add_caisses',
          'edit_payments',
          'delete_payments',
          'worker_finances',
          'worker_settlement',
        ],
      },
      {
        'index': 7,
        'title': _tr('المخزون والمشتريات والموردين (Stock, Achats & Fournisseurs)', 'Stock, Achats & Fournisseurs', 'Stock & Suppliers', lang),
        'icon': Icons.local_shipping_rounded,
        'color': const Color(0xFFE11D48),
        'keys': const [
          'inventory',
          'inventory_adjustment',
          'add_warehouses',
          'view_suppliers',
          'purchases',
          'add_purchases',
          'edit_purchases',
          'change_purchase_dates',
          'delete_purchases',
          'global_consumption',
        ],
      },
      {
        'index': 8,
        'title': _tr('الإحصائيات والتقارير (Statistiques & Rapports)', 'Statistiques & Rapports', 'Statistics & Reports', lang),
        'icon': Icons.bar_chart_rounded,
        'color': const Color(0xFF06B6D4),
        'keys': const [
          'statistics',
          'accelerate_confirmed_invoices',
        ],
      },
      {
        'index': 9,
        'title': _tr('محل بيع المواد وفصل الأنشطة (Magasin & Portée)', 'Magasin & Portée d\'activité', 'Materials Store & Scope', lang),
        'icon': Icons.storefront_rounded,
        'color': const Color(0xFFEA580C),
        'keys': const [
          'access_workshop',
          'access_store',
          'access_management',
          'store_sales',
          'store_purchases',
          'workshop_purchases',
          'internal_sales',
        ],
      },
    ];
  }

  Widget _buildSplitView(
    BuildContext context,
    AppLanguage lang,
    bool isDark,
    TextStyle titleStyle,
    List<Map<String, dynamic>> categories,
    List<Widget> categoryWidgets,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final minLeft = 240.0;
        final maxLeft = (totalW - 280.0).clamp(minLeft, totalW);
        final leftW = (_splitRatio * totalW).clamp(minLeft, maxLeft);

        final safeIndex = _selectedCategoryIndex.clamp(0, categories.length - 1);
        final currentCat = categories[safeIndex];
        final currentCatColor = currentCat['color'] as Color;

        return Container(
          height: 650,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── الجانب الأول: العنوان (Titles / Categories) ──
              SizedBox(
                width: leftW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(11),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.category_rounded,
                            size: 18,
                            color: isDark ? Colors.blue.shade300 : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _tr('أقسام الصلاحيات (عنوان)', 'Catégories (Titre)', 'Permission Categories (Title)', lang),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        itemCount: categories.length,
                        itemBuilder: (context, i) {
                          final cat = categories[i];
                          final isSelected = safeIndex == i;
                          final catColor = cat['color'] as Color;
                          final keys = cat['keys'] as List<String>;
                          final activeCount = _activeCountForCategory(keys);
                          final totalCount = keys.length;

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              if (_selectedCategoryIndex != i) {
                                setState(() => _selectedCategoryIndex = i);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? catColor.withValues(alpha: isDark ? 0.25 : 0.12)
                                    : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? catColor
                                      : (isDark ? const Color(0xFF334155) : Colors.grey.shade200),
                                  width: isSelected ? 1.8 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: catColor.withValues(alpha: 0.15),
                                    radius: 15,
                                    child: Icon(cat['icon'] as IconData, color: catColor, size: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      cat['title'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        color: isSelected
                                            ? (isDark ? Colors.white : catColor)
                                            : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: activeCount > 0
                                          ? (activeCount == totalCount ? Colors.green : catColor).withValues(alpha: 0.15)
                                          : (isDark ? Colors.white10 : Colors.grey.shade100),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$activeCount/$totalCount',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: activeCount > 0
                                            ? (activeCount == totalCount ? Colors.green : catColor)
                                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── الفاصل القابل للتحريك يميناً وشمالاً ──
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final isRtl = Directionality.of(context) == TextDirection.rtl;
                  final delta = isRtl ? -details.delta.dx : details.delta.dx;
                  setState(() {
                    final newPx = (leftW + delta).clamp(minLeft, maxLeft);
                    _splitRatio = (newPx / totalW).clamp(0.20, 0.75);
                  });
                },
                onHorizontalDragEnd: (_) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setDouble('permissions_split_ratio', _splitRatio);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: 12,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      border: Border.symmetric(
                        vertical: BorderSide(
                          color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white38 : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              // ── الجانب الثاني: العرض (Display / Content) ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(11),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: currentCatColor.withValues(alpha: 0.15),
                            radius: 16,
                            child: Icon(
                              currentCat['icon'] as IconData,
                              color: currentCatColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              currentCat['title'] as String,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: currentCatColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_activeCountForCategory(currentCat['keys'] as List<String>)} / ${(currentCat['keys'] as List<String>).length}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: currentCatColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: categoryWidgets[safeIndex],
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

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final phone = widget.worker['phone']?.toString() ?? '';
    final role = widget.worker['job_role']?.toString() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final blueDivider = Divider(
      height: 1,
      color: isDark
          ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
          : const Color(0xFF2563EB).withValues(alpha: 0.3),
    );

    final titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontFamily: 'Cairo',
      color: isDark ? Colors.white : Colors.black87,
    );

    final switchTitleStyle = TextStyle(
      fontFamily: 'Cairo',
      color: isDark ? Colors.white : Colors.black87,
    );

    final switchSubTitleStyle = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 11,
      color: isDark ? Colors.white70 : Colors.black54,
    );

    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          // ── رأس البطاقة ──────────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // أيقونة العامل
                  GestureDetector(
                    onLongPress: _showEditDialog,
                    child: CircleAvatar(
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : Colors.blueGrey,
                      radius: 22,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // اسم + بريد + هاتف + منصب
                  Expanded(
                    child: GestureDetector(
                      onLongPress: _showEditDialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.worker['name'] ??
                                _tr('بدون اسم', 'Sans nom', 'No name', lang),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          if (role.isNotEmpty)
                            Text(
                              '${_tr("المنصب:", "Poste:", "Role:", lang)} ${_localizedJobRole(role, lang)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // ── زر تعديل بيانات العامل ────────────────────────
                  if (!widget.isDeputyManager ||
                      (perms['edit_worker'] ?? false))
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      tooltip: _tr(
                        'تعديل بيانات العامل',
                        'Modifier l\'ouvrier',
                        'Edit worker data',
                        lang,
                      ),
                      onPressed: _showEditDialog,
                    ),
                  // ── زر طي / سدل القائمة ────────────────────────────
                  IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  // ── زر الحذف ───────────────────────────────────────
                  if (!widget.isDeputyManager ||
                      (perms['delete_worker'] ?? false))
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
            ),
          ),
          // ── قسم الصلاحيات (قابل للإخفاء) ───────────────────────
          if (_expanded) ...[
            blueDivider,

            // 👑 بطاقة زر "إعطاء مهام نفس مهام المدير"
            Builder(
              builder: (ctx) {
                final bool isFullManager = _hasFullManagerPermissions;
                return Container(
                  margin: const EdgeInsets.all(10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFullManager
                          ? [const Color(0xFF059669), const Color(0xFF10B981)]
                          : [const Color(0xFFD97706), const Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (isFullManager ? Colors.green : Colors.amber)
                            .withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            isFullManager
                                ? Icons.workspace_premium_rounded
                                : Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isFullManager
                                      ? _tr(
                                          'تم منح مهام نفس مهام المدير 👑',
                                          'Permissions de Directeur Accordées 👑',
                                          'Full Manager Permissions Granted 👑',
                                          lang,
                                        )
                                      : _tr(
                                          'إعطاء مهام نفس مهام المدير 👑',
                                          'Accorder les permissions de directeur 👑',
                                          'Grant Full Manager Permissions 👑',
                                          lang,
                                        ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isFullManager
                                      ? _tr(
                                          'هذا الشخص يستطيع الوصول لأي شيء في التطبيق مثله مثل المدير (بما فيها إضافة البروفايلات والسلاسل والمقاطع)',
                                          'Cet utilisateur a accès à toutes les fonctionnalités de l\'application comme le directeur',
                                          'This user has full access to all app features like the manager',
                                          lang,
                                        )
                                      : _tr(
                                          'اضغط هنا لتمكين الوصول الشامل لأي شيء في التطبيق مثله مثل المدير (حتى إضافة البروفايلات والسلاسل والمقاطع)',
                                          'Appuyez pour accorder l\'accès complet à toutes les fonctionnalités comme le directeur',
                                          'Tap here to grant full access to all app features like the manager',
                                          lang,
                                        ),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 11,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(
                            isFullManager
                                ? Icons.lock_reset_rounded
                                : Icons.verified_user_rounded,
                            color: isFullManager
                                ? Colors.red.shade700
                                : const Color(0xFFD97706),
                          ),
                          label: Text(
                            isFullManager
                                ? _tr(
                                    'إلغاء صلاحيات المدير (إعادة كعامل عادي)',
                                    'Révoquer l\'accès de directeur',
                                    'Revoke Manager Access',
                                    lang,
                                  )
                                : _tr(
                                    'إعطاء مهام نفس مهام المدير 👑',
                                    'Accorder les accès de directeur 👑',
                                    'Grant Manager Access 👑',
                                    lang,
                                  ),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isFullManager
                                  ? Colors.red.shade700
                                  : const Color(0xFF78350F),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: isFullManager
                                ? Colors.red.shade700
                                : const Color(0xFF78350F),
                            elevation: 3,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () =>
                              _toggleFullManagerPermissions(!isFullManager),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            blueDivider,

            Container(
              color: isDark ? Colors.red.withValues(alpha: 0.15) : Colors.red.shade50,
              child: SwitchListTile(
                title: Text(
                  _tr(
                    'حظر العامل من التطبيق نهائياً',
                    'Bloquer l\'accès de l\'ouvrier',
                    'Block worker from app',
                    lang,
                  ),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                value: perms['isBlocked'] ?? false,
                activeThumbColor: Colors.red,
                onChanged: (val) => _updatePermission('isBlocked', val),
              ),
            ),
            blueDivider,

            Builder(
              builder: (ctx) {
                final categories = _getCategoriesMetadata(lang);

                // 1️⃣ تصنيف صلاحيات الزبائن
                final cat0Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'view_clients',
                    'view_client_ledger',
                    'create_clients',
                    'edit_clients',
                    'delete_clients',
                    'view_client_details',
                  ],
                  viewOnlyKeys: const [
                    'view_clients',
                    'view_client_ledger',
                    'view_client_details',
                  ],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية قائمة الزبائن',
                      'Voir la liste des clients',
                      'View clients list',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_clients'] ?? false,
                  onChanged: (val) => _updatePermission('view_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية كشف حساب الزبائن التفصيلي (Chrono)',
                      'Voir le relevé de compte (Chrono)',
                      'View detailed client ledger',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_client_ledger'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_client_ledger', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إنشاء زبون جديد',
                      'Créer un nouveau client',
                      'Create new client',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['create_clients'] ?? false,
                  onChanged: (val) => _updatePermission('create_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل بيانات الزبائن',
                      'Modifier les données des clients',
                      'Edit clients data',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_clients'] ?? false,
                  onChanged: (val) => _updatePermission('edit_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مسح / حذف الزبائن',
                      'Supprimer les clients',
                      'Delete clients',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['delete_clients'] ?? false,
                  onChanged: (val) => _updatePermission('delete_clients', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية تفاصيل الزبون',
                      'Voir les détails du client',
                      'View client details',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_client_details'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_client_details', val),
                ),
              ],
            );
                // 2️⃣ تصنيف صلاحيات الطلبيات والمشاريع
                final cat1Content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'view_orders',
                    'view_projects',
                    'distribution_tracking',
                    'sales',
                    'create_orders',
                    'edit_orders',
                    'change_order_dates',
                    'delete_orders',
                    'access_trash',
                    'view_order_details',
                    'view_order_documents',
                    'fiche_de_coupe',
                    'view_order_materials',
                    'change_order_status',
                    'pass_to_next_stage',
                    'duplicate_orders',
                    'order_allocation',
                    'view_all_worker_tasks',
                  ],
                  viewOnlyKeys: const [
                    'view_orders',
                    'view_projects',
                    'sales',
                    'view_order_details',
                    'view_order_documents',
                    'fiche_de_coupe',
                    'view_order_materials',
                  ],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية قائمة الطلبيات',
                      'Voir la liste des commandes',
                      'View orders list',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_orders'] ?? false,
                  onChanged: (val) => _updatePermission('view_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية قائمة المشاريع (Projets)',
                      'Voir les projets',
                      'View projects list',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_projects'] ?? false,
                  onChanged: (val) => _updatePermission('view_projects', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'خطط التوزيع والتتبع',
                      'Suivi de distribution',
                      'Distribution tracking',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['distribution_tracking'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('distribution_tracking', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية سجل المبيعات (Vente)',
                      'Historique des ventes',
                      'Sales history',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['sales'] ?? false,
                  onChanged: (val) => _updatePermission('sales', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إنشاء طلبيات جديدة',
                      'Créer de nouvelles commandes',
                      'Create new orders',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['create_orders'] ?? false,
                  onChanged: (val) => _updatePermission('create_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل الطلبيات',
                      'Modifier les commandes',
                      'Edit orders',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_orders'] ?? false,
                  onChanged: (val) => _updatePermission('edit_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير تاريخ الطلبيات والفواتير التابعة لها',
                      'Modifier la date des commandes et de leurs factures',
                      'Change order and related invoice dates',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح بتغيير تاريخ الطلبية وتاريخ التسعيرة/الفاتورة المرتبط بها',
                      'Autoriser la modification des dates de commande et de devis',
                      'Allows changing order, quote, and related invoice dates',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['change_order_dates'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('change_order_dates', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'حذف الطلبيات',
                      'Supprimer les commandes',
                      'Delete orders',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'خطير: يسمح للعامل بحذف الطلبيات',
                      'Attention: Autorise la suppression de commandes',
                      'Warning: Allows worker to delete orders',
                      lang,
                    ),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  value: perms['delete_orders'] ?? false,
                  onChanged: (val) => _updatePermission('delete_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الوصول لسلة المحذوفات والرقابة',
                      'Accès à la corbeille & audit',
                      'Access trash & audit logs',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'حساس: يسمح للعامل بفتح سلة المحذوفات ورؤية السجلات المحذوفة واسترجاعها',
                      'Sensible: Permet à l\'ouvrier d\'accéder à la corbeille et de restaurer des éléments',
                      'Sensitive: Allows worker to view trash and restore deleted items',
                      lang,
                    ),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  value: perms['access_trash'] ?? false,
                  onChanged: (val) => _updatePermission('access_trash', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية تفاصيل الطلبية وخياراتها',
                      'Voir les détails de la commande',
                      'View order details',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_order_details'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_order_details', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية وطباعة وثائق الطلبية (الفواتير، Devis...)',
                      'Documents de commande (Devis, Fiche)',
                      'View & print order documents & devis',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_order_documents'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_order_documents', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'استخراج ورقة التقطيع (Fiche de Coupe)',
                      'Fiche de coupe',
                      'Extract cutting sheet (Fiche de Coupe)',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['fiche_de_coupe'] ?? false,
                  onChanged: (val) => _updatePermission('fiche_de_coupe', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية سلع ومواد الطلبية وتقارير النواقص',
                      'Matériaux & Manquants',
                      'View order materials & missing items',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_order_materials'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_order_materials', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير حالة الطلبية (يدوياً)',
                      'Changer le statut de la commande',
                      'Change order status manually',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['change_order_status'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('change_order_status', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'النقل للمرحلة التالية (Passer à l\'étape suivante)',
                      'Passer à l\'étape suivante',
                      'Pass to next stage',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['pass_to_next_stage'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('pass_to_next_stage', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تكرار / نسخ الطلبية (Duplicate)',
                      'Dupliquer la commande',
                      'Duplicate order',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['duplicate_orders'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('duplicate_orders', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'توزيع المهام وإسناد العمل للعمال',
                      'Attribution des tâches aux ouvriers',
                      'Assign tasks to workers',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['order_allocation'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('order_allocation', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية جميع إسنادات ومهام العمال',
                      'Voir toutes les tâches de l\'atelier',
                      'View all worker assigned tasks',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'تسمح للمشرف أو نائب المدير بمتابعة وإدراج كل المهام المسندة لجميع عمال الورشة',
                      'Permet de voir toutes les tâches attribuées à l\'équipe',
                      'Allows supervisor/co-manager to monitor all assigned tasks',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['view_all_worker_tasks'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_all_worker_tasks', val),
                ),
              ],
            );

            // 📐 بطاقة قياسات الموقع الذكية
            final cat2Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const ['measurements_card', 'confirm_measurements'],
                  viewOnlyKeys: const ['measurements_card'],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'دخول بطاقة رفع القياسات الذكية (الموقع)',
                      'Accès carte de mesure site',
                      'Access site measurements card',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['measurements_card'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('measurements_card', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تأكيد قياسات الموقع وتوليد ملصقات الباركود',
                      'Confirmer les mesures & QR/Code-barres',
                      'Confirm site measurements & generate QR/Barcodes',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['confirm_measurements'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('confirm_measurements', val),
                ),
              ],
            );

            // 3️⃣ تصنيف مهامي وتصنيع اعتماداتي والمهام الخارجية
            final cat3Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'view_my_tasks',
                    'view_my_accreditations',
                    'view_profiles',
                    'view_glass',
                    'view_shutters',
                    'view_colors',
                    'view_accessories',
                    'view_series_requirements_report',
                    'view_joints',
                    'view_kit_bundles',
                    'external_operations',
                  ],
                  viewOnlyKeys: const [
                    'view_my_tasks',
                    'view_my_accreditations',
                    'view_profiles',
                    'view_glass',
                    'view_shutters',
                    'view_colors',
                    'view_accessories',
                    'view_series_requirements_report',
                    'view_joints',
                    'view_kit_bundles',
                  ],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مهامي وتصنيعاتي (مهام العمل المسندة)',
                      'Mes tâches attribuées',
                      'My assigned work tasks',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_my_tasks'] ?? false,
                  onChanged: (val) => _updatePermission('view_my_tasks', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تصنيع اعتماداتي (شاشة المنتجات والكتالوج)',
                      'Produits & Catalogue',
                      'Products & Catalogue screen',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_my_accreditations'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_my_accreditations', val),
                ),
                if (perms['view_my_accreditations'] ?? false) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 16, left: 16),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• البروفيلات والأنظمة',
                              '• Profilés & Systèmes',
                              '• Profiles & Systems',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_profiles'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_profiles', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الزجاج',
                              '• Verre',
                              '• Glass page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_glass'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_glass', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الستائر',
                              '• Volets roulants',
                              '• Shutters page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_shutters'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_shutters', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الألوان',
                              '• Couleurs',
                              '• Colors page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_colors'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_colors', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الإكسسوارات',
                              '• Accessoires',
                              '• Accessories page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_accessories'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_accessories', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• صفحة الجوانات',
                              '• Joints',
                              '• Joints page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_joints'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_joints', val),
                        ),
                        SwitchListTile(
                          title: Text(
                            _tr(
                              '• مجموعات الكيت (Kit)',
                              '• Kits & Bundles',
                              '• Kit bundles page',
                              lang,
                            ),
                            style: switchTitleStyle,
                          ),
                          dense: true,
                          value: perms['view_kit_bundles'] ?? false,
                          onChanged: (val) =>
                              _updatePermission('view_kit_bundles', val),
                        ),
                      ],
                    ),
                  ),
                ],
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تقارير متطلبات واستعمال السلاسل',
                      'Rapports des besoins et de l’utilisation des gammes',
                      'Series requirements and usage reports',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'يعرض قواعد السلسلة والقطاعات المرتبطة والطلبات التي استعملتها.',
                      'Affiche les règles, les profilés liés et les commandes utilisant la gamme.',
                      'Shows series rules, linked profiles, and orders that used the series.',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['view_series_requirements_report'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_series_requirements_report', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الأعمال والمهمات الخارجية (Opérations Externe)',
                      'Opérations Externe',
                      'External Operations',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['external_operations'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('external_operations', val),
                ),
              ],
            );

            // 🛡️ إدارة صلاحيات الفريق (نائب المدير)
            final cat4Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: widget.isDeputyManager
                      ? const [
                          'cloud_backup',
                          'local_json_backup',
                        ]
                      : const [
                          'manage_workers',
                          'edit_worker',
                          'delete_worker',
                          'cloud_backup',
                          'local_json_backup',
                        ],
                  viewOnlyKeys: const [],
                ),
                if (!widget.isDeputyManager)
                  SwitchListTile(
                    title: Text(
                      _tr(
                        'تفويض إدارة صلاحيات الفريق (نائب المدير)',
                        'Délégation gestion d\'équipe',
                        'Delegate team management',
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    subtitle: Text(
                      _tr(
                        'يسمح لهذا العامل بإدارة صلاحيات بقية الفريق بدلاً من المدير',
                        'Permet d\'administrer les permissions de l\'équipe',
                        'Allows worker to manage team permissions',
                        lang,
                      ),
                      style: switchSubTitleStyle,
                    ),
                    value: perms['manage_workers'] ?? false,
                    onChanged: (val) =>
                        _updatePermission('manage_workers', val),
                  ),
                if (!widget.isDeputyManager ||
                    (perms['manage_workers'] ?? false))
                  SwitchListTile(
                    title: Text(
                      _tr(
                        'تعديل بيانات العامل',
                        'Modifier les données de l\'ouvrier',
                        'Edit worker data',
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    subtitle: Text(
                      _tr(
                        'السماح بتعديل اسم العامل وبريده وهاتفه ومنصبه',
                        'Autoriser la modification du profil',
                        'Allow editing worker profile & contact',
                        lang,
                      ),
                      style: switchSubTitleStyle,
                    ),
                    value: perms['edit_worker'] ?? false,
                    onChanged: (val) => _updatePermission('edit_worker', val),
                  ),
                if (!widget.isDeputyManager ||
                    (perms['manage_workers'] ?? false))
                  SwitchListTile(
                    title: Text(
                      _tr(
                        'حذف / طرد العامل من الورشة',
                        'Supprimer l\'ouvrier de l\'atelier',
                        'Delete worker from workshop',
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    subtitle: Text(
                      _tr(
                        'السماح بحذف العامل نهائياً من قائمة الفريق',
                        'Autoriser la suppression définitive de l\'ouvrier',
                        'Allow deleting worker from workshop',
                        lang,
                      ),
                      style: switchSubTitleStyle,
                    ),
                    value: perms['delete_worker'] ?? false,
                    onChanged: (val) => _updatePermission('delete_worker', val),
                  ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'النسخ الاحتياطي على السحابة',
                      'Sauvegarde cloud',
                      'Cloud backup',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح برفع وحفظ نسخة احتياطية من الورشة للسحابة',
                      'Autoriser la sauvegarde de l\'atelier sur le cloud',
                      'Allow backing up workshop data to cloud',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['cloud_backup'] ?? false,
                  onChanged: (val) => _updatePermission('cloud_backup', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'النسخ الاحتياطي المحلي (ملف JSON)',
                      'Sauvegarde locale JSON',
                      'Local JSON backup',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح بتصدير واستيراد ملفات النسخ الاحتياطي بصيغة JSON على الهاتف',
                      'Autoriser l\'importation/exportation de fichiers JSON',
                      'Allow importing/exporting JSON backup files',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['local_json_backup'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('local_json_backup', val),
                ),
              ],
            );

            // 4️⃣ تصنيف الإعدادات وأنظمة الورشة
            final cat5Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'settings',
                    'view_subscription',
                    'select_systems',
                  ],
                  viewOnlyKeys: const ['settings', 'view_subscription'],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الدخول لصفحة الإعدادات',
                      'Accès aux paramètres',
                      'Access settings page',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['settings'] ?? false,
                  onChanged: (val) => _updatePermission('settings', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية الاشتراك ومدة الصلاحية',
                      'Voir l’abonnement et sa durée',
                      'View subscription and expiry',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح للعامل برؤية معلومات اشتراك الورشة فقط',
                      'Autoriser l’ouvrier à voir les informations de l’abonnement',
                      'Allow the worker to view workshop subscription details',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['view_subscription'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('view_subscription', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تحديد الأنظمة المستعملة بالورشة',
                      'Sélection des systèmes de l\'atelier',
                      'Select active workshop systems',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['select_systems'] ?? false,
                  onChanged: (val) => _updatePermission('select_systems', val),
                ),
              ],
            );

            // 5️⃣ تصنيف المالية والصناديق والأجور
            final cat6Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'change_prices',
                    'view_cost_price',
                    'change_payment_dates',
                    'treasury',
                    'manage_caisses',
                    'add_caisses',
                    'edit_payments',
                    'delete_payments',
                    'worker_finances',
                    'worker_settlement',
                  ],
                  viewOnlyKeys: const [
                    'view_cost_price',
                    'treasury',
                    'worker_finances',
                    'worker_settlement',
                  ],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير وتحديث الأسعار',
                      'Modifier et mettre à jour les prix',
                      'Change & update prices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['change_prices'] ?? false,
                  onChanged: (val) => _updatePermission('change_prices', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية سعر التكلفة',
                      'Voir le prix de revient',
                      'View cost price',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_cost_price'] ?? false,
                  onChanged: (val) => _updatePermission('view_cost_price', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير تواريخ الدفعات والمعاملات (الصندوق)',
                      'Modifier les dates des paiements (Trésorerie)',
                      'Change payment and treasury transaction dates',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح للعامل بتغيير تاريخ الدفعات والإدخالات والإخراجات المالية',
                      'Autoriser la modification de la date des opérations',
                      'Allows changing dates of financial transactions',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['change_payment_dates'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('change_payment_dates', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'التعامل مع الصندوق (الخزينة)',
                      'Accès à la trésorerie',
                      'Treasury access',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['treasury'] ?? false,
                  onChanged: (val) => _updatePermission('treasury', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إدارة الصناديق',
                      'Gérer les caisses',
                      'Manage cash boxes',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['manage_caisses'] ?? false,
                  onChanged: (val) => _updatePermission('manage_caisses', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إضافة صندوق جديد',
                      'Ajouter une caisse',
                      'Add a cash box',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح للعامل بإنشاء صندوق جديد فقط',
                      'Autoriser l’ouvrier à créer une nouvelle caisse',
                      'Allow the worker to create a new cash box',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['add_caisses'] ?? false,
                  onChanged: (val) => _updatePermission('add_caisses', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل المدفوعات والمعاملات',
                      'Modifier les paiements',
                      'Edit payments and transactions',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_payments'] ?? false,
                  onChanged: (val) => _updatePermission('edit_payments', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'حذف المدفوعات والمعاملات',
                      'Supprimer les paiements',
                      'Delete payments and transactions',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['delete_payments'] ?? false,
                  onChanged: (val) => _updatePermission('delete_payments', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إدارة شؤون وأجور العمال',
                      'Gestion des salaires des ouvriers',
                      'Worker finances & wages',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['worker_finances'] ?? false,
                  onChanged: (val) => _updatePermission('worker_finances', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'المحاسبة الأسبوعية للعمال',
                      'Règlement hebdomadaire des ouvriers',
                      'Weekly worker settlement',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['worker_settlement'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('worker_settlement', val),
                ),
              ],
            );

            // 6️⃣ تصنيف المخزون والمشتريات والموردين
            final cat7Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'inventory',
                    'inventory_adjustment',
                    'add_warehouses',
                    'view_suppliers',
                    'purchases',
                    'add_purchases',
                    'edit_purchases',
                    'change_purchase_dates',
                    'delete_purchases',
                    'global_consumption',
                  ],
                  viewOnlyKeys: const [
                    'inventory',
                    'view_suppliers',
                    'purchases',
                    'global_consumption',
                  ],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'دخول ورؤية وإدارة المخزون (Stock)',
                      'Gestion du stock',
                      'Inventory stock management',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['inventory'] ?? false,
                  onChanged: (val) => _updatePermission('inventory', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الجرد السنوي / تصحيح المخزون',
                      'Inventaire annuel / Ajustement du stock',
                      'Annual inventory / Stock adjustment',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _inventoryAdjustmentWindowLabel(lang),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                  value: _isPermissionEnabled(perms['inventory_adjustment']),
                  onChanged: (val) => val
                      ? _setInventoryAdjustmentPreset(7)
                      : _disableInventoryAdjustment(),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إضافة مستودع جديد',
                      'Ajouter un entrepôt',
                      'Add a warehouse',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح للعامل بإنشاء مستودع جديد فقط',
                      'Autoriser l’ouvrier à créer un nouvel entrepôt',
                      'Allow the worker to create a new warehouse',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['add_warehouses'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('add_warehouses', val),
                ),
                if (_isPermissionEnabled(perms['inventory_adjustment']))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: Text(
                            _tr('أسبوع', 'Une semaine', 'One week', lang),
                          ),
                          selected: _inventoryAdjustmentMatchesDays(7),
                          onSelected: (_) => _setInventoryAdjustmentPreset(7),
                        ),
                        ChoiceChip(
                          label: Text(
                            _tr('10 أيام', '10 jours', '10 days', lang),
                          ),
                          selected: _inventoryAdjustmentMatchesDays(10),
                          onSelected: (_) => _setInventoryAdjustmentPreset(10),
                        ),
                        ChoiceChip(
                          label: Text(_tr('شهر', 'Un mois', 'One month', lang)),
                          selected: _inventoryAdjustmentMatchesDays(30),
                          onSelected: (_) => _setInventoryAdjustmentPreset(30),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickInventoryAdjustmentRange(lang),
                          icon: const Icon(Icons.date_range_rounded, size: 18),
                          label: Text(
                            _tr(
                              'تاريخ بداية ونهاية',
                              'Date début et fin',
                              'Start and end date',
                              lang,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إدارة ورؤية الموردين',
                      'Voir et gérer les fournisseurs',
                      'View & manage suppliers',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['view_suppliers'] ?? false,
                  onChanged: (val) => _updatePermission('view_suppliers', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'رؤية المشتريات',
                      'Voir les achats',
                      'View purchases',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['purchases'] ?? false,
                  onChanged: (val) => _updatePermission('purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إضافة فواتير مشتريات جديدة',
                      'Ajouter de nouvelles factures d\'achats',
                      'Add new purchase invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['add_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('add_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تعديل فواتير المشتريات',
                      'Modifier les factures d\'achats',
                      'Edit purchase invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['edit_purchases'] ?? false,
                  onChanged: (val) => _updatePermission('edit_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تغيير تاريخ المشتريات والفواتير',
                      'Modifier la date des achats et factures',
                      'Change purchase and invoice dates',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح بتعديل التاريخ المحاسبي للشراء دون تغيير بياناته الأخرى',
                      'Autoriser la modification de la date comptable de l’achat',
                      'Allows changing the accounting date of a purchase',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['change_purchase_dates'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('change_purchase_dates', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مسح / حذف فواتير المشتريات',
                      'Supprimer les factures d\'achats',
                      'Delete purchase invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['delete_purchases'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('delete_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تقرير النواقص والاستهلاك الشامل',
                      'Rapport de consommation globale',
                      'Global consumption & missing report',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['global_consumption'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('global_consumption', val),
                ),
              ],
            );

            // 7️⃣ تصنيف الإحصائيات والتقارير
            final cat8Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'statistics',
                    'accelerate_confirmed_invoices',
                  ],
                  viewOnlyKeys: const ['statistics'],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'دخول الإحصائيات والتقارير',
                      'Accès aux statistiques',
                      'Access statistics & reports',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['statistics'] ?? false,
                  onChanged: (val) => _updatePermission('statistics', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'إسراع الفواتير المؤكدة',
                      'Accélérer les factures confirmées',
                      'Accelerate confirmed invoices',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['accelerate_confirmed_invoices'] ?? false,
                  onChanged: (val) =>
                      _updatePermission('accelerate_confirmed_invoices', val),
                ),
              ],
            );

            // 9️⃣ تصنيف محل بيع المواد ونطاقات العمل
            final cat9Content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionGroupActions(
                  lang: lang,
                  allKeys: const [
                    'access_workshop',
                    'access_store',
                    'access_management',
                    'store_sales',
                    'view_store_sales',
                    'create_store_sales',
                    'edit_store_sales',
                    'confirm_store_sales',
                    'delete_store_sales',
                    'register_store_payments',
                    'return_store_sales',
                    'view_document_history',
                    'restore_deleted_documents',
                    'close_business_day',
                    'store_purchases',
                    'workshop_purchases',
                    'internal_sales',
                  ],
                  viewOnlyKeys: const [
                    'access_workshop',
                    'access_store',
                  ],
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الدخول لنطاق الورشة (Atelier)',
                      'Accès à la section Atelier',
                      'Access Workshop Section',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'إظهار أو إخفاء عناصر الورشة والتصنيع لهذا المستخدم',
                      'Afficher ou masquer les éléments de l\'atelier pour cet utilisateur',
                      'Show or hide workshop elements for this user',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['access_workshop'] ?? true,
                  onChanged: (val) => _updatePermission('access_workshop', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الدخول لنطاق محل بيع المواد (Magasin)',
                      'Accès à la section Magasin de matériaux',
                      'Access Materials Store Section',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'إظهار أو إخفاء عناصر بيع المواد لهذا المستخدم',
                      'Afficher ou masquer les éléments du magasin pour cet utilisateur',
                      'Show or hide store elements for this user',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['access_store'] ?? true,
                  onChanged: (val) => _updatePermission('access_store', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'الدخول لنطاق الإدارة العامة (Administration)',
                      'Accès à la section Administration',
                      'Access General Management Section',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['access_management'] ?? false,
                  onChanged: (val) => _updatePermission('access_management', val),
                ),
                const Divider(),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مبيعات وفواتير محل المواد',
                      'Ventes et facturation du magasin',
                      'Store Sales & Invoicing',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['store_sales'] ?? true,
                  onChanged: (val) => _updatePermission('store_sales', val),
                ),
                ...[
                  (
                    'view_store_sales',
                    'مشاهدة مبيعات ووثائق المحل',
                    'Voir les ventes et documents du magasin',
                    'View store sales and documents',
                  ),
                  (
                    'create_store_sales',
                    'إنشاء وثائق مبيعات المحل',
                    'Créer les documents de vente magasin',
                    'Create store sales documents',
                  ),
                  (
                    'edit_store_sales',
                    'تعديل مسودات مبيعات المحل',
                    'Modifier les brouillons de vente magasin',
                    'Edit store sales drafts',
                  ),
                  (
                    'confirm_store_sales',
                    'تأكيد وتسليم مبيعات المحل',
                    'Confirmer et livrer les ventes magasin',
                    'Confirm and deliver store sales',
                  ),
                  (
                    'delete_store_sales',
                    'إلغاء أو حذف وثائق المحل',
                    'Annuler ou supprimer les documents magasin',
                    'Cancel or delete store documents',
                  ),
                  (
                    'register_store_payments',
                    'تسجيل تحصيلات المحل',
                    'Enregistrer les encaissements magasin',
                    'Register store payments',
                  ),
                  (
                    'return_store_sales',
                    'تنفيذ مرتجعات المحل',
                    'Exécuter les retours magasin',
                    'Process store returns',
                  ),
                  (
                    'view_document_history',
                    'مشاهدة تاريخ الوثائق قبل وبعد التعديل',
                    'Voir l’historique avant/après des documents',
                    'View document before/after history',
                  ),
                  (
                    'restore_deleted_documents',
                    'استرجاع الوثائق المحذوفة',
                    'Restaurer les documents supprimés',
                    'Restore deleted documents',
                  ),
                  (
                    'close_business_day',
                    'إجراء التسوية والإقفال اليومي',
                    'Effectuer la clôture journalière',
                    'Perform daily closing',
                  ),
                ].map(
                  (permission) => SwitchListTile(
                    title: Text(
                      _tr(
                        permission.$2,
                        permission.$3,
                        permission.$4,
                        lang,
                      ),
                      style: switchTitleStyle,
                    ),
                    value: perms[permission.$1] ?? false,
                    onChanged: (val) =>
                        _updatePermission(permission.$1, val),
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مشتريات محل المواد المستقلة',
                      'Achats du magasin de matériaux',
                      'Materials Store Purchases',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['store_purchases'] ?? true,
                  onChanged: (val) => _updatePermission('store_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'مشتريات الورشة المستقلة',
                      'Achats de l\'atelier',
                      'Workshop Purchases',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  value: perms['workshop_purchases'] ?? true,
                  onChanged: (val) => _updatePermission('workshop_purchases', val),
                ),
                SwitchListTile(
                  title: Text(
                    _tr(
                      'تنفيذ البيع الداخلي والتحويل للورشة',
                      'Exécuter les ventes internes vers l\'atelier',
                      'Execute Internal Sales to Workshop',
                      lang,
                    ),
                    style: switchTitleStyle,
                  ),
                  subtitle: Text(
                    _tr(
                      'السماح بتحويل المواد تلقائياً من مخزن المحل إلى مخزن الورشة',
                      'Autoriser le transfert automatique du stock magasin vers l\'atelier',
                      'Allow automatic stock transfer from store to workshop warehouse',
                      lang,
                    ),
                    style: switchSubTitleStyle,
                  ),
                  value: perms['internal_sales'] ?? true,
                  onChanged: (val) => _updatePermission('internal_sales', val),
                ),
              ],
            );

            final categoryWidgets = [
              cat0Content,
              cat1Content,
              cat2Content,
              cat3Content,
              cat4Content,
              cat5Content,
              cat6Content,
              cat7Content,
              cat8Content,
              cat9Content,
            ];

            final isDesktop = MediaQuery.of(ctx).size.width >= 680;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDesktop)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _tr(
                            'طريقة العرض:',
                            'Mode d\'affichage:',
                            'View mode:',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment<bool>(
                              value: true,
                              icon: const Icon(Icons.vertical_split_rounded, size: 16),
                              label: Text(
                                _tr('شاشة مقسمة', 'Écran divisé', 'Split screen', lang),
                                style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
                              ),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              icon: const Icon(Icons.view_agenda_rounded, size: 16),
                              label: Text(
                                _tr('قوائم منسدلة', 'Accordéon', 'Accordion', lang),
                                style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
                              ),
                            ),
                          ],
                          selected: {_useSplitView},
                          onSelectionChanged: (Set<bool> newSelection) {
                            _setUseSplitView(newSelection.first);
                          },
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_useSplitView && isDesktop)
                  _buildSplitView(ctx, lang, isDark, titleStyle, categories, categoryWidgets)
                else
                  for (int i = 0; i < categories.length; i++) ...[
                    ExpansionTile(
                      leading: Icon(
                        categories[i]['icon'] as IconData,
                        color: categories[i]['color'] as Color,
                      ),
                      title: Text(
                        categories[i]['title'] as String,
                        style: titleStyle,
                      ),
                      children: [categoryWidgets[i]],
                    ),
                    if (i < categories.length - 1) blueDivider,
                  ],
              ],
            );
          },
        ),
      ],
    ],
      ),
    );
  }
}
