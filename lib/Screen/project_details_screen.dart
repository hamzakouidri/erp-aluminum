import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/order_workspace_screen.dart';
import 'link_existing_orders_screen.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final SqlDatabase db;
  final int projectId;

  const ProjectDetailsScreen({
    super.key,
    required this.db,
    required this.projectId,
  });

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  Map<String, dynamic>? _project;
  List<Map<String, dynamic>> _commandes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjectDetails();
  }

  Future<void> _loadProjectDetails() async {
    setState(() => _isLoading = true);
    final proj = await widget.db.readProjectById(widget.projectId);
    if (proj != null) {
      final cmds = await widget.db.readCommandesForProject(widget.projectId);
      setState(() {
        _project = proj;
        _commandes = cmds;
        _isLoading = false;
      });
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showEditProjectDialog() {
    if (_project == null) return;
    final nameController = TextEditingController(text: _project!['name']);
    final descController = TextEditingController(text: _project!['description'] ?? '');
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          Localization.translate('تعديل المشروع', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: Localization.translate('اسم المشروع', lang),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: Localization.translate('الوصف', lang),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await widget.db.updateProject(
                widget.projectId,
                name,
                _project!['client_id'] as int,
                descController.text.trim(),
              );
              if (context.mounted) {
                Navigator.pop(context);
                _loadProjectDetails();
              }
            },
            child: Text(Localization.translate('حفظ', lang)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProject() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('حذف المشروع', lang)),
        content: Text(
          Localization.translate(
            'هل أنت متأكد من حذف هذا المشروع؟ سيتم فك ارتباط الطلبيات المرتبطة به دون حذفها.',
            lang,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          TextButton(
            onPressed: () async {
              await widget.db.deleteProject(widget.projectId);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext); // close dialog
              }
              if (context.mounted) {
                Navigator.pop(context); // close screen
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(Localization.translate('حذف', lang)),
          ),
        ],
      ),
    );
  }

  Future<void> _showLinkExistingOrderDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LinkExistingOrdersScreen(
          db: widget.db,
          projectId: widget.projectId,
        ),
      ),
    );
    if (result == true) {
      _loadProjectDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_project == null) {
      return const Scaffold(
        body: Center(child: Text('المشروع غير موجود')),
      );
    }

    final clientName = '${_project!['firstname']} ${_project!['lastname']}'.trim();
    final desc = _project!['description']?.toString() ?? '';
    final double totalProjectAmount = _commandes.fold(0.0, (sum, item) {
      final netPayable = (item['net_payable'] as num?)?.toDouble() ?? 0.0;
      final rawTotal = (item['total'] as num?)?.toDouble() ?? 0.0;
      return sum + (netPayable > 0 ? netPayable : rawTotal);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _project!['name'],
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: Localization.translate('تعديل', lang),
            onPressed: _showEditProjectDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: Localization.translate('حذف', lang),
            onPressed: _confirmDeleteProject,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project Header Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue.shade100,
                          child: const Icon(Icons.person, color: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Localization.translate('الزبون', lang),
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            Text(
                              clientName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text(
                        Localization.translate('الوصف', lang),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: const TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                    ],
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Localization.translate('عدد الطلبيات', lang),
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            Text(
                              '${_commandes.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Localization.translate('إجمالي قيمة المشروع', lang),
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            Text(
                              '${totalProjectAmount.toStringAsFixed(2)} دج',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Orders section title
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    Localization.translate('الطلبيات المرتبطة', lang),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _showLinkExistingOrderDialog,
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('ربط طلبية موجودة'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          openOrderInWorkspaceTab(
                            context,
                            db: widget.db,
                            projectId: widget.projectId,
                            onSaved: _loadProjectDetails,
                          );
                        },
                        icon: const Icon(Icons.add_shopping_cart, size: 16),
                        label: Text(Localization.translate('إضافة طلبية', lang)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Orders List
            _commandes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        Localization.translate('لا توجد طلبيات مرتبطة بهذا المشروع حالياً', lang),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _commandes.length,
                    itemBuilder: (context, index) {
                      final cmd = _commandes[index];
                      final netPayable = (cmd['net_payable'] as num?)?.toDouble() ?? 0.0;
                      final rawTotal = (cmd['total'] as num?)?.toDouble() ?? 0.0;
                      final total = netPayable > 0 ? netPayable : rawTotal;
                      final status = cmd['status'] ?? 'Pending';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text('طلب #${cmd['id']}'),
                          subtitle: Text(cmd['created_at']?.toString().split('T')[0] ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${total.toStringAsFixed(2)} دج',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: status.toLowerCase() == 'paid'
                                          ? Colors.green
                                          : (status.toLowerCase() == 'pending' ? Colors.orange : Colors.blue),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, size: 16),
                            ],
                          ),
                          onTap: () {
                            openOrderInWorkspaceTab(
                              context,
                              db: widget.db,
                              editCommandeId: cmd['id'] as int,
                              onSaved: _loadProjectDetails,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
