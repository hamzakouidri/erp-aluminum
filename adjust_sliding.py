import re

with open("lib/Commande/Systeme/show_system_francais.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Change the text of the sliding button
content = content.replace("label: 'U.U+OU,U,',", "label: 'U.U+OU,U, (2, 3, 4, 5 OU,U?OO)',")
content = content.replace("label: 'منزلق',", "label: 'منزلق (2، 3، 4، 5 ضلفات)',")

# Wrap the fixed glass button with the condition
fixed_glass_button = """                  _ContentButton(
                    label: 'OOO O OO O"O',
                    icon: Icons.window_rounded,
                    selected: zone.content == ZoneContent.fixedGlass,
                    onPressed: () {
                      activeModel.setSelectedZoneContent(
                        ZoneContent.fixedGlass,
                      );
                      _showGlassPropertiesDialog(context, activeModel);
                    },
                  ),"""

if "if (widget.systemMode == 'french' || (widget.systemMode == 'sliding' && activeModel.zones.length > 1)) ...[" not in content:
    fixed_glass_conditional = """                  if (widget.systemMode == 'french' || (widget.systemMode == 'sliding' && activeModel.zones.length > 1)) ...[
                    _ContentButton(
                      label: 'OOO O OO O"O',
                      icon: Icons.window_rounded,
                      selected: zone.content == ZoneContent.fixedGlass,
                      onPressed: () {
                        activeModel.setSelectedZoneContent(
                          ZoneContent.fixedGlass,
                        );
                        _showGlassPropertiesDialog(context, activeModel);
                      },
                    ),
                  ],"""
    
    # We might have Arabic characters instead of U.U+... so let's use a regex to match the button
    regex = r"(\s+)_ContentButton\(\s*label:\s*'[^']+',\s*icon:\s*Icons\.window_rounded,\s*selected:\s*zone\.content == ZoneContent\.fixedGlass,[\s\S]*?_showGlassPropertiesDialog\(context, activeModel\);\s*},\s*\),"
    
    match = re.search(regex, content)
    if match:
        matched_str = match.group(0)
        replacement = f"""{match.group(1)}if (widget.systemMode == 'french' || (widget.systemMode == 'sliding' && activeModel.zones.length > 1)) ...[{matched_str}{match.group(1)}]"""
        content = content.replace(matched_str, replacement)


# Let's fix the sliding label text by Regex if it was Arabic
sliding_regex = r"label:\s*'([^']+)',\s*icon:\s*Icons\.sync_alt_rounded"
match_sliding = re.search(sliding_regex, content)
if match_sliding:
    sliding_label = match_sliding.group(1)
    if "2" not in sliding_label:
        content = content.replace(f"label: '{sliding_label}'", "label: 'منزلق (2، 3، 4، 5 ضلفات)'")

with open("lib/Commande/Systeme/show_system_francais.dart", "w", encoding="utf-8") as f:
    f.write(content)
