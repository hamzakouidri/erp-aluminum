import 'package:flutter/material.dart';

class MyCards extends StatelessWidget {
  final String? count;
  final String title;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool showAvatar;
  final Color color;

  const MyCards({
    super.key,
    this.icon,
    required this.title,
    this.count,
    this.onTap,
    this.showAvatar = true,
    this.color = Colors.blueAccent,
  });

  @override
  Widget build(BuildContext context) {
    // استخدمنا Container بـ width محدد أو اتركه ليتمدد حسب الأب
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Material(
        // Material ضروري لظهور تأثير النقر والظلال بشكل صحيح
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(width: 1, color: Colors.grey),
              color: color,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // هام جداً لكي لا يأخذ العمود الشاشة كلها
              children: [
                if (showAvatar)
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Icon(icon, color: Colors.blue),
                  )
                else
                  Icon(icon, size: 35, color: Colors.blue),

                const SizedBox(height: 10),

                if (count != null)
                  Text(
                    count!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black, // تأكد من أن اللون ليس أبيض
                    ),
                  ),

                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
