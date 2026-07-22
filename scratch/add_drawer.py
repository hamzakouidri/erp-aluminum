import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace Scaffold to add endDrawer and remove the toolbars from body
old_scaffold = """        return Scaffold(
          backgroundColor: const Color(0xFFE8EAF6),
          appBar: _buildAppBar(context),
          body: Column(
            children: [
              _buildGlobalSettingsBar(context),
              buildShutterSidesControl(context, widget.model),
              if (!isMullionSelected) _buildSplitToolbar(context, hasSelection),"""

new_scaffold = """        return Scaffold(
          backgroundColor: const Color(0xFFE8EAF6),
          appBar: _buildAppBar(context),
          endDrawer: Drawer(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('إعدادات النافذة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ),
                    const Divider(),
                    _buildGlobalSettingsBar(context),
                    const Divider(),
                    buildShutterSidesControl(context, widget.model),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              if (!isMullionSelected) _buildSplitToolbar(context, hasSelection),"""

content = content.replace(old_scaffold, new_scaffold)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Added endDrawer to Scaffold.")
