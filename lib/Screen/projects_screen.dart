import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/add_commande.dart' show ClientDropdownDialog;
import 'project_details_screen.dart';

class ProjectsScreen extends StatefulWidget {
  final SqlDatabase db;
  const ProjectsScreen({super.key, required this.db});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canViewProjects()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProjects() async {
    setState(() => _isLoading = true);
    final data = _searchQuery.isEmpty
        ? await widget.db.readProjects()
        : await widget.db.searchProjects(_searchQuery);
    setState(() {
      _projects = data;
      _isLoading = false;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    _fetchProjects();
  }

  void _showAddProjectDialog([Map<String, dynamic>? project]) {
    final nameController = TextEditingController(text: project?['name'] ?? '');
    final descController = TextEditingController(text: project?['description'] ?? '');
    Map<String, dynamic>? selectedClient;
    final clientNameController = TextEditingController();

    if (project != null) {
      selectedClient = {
        'id': project['client_id'],
        'firstname': project['firstname'],
        'lastname': project['lastname'],
      };
      clientNameController.text = '${project['firstname']} ${project['lastname']}'.trim();
    }

    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            project == null
                ? Localization.translate('إضافة مشروع جديد', lang)
                : Localization.translate('تعديل المشروع', lang),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: Localization.translate('اسم المشروع', lang),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.folder_open),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clientNameController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: Localization.translate('الزبون', lang),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                    suffixIcon: const Icon(Icons.search),
                  ),
                  onTap: () async {
                    final result = await showDialog(
                      context: context,
                      builder: (context) => ClientDropdownDialog(db: widget.db),
                    );
                    if (result != null && result is Map<String, dynamic>) {
                      setDialogState(() {
                        selectedClient = result;
                        clientNameController.text =
                            '${result['firstname']} ${result['lastname']}'.trim();
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: Localization.translate('الوصف (اختياري)', lang),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.description),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(Localization.translate('يرجى إدخال اسم المشروع', lang))),
                  );
                  return;
                }
                if (selectedClient == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(Localization.translate('يرجى اختيار الزبون', lang))),
                  );
                  return;
                }

                if (project == null) {
                  await widget.db.insertProject(name, selectedClient!['id'] as int, descController.text.trim());
                } else {
                  await widget.db.updateProject(project['id'] as int, name, selectedClient!['id'] as int, descController.text.trim());
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  _fetchProjects();
                }
              },
              child: Text(Localization.translate('حفظ', lang)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('المشاريع', lang),
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search Bar
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: Localization.translate('البحث عن مشروع...', lang),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            const SizedBox(height: 16),

            // Projects List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _projects.isEmpty
                      ? Center(
                          child: Text(
                            Localization.translate('لا توجد مشاريع حالية', lang),
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _projects.length,
                          itemBuilder: (context, index) {
                            final proj = _projects[index];
                            final clientName = '${proj['firstname']} ${proj['lastname']}'.trim();
                            final desc = proj['description']?.toString() ?? '';

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  radius: 25,
                                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.folder, color: Theme.of(context).primaryColor),
                                ),
                                title: Text(
                                  proj['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.person, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            clientName,
                                            style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (desc.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        desc,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProjectDetailsScreen(
                                        db: widget.db,
                                        projectId: proj['id'] as int,
                                      ),
                                    ),
                                  ).then((_) => _fetchProjects());
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProjectDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
