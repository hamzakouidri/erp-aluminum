import re

with open('lib/Commande/Systeme/show_system_francais.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# We want to wrap singleSash and doubleSash in `if (widget.systemMode == 'french') { ... }`
# And slidingSash in `if (widget.systemMode == 'sliding') { ... }`

# Since dart supports collection if `if (condition) ...[ items ]` in lists,
# we can use that! Wait, we are in a `Row(children: [ ... ])`. So we can use `if (widget.systemMode == 'french') ...[ SizedBox(), _ContentButton(...) ],`

pattern = r"""(\s*SizedBox\(width: 8\),\s*_ContentButton\(\s*label: '[^']+',\s*icon: Icons\.door_back_door_rounded,\s*selected: zone\.content == ZoneContent\.singleSash,.*?_showGlassPropertiesDialog\(context, activeModel\);\s*},\s*\),\s*SizedBox\(width: 8\),\s*_ContentButton\(\s*label: '[^']+',\s*icon: Icons\.garage_rounded,\s*selected: zone\.content == ZoneContent\.doubleSash,.*?_showGlassPropertiesDialog\(context, activeModel\);\s*},\s*\),)(\s*SizedBox\(width: 8\),\s*_ContentButton\(\s*label: '[^']+',\s*icon: Icons\.sync_alt_rounded,\s*selected: zone\.content == ZoneContent\.slidingSash,.*?_showGlassPropertiesDialog\(context, activeModel\);\s*},\s*\),)"""

def replacer(match):
    french_buttons = match.group(1)
    sliding_button = match.group(2)
    
    return f"""
                    if (widget.systemMode == 'french') ...[
{french_buttons}
                    ],
                    if (widget.systemMode == 'sliding') ...[
{sliding_button}
                    ],"""

new_text, count = re.subn(pattern, replacer, text, flags=re.DOTALL)

print(f"Replaced {count} occurrences")

with open('lib/Commande/Systeme/show_system_francais.dart', 'w', encoding='utf-8') as f:
    f.write(new_text)
