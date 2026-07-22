void main() {
  List<Map<String, dynamic>> list = [];
  try {
    list.firstWhere((e) => false, orElse: () => {'type': ''});
    print('OK');
  } catch (e) {
    print('Error: $e');
  }
}
