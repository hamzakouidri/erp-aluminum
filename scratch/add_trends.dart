import 'dart:io';

void main() {
  String path = 'lib/sql_database.dart';
  String content = File(path).readAsStringSync();

  String newMethod = '''  Future<Map<String, dynamic>> getDashboardStats() async {
    final database = await db;
    if (database == null) return {'cmdCount': '0', 'cmdTrend': '—', 'cliCount': '0', 'cliTrend': '—'};

    try {
      DateTime now = DateTime.now();
      DateTime startOfThisMonth = DateTime(now.year, now.month, 1);
      DateTime startOfLastMonth = DateTime(now.year, now.month - 1, 1);

      String thisMonthStr = startOfThisMonth.toIso8601String();
      String lastMonthStr = startOfLastMonth.toIso8601String();

      // Commandes
      final cmds = await database.query('Commandes');
      int cmdThisMonth = 0;
      int cmdLastMonth = 0;
      for (var row in cmds) {
        if (row['created_at'] != null) {
          try {
            DateTime dt = DateTime.parse(row['created_at'].toString());
            if (dt.isAfter(startOfThisMonth) || dt.isAtSameMomentAs(startOfThisMonth)) {
              cmdThisMonth++;
            } else if (dt.isAfter(startOfLastMonth) && dt.isBefore(startOfThisMonth)) {
              cmdLastMonth++;
            }
          } catch (_) {}
        }
      }
      
      String cmdTrend = '—';
      if (cmdLastMonth > 0) {
        double diff = ((cmdThisMonth - cmdLastMonth) / cmdLastMonth) * 100;
        cmdTrend = diff >= 0 ? '+\${diff.toStringAsFixed(1)}%' : '\${diff.toStringAsFixed(1)}%';
      } else if (cmdThisMonth > 0) {
        cmdTrend = '+\${cmdThisMonth} (جديد)';
      }

      // Clients
      final clis = await database.query('Client');
      int cliThisMonth = 0;
      int cliLastMonth = 0;
      for (var row in clis) {
        if (row['created_at'] != null) {
          try {
            DateTime dt = DateTime.parse(row['created_at'].toString());
            if (dt.isAfter(startOfThisMonth) || dt.isAtSameMomentAs(startOfThisMonth)) {
              cliThisMonth++;
            } else if (dt.isAfter(startOfLastMonth) && dt.isBefore(startOfThisMonth)) {
              cliLastMonth++;
            }
          } catch (_) {}
        }
      }

      String cliTrend = '—';
      if (cliLastMonth > 0) {
        double diff = ((cliThisMonth - cliLastMonth) / cliLastMonth) * 100;
        cliTrend = diff >= 0 ? '+\${diff.toStringAsFixed(1)}%' : '\${diff.toStringAsFixed(1)}%';
      } else if (cliThisMonth > 0) {
        cliTrend = '+\${cliThisMonth} (جديد)';
      }

      return {
        'cmdCount': cmds.length.toString(),
        'cmdTrend': cmdTrend,
        'cliCount': clis.length.toString(),
        'cliTrend': cliTrend,
      };
    } catch (e) {
      print("Error getting stats: \$e");
      return {'cmdCount': '0', 'cmdTrend': '—', 'cliCount': '0', 'cliTrend': '—'};
    }
  }
''';

  if (!content.contains('getDashboardStats')) {
    int lastBracketIndex = content.lastIndexOf('}');
    content = content.substring(0, lastBracketIndex) + newMethod + '}\n';
    File(path).writeAsStringSync(content);
    print("Added getDashboardStats to sql_database.dart");
  } else {
    print("getDashboardStats already exists");
  }
}
