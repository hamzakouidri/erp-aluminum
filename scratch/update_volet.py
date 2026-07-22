import sys

def modify_volet():
    file_path = "lib/Commande/Systeme/volet.dart"
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading file: {e}")
        return

    # Add sql_database import
    if "import 'package:database_data/sql_database.dart';" not in content:
        content = content.replace(
            "import 'package:database_data/Commande/Systeme/model.dart';",
            "import 'package:database_data/Commande/Systeme/model.dart';\nimport 'package:database_data/sql_database.dart';"
        )

    # State variables
    if "List<String> _lames = [];" not in content:
        state_vars = """
  List<String> _lames = [];
  List<String> _glissieres = [];
  bool _isLoadingOptions = true;

  @override
  void initState() {
    super.initState();
    _loadShutterOptions();
"""
        content = content.replace("""
  @override
  void initState() {""", state_vars)

        # Add _loadShutterOptions method
        load_method = """
  Future<void> _loadShutterOptions() async {
    try {
      final db = SqlDatabase();
      final options = await db.getShutterOptions();
      setState(() {
        _lames = options['lames']!;
        _glissieres = options['glissieres']!;
        if (!_lames.contains(widget.model.shutterLame) && _lames.isNotEmpty) {
          widget.model.shutterLame = _lames.first;
        }
        if (!_glissieres.contains(widget.model.shutterGlissiere) && _glissieres.isNotEmpty) {
          widget.model.shutterGlissiere = _glissieres.first;
        }
        _isLoadingOptions = false;
      });
    } catch (e) {
      setState(() { _isLoadingOptions = false; });
    }
  }
"""
        content = content.replace("  @override\n  void dispose() {", load_method + "\n  @override\n  void dispose() {")

    # Add dropdowns to UI
    # Looking for the row with 'نوع التحكم'
    if "Row _buildShutterOptionsRow" not in content:
        dropdowns_ui = """
                        // Lame & Glissiere
                        if (!_isLoadingOptions)
                          Row(
                            children: [
                              Text('نوع الشفرة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _lames.contains(widget.model.shutterLame) ? widget.model.shutterLame : (_lames.isNotEmpty ? _lames.first : null),
                                  items: _lames.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() { widget.model.shutterLame = val; widget.model.refreshUI(); });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text('نوع السكة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _glissieres.contains(widget.model.shutterGlissiere) ? widget.model.shutterGlissiere : (_glissieres.isNotEmpty ? _glissieres.first : null),
                                  items: _glissieres.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() { widget.model.shutterGlissiere = val; widget.model.refreshUI(); });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 10),
"""
        content = content.replace("                    // المنزلق لرفع وإنزال الستار", dropdowns_ui + "\n                    // المنزلق لرفع وإنزال الستار")

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Modified volet.dart")

if __name__ == "__main__":
    modify_volet()
