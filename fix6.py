import sys

with open('lib/login_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = "import 'package:shared_preferences/shared_preferences.dart';\n" + content

# In _loginUser, after successful login, we need to fetch the user doc and save it to SharedPreferences
old_login = '''      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const Home()),
        );
      }'''

new_login = '''      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (userCredential.user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
        final prefs = await SharedPreferences.getInstance();
        if (doc.exists) {
          final data = doc.data()!;
          await prefs.setString('user_role', data['role'] ?? 'manager');
          await prefs.setString('workshop_code', data['workshopCode'] ?? userCredential.user!.uid);
        } else {
          // Default to manager if not found (legacy)
          await prefs.setString('user_role', 'manager');
          await prefs.setString('workshop_code', userCredential.user!.uid);
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const Home()),
        );
      }'''

content = content.replace(old_login, new_login)

with open('lib/login_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
