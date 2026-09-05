import 'dart:async';
import 'package:flutter/widgets.dart';

/// Enforces the saved deadline locally, including after device sleep.
class SubscriptionDeadline extends StatefulWidget {
  const SubscriptionDeadline({super.key, required this.endsAt,
    required this.child, required this.expired});
  final DateTime? endsAt;
  final Widget child;
  final Widget expired;
  @override
  State<SubscriptionDeadline> createState() => _SubscriptionDeadlineState();
}

class _SubscriptionDeadlineState extends State<SubscriptionDeadline>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _expired = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }
  @override
  void didUpdateWidget(SubscriptionDeadline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) _schedule();
  }
  void _schedule() {
    _timer?.cancel();
    final remaining = widget.endsAt?.difference(DateTime.now());
    _expired = remaining != null && remaining <= Duration.zero;
    if (remaining != null && !_expired) {
      _timer = Timer(remaining, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(_schedule);
  }
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => _expired ? widget.expired : widget.child;
}
