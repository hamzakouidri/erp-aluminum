import re

file_path = "lib/Commande/Systeme/show_system_francais.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Make slider 3 and 4 available without restrictions
# For slider 3:
old_slider_3 = """                    // 🟢 أزرار إضافية تظهر فقط للسلاسل المخصصة (مثل 4 ضلفات)
                    // ضع هنا اسم السلسلة أو الكود الذي يدعم أكثر من 3 ضلفات
                    if (seriesName.contains('h36') ||
                        seriesName.contains('67000') ||
                        seriesName.contains('67000ld') ||
                        seriesName.contains('70kp')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 3',
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 3,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.slidingSash,
                          );
                          widget.model.setSlidingSashesCount(
                            3,
                          ); // تحديد العدد 4
                        },
                      ),
                    ],"""

new_slider_3 = """                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق 3',
                      icon: Icons.sync_alt_rounded,
                      selected:
                          zone.content == ZoneContent.slidingSash &&
                          zone.slidingSashesCount == 3,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(
                          ZoneContent.slidingSash,
                        );
                        widget.model.setSlidingSashesCount(
                          3,
                        );
                      },
                    ),"""

content = content.replace(old_slider_3, new_slider_3)

# For slider 4:
old_slider_4 = """                    if (seriesName.contains('h36')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 4',
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 4,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.slidingSash,
                          );
                          widget.model.setSlidingSashesCount(
                            4,
                          ); // تحديد العدد 4
                        },
                      ),
                    ],"""

new_slider_4 = """                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق 4',
                      icon: Icons.sync_alt_rounded,
                      selected:
                          zone.content == ZoneContent.slidingSash &&
                          zone.slidingSashesCount == 4,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(
                          ZoneContent.slidingSash,
                        );
                        widget.model.setSlidingSashesCount(
                          4,
                        );
                      },
                    ),"""

content = content.replace(old_slider_4, new_slider_4)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Sliders unlocked.")
