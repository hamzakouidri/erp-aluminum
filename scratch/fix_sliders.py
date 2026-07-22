import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add condition method to state class
condition_method = """  bool _isMultiTrackSystem() {
    String seriesName = (widget.model.activeSeries?.name ?? widget.model.loadedSeriesName ?? "").toLowerCase();
    return seriesName.contains('tpr') ||
           seriesName.contains('h30') ||
           seriesName.contains('h31') ||
           seriesName.contains('h36') ||
           seriesName.contains('67000');
  }"""

if "_isMultiTrackSystem()" not in content:
    content = content.replace(
        "class _WindowViewState extends State<WindowView> {",
        "class _WindowViewState extends State<WindowView> {\n" + condition_method
    )

# Now apply it to Slider 3 and 4
# Slider 3 starts with: _ContentButton(\n                      label: 'منزلق 3',
slider3_pattern = re.compile(r"(_ContentButton\(\s*label:\s*'منزلق 3'.*?\},.*?)[,;]\s*_ContentButton\(\s*label:\s*'منزلق 4'", re.DOTALL)
slider4_pattern = re.compile(r"(_ContentButton\(\s*label:\s*'منزلق 4'.*?\}\s*,\s*\),)", re.DOTALL)

# Let's do a more robust text replacement
old_slider3 = """                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق 3',
                      icon: Icons.sync_alt_rounded,"""

new_slider3 = """                    if (_isMultiTrackSystem()) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 3',
                        icon: Icons.sync_alt_rounded,"""

old_slider4 = """                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق 4',
                      icon: Icons.sync_alt_rounded,"""

new_slider4 = """                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق 4',
                      icon: Icons.sync_alt_rounded,"""
                      
old_end_slider4 = """                        widget.model.setSlidingSashesCount(
                          4,
                        );
                      },
                    ),
                  ],"""

new_end_slider4 = """                        widget.model.setSlidingSashesCount(
                          4,
                        );
                      },
                    ),
                    ],
                  ],"""

if old_slider3 in content:
    content = content.replace(old_slider3, new_slider3)
    content = content.replace(old_end_slider4, new_end_slider4)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Sliders 3 and 4 fixed.")
else:
    print("Could not find slider 3 replacement targets.")
