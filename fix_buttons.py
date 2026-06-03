import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Remove the "Empty" button logic
empty_regex = r"(\s*)_ContentButton\(\s*label:\s*'.*?',\s*icon:\s*Icons\.crop_free_rounded,\s*selected:\s*zone\.content == ZoneContent\.empty,\s*onPressed:\s*\(\)\s*=>\s*activeModel\.setSelectedZoneContent\(ZoneContent\.empty\),\s*\),\s*SizedBox\(width:\s*\d+\),"
content = re.sub(empty_regex, "", content, flags=re.DOTALL)

# 2. Fix the else if bug in french
else_if_regex = r"\] else if \(widget\.systemMode == 'french'\) \.\.\.\["
content = content.replace("] else if (widget.systemMode == 'french') ...[", "] \n                  if (widget.systemMode == 'french') ...[")

# 3. Create the 4 separate buttons for sliding
sliding_old_regex = r"(\s*)if \(widget\.systemMode == 'sliding'\) \.\.\.\[\s*SizedBox\(width:\s*\d+\),\s*_ContentButton\([\s\S]*?\}\s*,\s*\),\s*\]"

new_sliding_buttons = """                  if (widget.systemMode == 'sliding') ...[
                    SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق (2 ضلفة)',
                      icon: Icons.sync_alt_rounded,
                      selected: zone.content == ZoneContent.slidingSash && zone.slidingSashesCount == 2,
                      onPressed: () {
                        activeModel.setSelectedZoneContent(ZoneContent.slidingSash);
                        activeModel.setSlidingSashesCount(2);
                        _showGlassPropertiesDialog(context, activeModel);
                      },
                    ),
                    SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق (3 ضلفات)',
                      icon: Icons.sync_alt_rounded,
                      selected: zone.content == ZoneContent.slidingSash && zone.slidingSashesCount == 3,
                      onPressed: () {
                        activeModel.setSelectedZoneContent(ZoneContent.slidingSash);
                        activeModel.setSlidingSashesCount(3);
                        _showGlassPropertiesDialog(context, activeModel);
                      },
                    ),
                    SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق (4 ضلفات)',
                      icon: Icons.sync_alt_rounded,
                      selected: zone.content == ZoneContent.slidingSash && zone.slidingSashesCount == 4,
                      onPressed: () {
                        activeModel.setSelectedZoneContent(ZoneContent.slidingSash);
                        activeModel.setSlidingSashesCount(4);
                        _showGlassPropertiesDialog(context, activeModel);
                      },
                    ),
                    SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق (5 ضلفات)',
                      icon: Icons.sync_alt_rounded,
                      selected: zone.content == ZoneContent.slidingSash && zone.slidingSashesCount == 5,
                      onPressed: () {
                        activeModel.setSelectedZoneContent(ZoneContent.slidingSash);
                        activeModel.setSlidingSashesCount(5);
                        _showGlassPropertiesDialog(context, activeModel);
                      },
                    ),
                  ]"""

content = re.sub(sliding_old_regex, "\n" + new_sliding_buttons, content)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
