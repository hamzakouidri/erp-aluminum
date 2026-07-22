import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/sql_database.dart';

class FirebaseSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // 🟢 رفع البيانات من قاعدة البيانات المحلية (الهاتف) إلى Firebase
  Future<void> syncToCloud(SqlDatabase localDb) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("User not logged in");

    final userDoc = _firestore.collection('users').doc(uid);

    try {
      // Sync Clients
      final clients = await localDb.readClient();
      final clientBatch = _firestore.batch();
      for (var client in clients) {
        // [تم الإصلاح]: التحقق من صحة البيانات قبل الرفع
        if (client['id'] != null) {
          final docRef = userDoc
              .collection('Client')
              .doc(client['id'].toString());
          // [تم الإصلاح]: إزالة الحقول الحساسة قبل الرفع
          final sanitizedClient = _sanitizeData(client, [
            'password',
            'secret',
            'token',
          ]);
          clientBatch.set(docRef, sanitizedClient);
        }
      }
      await clientBatch.commit();

      // Sync Commandes
      final commandes = await localDb.readCommande();
      final commandeBatch = _firestore.batch();
      for (var commande in commandes) {
        if (commande['id'] != null) {
          final docRef = userDoc
              .collection('Commandes')
              .doc(commande['id'].toString());
          final sanitizedCommande = _sanitizeData(commande, [
            'password',
            'secret',
            'token',
          ]);
          commandeBatch.set(docRef, sanitizedCommande);
        }
      }
      await commandeBatch.commit();

      // Sync Achats
      final achats = await localDb.readAchats();
      final achatsBatch = _firestore.batch();
      for (var achat in achats) {
        if (achat['id'] != null) {
          final docRef = userDoc
              .collection('Achats')
              .doc(achat['id'].toString());
          final sanitizedAchat = _sanitizeData(achat, [
            'password',
            'secret',
            'token',
          ]);
          achatsBatch.set(docRef, sanitizedAchat);
        }
      }
      await achatsBatch.commit();

      // (يمكن إضافة باقي الجداول بنفس الطريقة مثل Colors, Series, Sections, الخ)

      // حفظ وقت آخر مزامنة
      await userDoc.set({
        'last_sync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('فشلت المزامنة مع السحابة: $e');
    }
  }

  // 🟢 تنزيل البيانات من Firebase إلى قاعدة البيانات المحلية
  Future<void> syncFromCloud(SqlDatabase localDb) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("User not logged in");

    final userDoc = _firestore.collection('users').doc(uid);
    final db = await localDb.db;
    if (db == null) throw Exception('Database not initialized');

    try {
      // Retrieve Clients
      final clientsSnapshot = await userDoc.collection('Client').get();
      for (var doc in clientsSnapshot.docs) {
        final data = doc.data();
        // [تم الإصلاح]: التحقق من صحة البيانات قبل الاستيراد
        if (data['id'] != null) {
          var res = await db.query(
            'Client',
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          if (res.isEmpty) {
            await db.insert('Client', data);
          } else {
            await db.update(
              'Client',
              data,
              where: 'id = ?',
              whereArgs: [data['id']],
            );
          }
        }
      }

      // Retrieve Commandes
      final commandesSnapshot = await userDoc.collection('Commandes').get();
      for (var doc in commandesSnapshot.docs) {
        final data = doc.data();
        if (data['id'] != null) {
          var res = await db.query(
            'Commandes',
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          if (res.isEmpty) {
            await db.insert('Commandes', data);
          } else {
            await db.update(
              'Commandes',
              data,
              where: 'id = ?',
              whereArgs: [data['id']],
            );
          }
        }
      }

      // Retrieve Achats
      final achatsSnapshot = await userDoc.collection('Achats').get();
      for (var doc in achatsSnapshot.docs) {
        final data = doc.data();
        if (data['id'] != null) {
          var res = await db.query(
            'Achats',
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          if (res.isEmpty) {
            await db.insert('Achats', data);
          } else {
            await db.update(
              'Achats',
              data,
              where: 'id = ?',
              whereArgs: [data['id']],
            );
          }
        }
      }
    } catch (e) {
      throw Exception('فشلت استعادة البيانات من السحابة: $e');
    }
  }

  // [تم الإصلاح]: دالة لتطهير البيانات من الحقول الحساسة
  Map<String, dynamic> _sanitizeData(
    Map<String, dynamic> data,
    List<String> sensitiveFields,
  ) {
    final sanitized = Map<String, dynamic>.from(data);
    for (final field in sensitiveFields) {
      sanitized.remove(field);
    }
    return sanitized;
  }
}
