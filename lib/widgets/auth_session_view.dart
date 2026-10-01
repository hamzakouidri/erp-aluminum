import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Replaces the entire navigation tree when the signed-in account changes.
/// Updating only MaterialApp.home leaves pushed workspace routes above login.
class AuthSessionView extends StatelessWidget {
  const AuthSessionView({
    super.key,
    required this.authStateChanges,
    required this.initialUser,
    required this.builder,
  });

  final Stream<AppAuthUser?> authStateChanges;
  final AppAuthUser? initialUser;
  final Widget Function(BuildContext, AppAuthUser?) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<AppAuthUser?>(
    stream: authStateChanges,
    initialData: initialUser,
    builder: (context, snapshot) => KeyedSubtree(
      key: ValueKey(snapshot.data?.uid),
      child: builder(context, snapshot.data),
    ),
  );
}
