import re

path = 'lib/Screen/welcom_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove FadeTransition and AnimationController
content = re.sub(r'with SingleTickerProviderStateMixin\s*\{', '{', content)
content = re.sub(r'\s*late AnimationController _ctrl;\s*late Animation<double> _fadeIn;', '', content)
content = re.sub(r'\s*_ctrl = AnimationController\([^;]+;\s*_fadeIn = CurvedAnimation\([^;]+;\s*_ctrl\.forward\(\);', '', content)
content = re.sub(r'\s*SystemChrome\.setSystemUIOverlayStyle\([^;]+;\s*', '', content)
content = re.sub(r'\s*@override\s*void dispose\(\)\s*\{\s*_ctrl\.dispose\(\);\s*super\.dispose\(\);\s*\}', '', content)

# Remove FadeTransition wrapper
content = re.sub(r'body:\s*FadeTransition\(\s*opacity:\s*_fadeIn,\s*child:\s*CustomScrollView\(', 'body: CustomScrollView(', content)
content = re.sub(r'\),\s*\),\s*\]\s*,\s*\)\s*,\s*\)', '), ], ), )', content) # roughly match the end of CustomScrollView... actually it's easier to just do string replacement.

# Let's do exact string replacements for the body part
content = content.replace('body: FadeTransition(\n        opacity: _fadeIn,\n        child: CustomScrollView(', 'body: CustomScrollView(')
# we need to remove one closing parenthesis at the end of the build method
# Let's find the build method
build_pattern = r'(body: CustomScrollView\(.*?\n        \),\n      ),\n    );'
content = re.sub(r'(\s+)\),\n\s*\),\n\s*\]\s*,\s*\)\s*,\s*\)', r'\1),\n              ),\n            ),\n          ],\n        )', content, flags=re.DOTALL)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
