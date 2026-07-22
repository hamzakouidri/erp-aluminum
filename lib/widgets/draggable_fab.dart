import 'package:flutter/material.dart';

class DraggableFloatingActionButton extends StatefulWidget {
  final Widget child;
  final Offset initialOffset;

  const DraggableFloatingActionButton({
    super.key,
    required this.child,
    this.initialOffset = const Offset(20, 150),
  });

  @override
  State<DraggableFloatingActionButton> createState() =>
      _DraggableFloatingActionButtonState();
}

class _DraggableFloatingActionButtonState
    extends State<DraggableFloatingActionButton> {
  late Offset _offset;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newX = _offset.dx + details.delta.dx;
            double newY = _offset.dy + details.delta.dy;

            // Keep FAB within screen bounds safely
            newX = newX.clamp(10.0, (screenSize.width - 150.0).clamp(10.0, 500.0));
            newY = newY.clamp(60.0, (screenSize.height - 120.0).clamp(60.0, 1000.0));

            _offset = Offset(newX, newY);
          });
        },
        child: Material(
          type: MaterialType.transparency,
          child: widget.child,
        ),
      ),
    );
  }
}
