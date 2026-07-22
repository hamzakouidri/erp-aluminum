import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Commande/Systeme/show_system_francais.dart'
content = open(path, encoding='utf-8').read()

# 1. State field
old_fields = """  final ScrollController _glassScrollController = ScrollController();
  final TextEditingController _leftSashWidthController = TextEditingController();
  final FocusNode _leftSashFocusNode = FocusNode();"""

new_fields = """  final ScrollController _glassScrollController = ScrollController();
  final TextEditingController _leftSashWidthController = TextEditingController();
  final FocusNode _leftSashFocusNode = FocusNode();
  late final TextEditingController _positionCtrl;"""

content = content.replace(old_fields, new_fields)

# 2. initState
old_init = """  @override
  void initState() {
    super.initState();
    widget.model.loadCatalogData(widget.systemMode);"""

new_init = """  @override
  void initState() {
    super.initState();
    _positionCtrl = TextEditingController(text: widget.model.position ?? '');
    widget.model.loadCatalogData(widget.systemMode);"""

content = content.replace(old_init, new_init)

# 3. dispose
old_dispose = """  @override
  void dispose() {
    _drawingTimer?.cancel();
    _paintbrushTimer?.cancel();
    widget.model.removeListener(_onModelChanged);
    _glassScrollController.dispose();
    _leftSashWidthController.dispose();
    _leftSashFocusNode.dispose();"""

new_dispose = """  @override
  void dispose() {
    _drawingTimer?.cancel();
    _paintbrushTimer?.cancel();
    widget.model.removeListener(_onModelChanged);
    _glassScrollController.dispose();
    _leftSashWidthController.dispose();
    _leftSashFocusNode.dispose();
    _positionCtrl.dispose();"""

content = content.replace(old_dispose, new_dispose)

# 4. Right Drawer textfield
old_drawer = """            // 🟢 1. الخصائص العامة
            Row(
              children: [
                Icon(Icons.tune_rounded, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                const Text(
                  'الخصائص العامة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 20),"""

new_drawer = """            // 🟢 1. الخصائص العامة
            Row(
              children: [
                Icon(Icons.tune_rounded, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                const Text(
                  'الخصائص العامة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 20),

            TextField(
              controller: _positionCtrl,
              decoration: InputDecoration(
                labelText: Localization.translate('موقع النافذة (مثال: المطبخ - الطابق 2)', Provider.of<AppSettingsProvider>(context, listen: false).language),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (val) {
                widget.model.position = val;
              },
            ),
            const SizedBox(height: 15),"""

content = content.replace(old_drawer, new_drawer)

open(path, 'w', encoding='utf-8').write(content)
print("Done updating show_system_francais.dart for position input field!")
