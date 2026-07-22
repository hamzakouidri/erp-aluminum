import 'dart:io';

void main() {
  String content = File('lib/services/cloud_sync_service.dart').readAsStringSync();
  
  // Fix _silentBackup
  String silentBackupTarget = """
      // [تم الإصلاح]: إزالة التحقق من البريد الإلكتروني الثابت
      // يجب استخدام نظام صلاحيات صحيح بدلاً من ذلك
      // final user = _auth.currentUser;
      // if (user != null && _isGlobalAdmin(user)) {
      //   await backupGlobalCatalog();
      // }
""";
  String silentBackupReplacement = """
      final user = _auth.currentUser;
      if (user != null && user.email == 'kouidrihamza45@gmail.com') {
        await backupGlobalCatalog();
      }
""";
  if (content.contains(silentBackupTarget)) {
    content = content.replaceFirst(silentBackupTarget, silentBackupReplacement);
  }

  // Fix downloadGlobalCatalog caching issue
  String downloadGlobalTarget = """
    DocumentSnapshot doc = await catalogRef.get();
""";
  String downloadGlobalReplacement = """
    DocumentSnapshot doc = await catalogRef.get(const GetOptions(source: Source.server));
""";
  if (content.contains(downloadGlobalTarget)) {
    content = content.replaceFirst(downloadGlobalTarget, downloadGlobalReplacement);
  }

  String chunksTarget = """
        var snapshot = await catalogRef.collection('chunks').get();
""";
  String chunksReplacement = """
        var snapshot = await catalogRef.collection('chunks').get(const GetOptions(source: Source.server));
""";
  if (content.contains(chunksTarget)) {
    content = content.replaceFirst(chunksTarget, chunksReplacement);
  }
  
  // Fix admin check in backupGlobalCatalog
  String backupGlobalAdminTarget = """
    // [تم الإصلاح]: إزالة التحقق من البريد الإلكتروني الثابت
    // يجب استخدام نظام صلاحيات صحيح
    if (user == null) return;
    // if (!_isGlobalAdmin(user)) return;
""";
  String backupGlobalAdminReplacement = """
    if (user == null) return;
    if (user.email != 'kouidrihamza45@gmail.com') return;
""";
  if (content.contains(backupGlobalAdminTarget)) {
    content = content.replaceFirst(backupGlobalAdminTarget, backupGlobalAdminReplacement);
  }

  File('lib/services/cloud_sync_service.dart').writeAsStringSync(content);
  print("Updated cloud_sync_service.dart");
}
