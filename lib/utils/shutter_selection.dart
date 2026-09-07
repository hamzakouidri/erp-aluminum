/// The selected component is authoritative for drawings and saved documents.
/// Older orders may contain only the legacy shutterLame label.
String resolveShutterBladeName(Object? componentOverrides, {Object? fallback}) {
  if (componentOverrides is Map) {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade is Map) {
      final name = blade['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
  }
  return fallback?.toString().trim() ?? '';
}
