import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/firebase_options.dart';

void main() {
  test('Print Firestore backup chunks', () async {
    // We cannot run Firebase inside a unit test without binding, but we can try to initialize it.
    // If it fails, it's fine.
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final snapshot = await FirebaseFirestore.instance
          .collection('workshops')
          .doc('gpFPvIMjazb23WXedc8ClD4ggXY2')
          .collection('backups')
          .doc('latest')
          .collection('chunks')
          .get();

      print('--- FIREBASE CHUNKS DIAGNOSTICS ---');
      print('Total chunks found: ${snapshot.docs.length}');
      for (var doc in snapshot.docs) {
        print('Chunk Doc ID: ${doc.id} => Table: ${doc.data()['table']}');
      }
      print('-----------------------------------');
    } catch (e) {
      print('Firebase initialization failed in test mode: $e');
    }
  });
}
