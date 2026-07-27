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
        if (client['id'] != null) {
          final docRef = userDoc
              .collection('Client')
              .doc(client['id'].toString());
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

      // Sync Colors
      final colors = await localDb.readColors();
      final colorsBatch = _firestore.batch();
      for (var color in colors) {
        if (color['id'] != null) {
          final docRef = userDoc
              .collection('Colors')
              .doc(color['id'].toString());
          colorsBatch.set(docRef, color);
        }
      }
      await colorsBatch.commit();

      // Sync ShutterComponents
      final shutterComps = await localDb.readShutterComponents(includeInactive: true);
      final shutterBatch = _firestore.batch();
      for (var comp in shutterComps) {
        if (comp['id'] != null) {
          final docRef = userDoc
              .collection('ShutterComponents')
              .doc(comp['id'].toString());
          shutterBatch.set(docRef, comp);
        }
      }
      await shutterBatch.commit();

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

      // Retrieve Colors from Cloud
      final colorsSnapshot = await userDoc.collection('Colors').get();
      for (var doc in colorsSnapshot.docs) {
        final data = doc.data();
        if (data['id'] != null) {
          var res = await db.query(
            'Colors',
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          if (res.isEmpty) {
            await db.insert('Colors', data);
          } else {
            await db.update(
              'Colors',
              data,
              where: 'id = ?',
              whereArgs: [data['id']],
            );
          }
        }
      }

      // Retrieve ProfileColors from Cloud
      final profileColorsSnapshot = await userDoc.collection('ProfileColors').get();
      for (var doc in profileColorsSnapshot.docs) {
        final data = doc.data();
        if (data['profile_id'] != null && data['color_id'] != null) {
          var res = await db.query(
            'ProfileColors',
            where: 'profile_id = ? AND color_id = ?',
            whereArgs: [data['profile_id'], data['color_id']],
          );
          if (res.isEmpty) {
            await db.insert('ProfileColors', data);
          }
        }
      }

      // Retrieve ShutterComponents from Cloud
      final shutterSnapshot = await userDoc.collection('ShutterComponents').get();
      for (var doc in shutterSnapshot.docs) {
        final data = doc.data();
        if (data['id'] != null) {
          var res = await db.query(
            'ShutterComponents',
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          if (res.isEmpty) {
            await db.insert('ShutterComponents', data);
          } else {
            await db.update(
              'ShutterComponents',
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

