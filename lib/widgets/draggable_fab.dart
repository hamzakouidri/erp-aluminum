import 'package:flutter/material.dart';

class DraggableFloatingActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Offset initialOffset;

  const DraggableFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    this.initialOffset = const Offset(20, 220),
  });

  @override
  State<DraggableFloatingActionButton> createState() =>
      _DraggableFloatingActionButtonState();
}

class _DraggableFloatingActionButtonState
    extends State<DraggableFloatingActionButton> {
  late Offset _offset;
  bool _isDragging = false;

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
        onPanStart: (_) {
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          setState(() {
            double newX = _offset.dx + details.delta.dx;
            double newY = _offset.dy + details.delta.dy;

            newX = newX.clamp(10.0, (screenSize.width - 150.0).clamp(10.0, 500.0));
            newY = newY.clamp(60.0, (screenSize.height - 100.0).clamp(60.0, 1000.0));

            _offset = Offset(newX, newY);
          });
        },
        onPanEnd: (_) {
          setState(() => _isDragging = false);
        },
        child: AnimatedScale(
          scale: _isDragging ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: FloatingActionButton.extended(
            onPressed: () {
              if (!_isDragging) {
                widget.onPressed();
              }
            },
            backgroundColor: widget.backgroundColor,
            elevation: _isDragging ? 12 : 6,
            icon: Icon(widget.icon, color: Colors.white),
            label: Text(
              widget.label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
