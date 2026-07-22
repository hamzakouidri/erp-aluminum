import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:database_data/Screen/subscription_checker.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'settings/app_settings.dart';
import 'settings/localization.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _workshopNameController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;
  bool _isLoginMode = true;
  bool _isWorkerSignup = false;
  final _workshopCodeController = TextEditingController();

  late AnimationController _animationController;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rand = Random();
    _particles = List.generate(20, (index) {
      return Particle(
        x: rand.nextDouble(),
        y: rand.nextDouble(),
        speed: 0.001 + rand.nextDouble() * 0.003,
        size: 3.0 + rand.nextDouble() * 9.0,
        opacity: 0.05 + rand.nextDouble() * 0.15,
        angle: rand.nextDouble() * 2 * pi,
      );
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..addListener(() {
        if (mounted) {
          setState(() {
            for (var p in _particles) {
              p.y -= p.speed;
              p.x += sin(p.angle) * 0.0005;
              if (p.y < -0.05) {
                p.y = 1.05;
                p.x = Random().nextDouble();
              }
            }
          });
        }
      })..repeat();
  }

  String _getFriendlyErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح، يرجى كتابته بشكل صحيح.';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب من قبل الإدارة.';
      case 'user-not-found':
        return 'لم يتم العثور على حساب بهذا البريد، تأكد من صحته.';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة، يرجى المحاولة مرة أخرى.';
      case 'invalid-credential':
        return 'بيانات الدخول غير صحيحة، يرجى التأكد من البريد وكلمة المرور.';
      case 'email-already-in-use':
        return 'هذا البريد الإلكتروني مسجل لدينا بالفعل، جرب تسجيل الدخول.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة جداً، يرجى استخدام 6 أحرف أو أكثر.';
      case 'operation-not-allowed':
        return 'طريقة تسجيل الدخول هذه غير مفعلة في لوحة التحكم (يرجى تفعيل Email/Password).';
      case 'network-request-failed':
        return 'لا يوجد اتصال بالإنترنت، يرجى التحقق من الشبكة الخاصة بك.';
      case 'internal-error':
        return 'إعدادات غير مكتملة: يرجى الذهاب إلى Firebase Console -> قسم Authentication -> واضغط على Get Started ثم قم بتفعيل Email/Password.';
      default:
        if (e.message?.contains('configuration not found') ?? false) {
          return 'إعدادات المصادقة غير موجودة: يرجى الذهاب إلى Firebase Console -> قسم Authentication وتفعيل البريد الإلكتروني (Email/Password).';
        }
        return 'حدث خطأ: ${e.message}';
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى كتابة البريد الإلكتروني أولاً لإرسال رابط استعادة كلمة المرور.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك الإلكتروني بنجاح. يرجى مراجعة علبة الوارد.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found') {
          _errorMessage = 'لم يتم العثور على حساب بهذا البريد الإلكتروني. يرجى التحقق من صحته.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'البريد الإلكتروني المكتوب غير صالح.';
        } else {
          _errorMessage = 'حدث خطأ: ${e.message}';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ غير متوقع: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (userCredential.user!.email == 'kouidrihamza45@gmail.com') {
        // Ensure Admin doc exists and is active
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'email': userCredential.user!.email,
              'role': 'admin',
              'subscriptionStatus': 'active',
              'isBlocked': false,
              'workshopId': 'admin_workshop',
            }, SetOptions(merge: true));
      } else {
        if (!doc.exists || (doc.data()?['isBlocked'] == true)) {
          await _auth.signOut();
          if (mounted) {
            setState(() {
              _errorMessage =
                  'عذراً، هذا الحساب محذوف أو تم إيقافه من قبل المدير.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Firebase auth state changes will handle transitioning the screen automatically
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    if (!_isWorkerSignup && _workshopNameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال اسم المصنع أو الورشة.';
        _isLoading = false;
      });
      return;
    }

    if (_isWorkerSignup && _workshopCodeController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال كود الورشة.';
        _isLoading = false;
      });
      return;
    }

    // تفريغ حقول كلمة المرور عند عدم التطابق لتحسين تجربة المستخدم
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'كلمتا المرور غير متطابقتين. يرجى التأكد.';
        _passwordController.clear();
        _confirmPasswordController.clear();
        _isLoading = false;
      });
      return;
    }

    if (!_isWorkerSignup) {
      final isTaken = await _isWorkshopNameTaken(_workshopNameController.text.trim());
      if (isTaken) {
        setState(() {
          _errorMessage = 'اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر فريد.';
          _isLoading = false;
        });
        return;
      }
    }

    UserCredential? userCredential;
    bool isNewAuthUser = false;
    try {
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      isNewAuthUser = true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          userCredential = await _auth.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          // Check if they already exist in Firestore
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .get();
          if (doc.exists) {
            setState(() {
              _errorMessage =
                  'هذا البريد الإلكتروني مسجل بالفعل. يرجى التوجه لتسجيل الدخول.';
              _isLoading = false;
            });
            return;
          }
          // If doc DOES NOT exist, it means Admin deleted them! We proceed to recreate their data.
        } catch (signInErr) {
          setState(() {
            _errorMessage =
                'هذا الحساب موجود مسبقاً، ولكن كلمة المرور غير صحيحة لتفعيله من جديد.';
            _isLoading = false;
          });
          return;
        }
      } else {
        setState(() {
          _errorMessage = e.message ?? 'حدث خطأ في التسجيل';
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ: $e';
        _isLoading = false;
      });
      return;
    }

    String? targetWorkshopId;
    String? workshopNameForWorker;

    if (_isWorkerSignup) {
      final code = _workshopCodeController.text.trim();
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('workshops')
            .where('joinCode', isEqualTo: code)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          if (isNewAuthUser) {
            await userCredential.user!.delete();
          } else {
            await _auth.signOut();
          }
          setState(() {
            _errorMessage = 'كود الورشة غير صحيح أو الورشة غير موجودة.';
            _isLoading = false;
          });
          return;
        }

        final workshopData =
            querySnapshot.docs.first.data() as Map<String, dynamic>? ?? {};
        targetWorkshopId = querySnapshot.docs.first.id;
        workshopNameForWorker = workshopData['name'] as String?;

        int maxWorkers = 3;
        if (workshopData.containsKey('maxWorkers') &&
            workshopData['maxWorkers'] != null) {
          final mw = workshopData['maxWorkers'];
          if (mw is num) {
            maxWorkers = mw.toInt();
          } else if (mw is String) {
            maxWorkers = int.tryParse(mw) ?? 3;
          }
        }

        if (maxWorkers != 999) {
          final workersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('workshopId', isEqualTo: targetWorkshopId)
              .get();

          int currentWorkers = 0;
          for (var doc in workersSnapshot.docs) {
            final d = doc.data() as Map<String, dynamic>? ?? {};
            if (d['role'] == 'worker') {
              currentWorkers++;
            }
          }

          if (currentWorkers >= maxWorkers) {
            if (isNewAuthUser) {
              await userCredential.user!.delete();
            } else {
              await _auth.signOut();
            }
            setState(() {
              _errorMessage =
                  'نعتذر، لقد وصلت هذه الورشة للحد الأقصى المسموح به من العمال ($maxWorkers). يرجى مراجعة مدير الورشة لترقية اشتراكه.';
              _isLoading = false;
            });
            return;
          }
        }
      } catch (e) {
        if (isNewAuthUser) {
          await userCredential.user!.delete();
        } else {
          await _auth.signOut();
        }
        setState(() {
          _errorMessage = 'حدث خطأ أثناء التحقق من الكود: $e';
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final uid = userCredential.user!.uid;

      String? logoUrl;
      if (!_isWorkerSignup) {
        final encodedName = Uri.encodeComponent(
          _workshopNameController.text.trim(),
        );
        logoUrl =
            'https://ui-avatars.com/api/?name=$encodedName&background=random&color=fff&size=256&font-size=0.4&bold=true';
      }

      if (_isWorkerSignup) {
        int currentWorkerCount = 0;
        try {
          final workersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('workshopId', isEqualTo: targetWorkshopId)
              .get();
          currentWorkerCount = workersSnapshot.docs.where((doc) {
            final data = doc.data();
            return data['role'] == 'worker';
          }).length;
        } catch (_) {}

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': _emailController.text.trim(),
          'role': 'worker',
          'workshopId': targetWorkshopId,
          'workshopName': workshopNameForWorker,
          'displayName': _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'العامل رقم ${currentWorkerCount + 1}',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final joinCode = _generateJoinCode();
        // Create workshop doc
        await FirebaseFirestore.instance
            .collection('workshops')
            .doc(uid)
            .set({
              'name': _workshopNameController.text.trim(),
              'managerUid': uid,
              'joinCode': joinCode,
              'createdAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));

        // Create user doc - تم الحفاظ على إعدادات التجربة كما طلبت (-1)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({
              'email': _emailController.text.trim(),
              'role': 'manager',
              'workshopId': uid,
              'workshopName': _workshopNameController.text.trim(),
              'displayName': _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'مدير الورشة',
              'logoUrl': logoUrl,
              'joinCode': joinCode,
              'createdAt': FieldValue.serverTimestamp(),
              'trialEndDate': DateTime.now()
                  .add(const Duration(days: -1))
                  .toIso8601String(),
              'isTrialActive': false,
              'subscriptionStatus': 'trialing',
            })
            .timeout(const Duration(seconds: 10));

        // Auto-download global catalog for new workshop
        try {
          await CloudSyncService().init();
          await CloudSyncService().downloadGlobalCatalog().timeout(
            const Duration(seconds: 30),
          );
        } catch (e) {
          debugPrint('Failed to auto-download global catalog: $e');
        }
      }

      // Firebase auth state changes will handle transitioning the screen automatically
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _isWorkshopNameTaken(String name) async {
    try {
      final nameCheck = await FirebaseFirestore.instance
          .collection('workshops')
          .where('name', isEqualTo: name)
          .get()
          .timeout(const Duration(seconds: 8));
      return nameCheck.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking workshop name: $e');
      try {
        final usersCheck = await FirebaseFirestore.instance
            .collection('users')
            .where('workshopName', isEqualTo: name)
            .get()
            .timeout(const Duration(seconds: 5));
        return usersCheck.docs.any((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return data?['role'] == 'manager';
        });
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 1. Validation check for signup before authentication
      if (!_isLoginMode) {
        if (!_isWorkerSignup && _workshopNameController.text.trim().isEmpty) {
          setState(() {
            _errorMessage = 'يرجى إدخال اسم المصنع أو الورشة.';
            _isLoading = false;
          });
          return;
        }

        if (!_isWorkerSignup) {
          final isTaken = await _isWorkshopNameTaken(_workshopNameController.text.trim());
          if (isTaken) {
            setState(() {
              _errorMessage = 'اسم الورشة محجوز وموجود مسبقاً! يرجى اختيار اسم آخر فريد.';
              _isLoading = false;
            });
            return;
          }
        }

        if (_isWorkerSignup && _workshopCodeController.text.trim().isEmpty) {
          setState(() {
            _errorMessage = 'يرجى إدخال كود الورشة.';
            _isLoading = false;
          });
          return;
        }
      }

      // 2. Trigger Google Sign-In
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 3. Sign in to Firebase with the credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'null-user',
          message: 'فشل الحصول على بيانات المستخدم من Google.',
        );
      }

      final uid = user.uid;
      final email = user.email ?? '';

      // 4. Firestore checking and logic
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (_isLoginMode) {
        // --- LOGIN MODE ---
        if (email == 'kouidrihamza45@gmail.com') {
          // Admin account check/auto-create
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'admin',
            'subscriptionStatus': 'active',
            'isBlocked': false,
            'workshopId': 'admin_workshop',
          }, SetOptions(merge: true));
        } else {
          if (!doc.exists) {
            // User does not exist, so they must register first!
            await _auth.signOut();
            await GoogleSignIn().signOut();
            setState(() {
              _errorMessage = 'لم يتم العثور على حساب مسجل لهذا البريد الإلكتروني. يرجى تبديل الوضع وإنشاء حساب جديد أولاً.';
              _isLoading = false;
            });
            return;
          }

          if (doc.data()?['isBlocked'] == true) {
            await _auth.signOut();
            await GoogleSignIn().signOut();
            setState(() {
              _errorMessage = 'عذراً، هذا الحساب محذوف أو تم إيقافه من قبل المدير.';
              _isLoading = false;
            });
            return;
          }
        }
      } else {
        // --- REGISTRATION MODE ---
        if (doc.exists) {
          // Account already exists in Firestore!
          setState(() {
            _errorMessage = 'هذا البريد الإلكتروني مسجل بالفعل. يرجى التوجه لتسجيل الدخول.';
            _isLoading = false;
          });
          return;
        }

        // Proceed to register
        String? targetWorkshopId;
        String? workshopNameForWorker;

        if (_isWorkerSignup) {
          final code = _workshopCodeController.text.trim();
          final querySnapshot = await FirebaseFirestore.instance
              .collection('workshops')
              .where('joinCode', isEqualTo: code)
              .limit(1)
              .get();

          if (querySnapshot.docs.isEmpty) {
            await _auth.signOut();
            await GoogleSignIn().signOut();
            setState(() {
              _errorMessage = 'كود الورشة غير صحيح أو الورشة غير موجودة.';
              _isLoading = false;
            });
            return;
          }

          final workshopData = querySnapshot.docs.first.data();
          targetWorkshopId = querySnapshot.docs.first.id;
          workshopNameForWorker = workshopData['name'] as String?;

          int maxWorkers = 3;
          if (workshopData.containsKey('maxWorkers') && workshopData['maxWorkers'] != null) {
            final mw = workshopData['maxWorkers'];
            if (mw is num) {
              maxWorkers = mw.toInt();
            } else if (mw is String) {
              maxWorkers = int.tryParse(mw) ?? 3;
            }
          }

          int currentWorkers = 0;
          try {
            final workersSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('workshopId', isEqualTo: targetWorkshopId)
                .get();

            currentWorkers = workersSnapshot.docs.where((doc) {
              final d = doc.data();
              return d['role'] == 'worker';
            }).length;
          } catch (e) {
            debugPrint('Failed to count workers: $e');
          }

          if (maxWorkers != 999) {
            if (currentWorkers >= maxWorkers) {
              await _auth.signOut();
              await GoogleSignIn().signOut();
              setState(() {
                _errorMessage = 'نعتذر، لقد وصلت هذه الورشة للحد الأقصى المسموح به من العمال ($maxWorkers). يرجى مراجعة مدير الورشة لترقية اشتراكه.';
                _isLoading = false;
              });
              return;
            }
          }

          // Create Worker User
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'worker',
            'workshopId': targetWorkshopId,
            'workshopName': workshopNameForWorker,
            'displayName': user.displayName ?? 'العامل رقم ${currentWorkers + 1}',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Manager Signup
          final joinCode = _generateJoinCode();
          final workshopName = _workshopNameController.text.trim();
          final logoUrl = 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(workshopName)}&background=random&color=fff&size=256&font-size=0.4&bold=true';

          // Create workshop doc
          await FirebaseFirestore.instance.collection('workshops').doc(uid).set({
            'name': workshopName,
            'managerUid': uid,
            'joinCode': joinCode,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Create user doc
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'manager',
            'workshopId': uid,
            'workshopName': workshopName,
            'displayName': user.displayName ?? 'مدير الورشة',
            'logoUrl': logoUrl,
            'joinCode': joinCode,
            'createdAt': FieldValue.serverTimestamp(),
            'trialEndDate': DateTime.now().add(const Duration(days: -1)).toIso8601String(),
            'isTrialActive': false,
            'subscriptionStatus': 'trialing',
          });

          // Auto-download global catalog
          try {
            await CloudSyncService().init();
            await CloudSyncService().downloadGlobalCatalog().timeout(
              const Duration(seconds: 30),
            );
          } catch (e) {
            debugPrint('Failed to auto-download global catalog: $e');
          }
        }
      }

      // Firebase auth state changes will handle transitioning the screen automatically
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء الاتصال بـ Google: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _workshopNameController.dispose();
    _workshopCodeController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0F2027),
              Color(0xFF203A43),
              Color(0xFF2C5364),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Floating Particles background
            Positioned.fill(
              child: CustomPaint(
                painter: ParticlePainter(_particles),
              ),
            ),
            
            // Login Form
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulsating Logo/Icon
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        final pulse = sin(_animationController.value * 2 * pi) * 0.05;
                        return Transform.scale(
                          scale: 1.0 + pulse,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blueAccent.withOpacity(0.1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.3 + pulse * 2),
                                  blurRadius: 20 + pulse * 100,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.cloud_sync,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      Localization.translate('ورشتي', settings.language),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      'نظام إدارة وتسيير ورش الألمنيوم الذكي',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Frosted Glassmorphism Card
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24.0),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                        child: Container(
                          padding: const EdgeInsets.all(28.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(24.0),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _isLoginMode ? 'تسجيل الدخول' : 'إنشاء حساب جديد',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              if (!_isLoginMode) ...[
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 10,
                                  children: [
                                    ChoiceChip(
                                      label: const Text(
                                        'إنشاء ورشة (مدير)',
                                        style: TextStyle(fontFamily: 'Cairo'),
                                      ),
                                      selected: !_isWorkerSignup,
                                      selectedColor: Colors.blueAccent,
                                      backgroundColor: Colors.white.withOpacity(0.08),
                                      labelStyle: TextStyle(
                                        color: !_isWorkerSignup ? Colors.white : Colors.white70,
                                      ),
                                      onSelected: (val) {
                                        setState(() {
                                          _isWorkerSignup = !val;
                                        });
                                      },
                                    ),
                                    ChoiceChip(
                                      label: const Text(
                                        'تسجيل كعامل',
                                        style: TextStyle(fontFamily: 'Cairo'),
                                      ),
                                      selected: _isWorkerSignup,
                                      selectedColor: Colors.blueAccent,
                                      backgroundColor: Colors.white.withOpacity(0.08),
                                      labelStyle: TextStyle(
                                        color: _isWorkerSignup ? Colors.white : Colors.white70,
                                      ),
                                      onSelected: (val) {
                                        setState(() {
                                          _isWorkerSignup = val;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                if (!_isWorkerSignup) ...[
                                  TextField(
                                    controller: _workshopNameController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: InputDecoration(
                                      labelText: 'اسم المصنع / الورشة',
                                      labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.04),
                                      prefixIcon: const Icon(Icons.storefront, color: Colors.white60),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  TextField(
                                    controller: _workshopCodeController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: InputDecoration(
                                      labelText: 'كود الورشة (ضروري)',
                                      labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.04),
                                      prefixIcon: const Icon(Icons.qr_code, color: Colors.white60),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                              ],

                              if (!_isLoginMode) ...[
                                TextField(
                                  controller: _nameController,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                  decoration: InputDecoration(
                                    labelText: 'الاسم الكامل',
                                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.04),
                                    prefixIcon: const Icon(Icons.person_outline, color: Colors.white60),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'البريد الإلكتروني',
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.04),
                                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.white60),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                  ),
                                ),
                              ),
                              if (!_isLoginMode) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Text(
                                    '⚠️ من الأفضل التسجيل ببريد إلكتروني حقيقي لتتمكن من استرجاع كلمة المرور في حال نسيانها.',
                                    style: TextStyle(
                                      color: Colors.amber.shade300,
                                      fontSize: 11,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'كلمة المرور',
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.04),
                                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.white60),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.white60,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              if (_isLoginMode) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: _resetPassword,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(50, 30),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'نسيت كلمة المرور؟',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              
                              if (!_isLoginMode) ...[
                                TextField(
                                  controller: _confirmPasswordController,
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                  decoration: InputDecoration(
                                    labelText: 'تأكيد كلمة المرور',
                                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.04),
                                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white60),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              
                              if (_errorMessage.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.12),
                                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.redAccent),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage,
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                              if (_isLoading)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8.0),
                                    child: CircularProgressIndicator(color: Colors.blueAccent),
                                  ),
                                )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _isLoginMode ? _login : _register,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 4,
                                      ),
                                      child: Text(
                                        _isLoginMode ? 'تسجيل الدخول' : 'إنشاء حساب',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    OutlinedButton(
                                      onPressed: _signInWithGoogle,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        backgroundColor: Colors.white.withOpacity(0.08),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.network(
                                            'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                                            height: 22,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Icon(Icons.g_mobiledata, size: 22, color: Colors.white),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            _isLoginMode
                                                ? 'الدخول باستخدام Google'
                                                : 'التسجيل باستخدام Google',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _isLoginMode = !_isLoginMode;
                                          _errorMessage = '';
                                        });
                                      },
                                      child: Text(
                                        _isLoginMode
                                            ? 'ليس لديك حساب؟ إنشاء حساب جديد'
                                            : 'لديك حساب بالفعل؟ تسجيل الدخول',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Particle Effect classes for Premium UI Animation
// ─────────────────────────────────────────────────────────────────────────────
class Particle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;
  double angle;

  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.angle,
  });
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;

  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var p in particles) {
      paint.color = Colors.white.withOpacity(p.opacity);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

