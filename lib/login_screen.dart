import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:database_data/Screen/subscription_checker.dart';
import 'package:database_data/services/cloud_sync_service.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  XFile? _selectedLogo;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedLogo = image;
      });
    }
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

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SubscriptionChecker()),
        );
      }
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
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
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

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'كلمتا المرور غير متطابقتين. يرجى التأكد.';
        _isLoading = false;
      });
      return;
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
          final doc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
          if (doc.exists) {
            setState(() {
              _errorMessage = 'هذا البريد الإلكتروني مسجل بالفعل. يرجى التوجه لتسجيل الدخول.';
              _isLoading = false;
            });
            return;
          }
          // If doc DOES NOT exist, it means Admin deleted them! We proceed to recreate their data.
        } catch (signInErr) {
          setState(() {
            _errorMessage = 'هذا الحساب موجود مسبقاً، ولكن كلمة المرور غير صحيحة لتفعيله من جديد.';
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
          if (isNewAuthUser) await userCredential.user!.delete(); else await _auth.signOut();
          setState(() {
            _errorMessage = 'كود الورشة غير صحيح أو الورشة غير موجودة.';
            _isLoading = false;
          });
          return;
        }
        
        final workshopData = querySnapshot.docs.first.data() as Map<String, dynamic>? ?? {};
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
            if (isNewAuthUser) await userCredential.user!.delete(); else await _auth.signOut();
            setState(() {
              _errorMessage = 'نعتذر، لقد وصلت هذه الورشة للحد الأقصى المسموح به من العمال ($maxWorkers). يرجى مراجعة مدير الورشة لترقية اشتراكه.';
              _isLoading = false;
            });
            return;
          }
        }
      } catch (e) {
        if (isNewAuthUser) await userCredential.user!.delete(); else await _auth.signOut();
        setState(() {
          _errorMessage = 'حدث خطأ أثناء التحقق من الكود: $e';
          _isLoading = false;
        });
        return;
      }
    }
    
    try {
      // Save user profile to Firestore with a 30-day trial
      final uid = userCredential.user!.uid;

      String? logoUrl;
      if (_selectedLogo != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('logos/${uid}_${DateTime.now().millisecondsSinceEpoch}.png');
          
          if (kIsWeb) {
            await storageRef.putData(await _selectedLogo!.readAsBytes());
          } else {
            await storageRef.putFile(File(_selectedLogo!.path));
          }
          logoUrl = await storageRef.getDownloadURL();
        } catch (e) {
          debugPrint("Failed to upload logo: $e");
        }
      }

      // إذا لم يقم العميل برفع شعار، نصنع له شعاراً مجانياً باستخدام أول حرفين من اسم الورشة!
      if (logoUrl == null && !_isWorkerSignup) {
        final encodedName = Uri.encodeComponent(_workshopNameController.text.trim());
        logoUrl = 'https://ui-avatars.com/api/?name=$encodedName&background=random&color=fff&size=256&font-size=0.4&bold=true';
      }

      if (_isWorkerSignup) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': _emailController.text.trim(),
          'role': 'worker',
          'workshopId': targetWorkshopId,
          'workshopName': workshopNameForWorker,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final joinCode = _generateJoinCode();
        // Create workshop doc
        await FirebaseFirestore.instance.collection('workshops').doc(uid).set({
          'name': _workshopNameController.text.trim(),
          'managerUid': uid,
          'joinCode': joinCode,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Create user doc
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': _emailController.text.trim(),
          'role': 'manager',
          'workshopId': uid,
          'workshopName': _workshopNameController.text.trim(),
          'logoUrl': logoUrl,
          'joinCode': joinCode,
          'createdAt': FieldValue.serverTimestamp(),
          'trialEndDate': DateTime.now().add(const Duration(days: -1)).toIso8601String(),
          'isTrialActive': false,
          'subscriptionStatus': 'trialing',
        });
        
        // Auto-download global catalog for new workshop
        try {
          await CloudSyncService().downloadGlobalCatalog();
        } catch (e) {
          debugPrint('Failed to auto-download global catalog: $e');
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SubscriptionChecker()),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isLoginMode ? 'تسجيل الدخول' : 'إنشاء حساب جديد'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Icon(Icons.cloud_sync, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            if (!_isLoginMode) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('إنشاء ورشة (مدير)'),
                    selected: !_isWorkerSignup,
                    onSelected: (val) {
                      setState(() {
                        _isWorkerSignup = !val;
                      });
                    },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('تسجيل كعامل'),
                    selected: _isWorkerSignup,
                    onSelected: (val) {
                      setState(() {
                        _isWorkerSignup = val;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!_isWorkerSignup) ...[
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blue.shade50,
                    backgroundImage: _selectedLogo != null
                        ? (kIsWeb
                            ? NetworkImage(_selectedLogo!.path)
                            : FileImage(File(_selectedLogo!.path))) as ImageProvider
                        : null,
                    child: _selectedLogo == null
                        ? const Icon(Icons.add_a_photo, size: 40, color: Colors.blue)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _workshopNameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المصنع / الورشة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storefront),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _workshopCodeController,
                  decoration: const InputDecoration(
                    labelText: 'كود الورشة (ضروري)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.qr_code),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_isLoginMode) ...[
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _isLoginMode ? _login : _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(_isLoginMode ? 'تسجيل الدخول' : 'إنشاء حساب', style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLoginMode = !_isLoginMode;
                        _errorMessage = '';
                      });
                    },
                    child: Text(_isLoginMode ? 'ليس لديك حساب؟ إنشاء حساب جديد' : 'لديك حساب بالفعل؟ تسجيل الدخول', style: const TextStyle(fontSize: 16)),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
