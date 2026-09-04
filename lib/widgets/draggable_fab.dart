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
  late Offset _dragStartOffset;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
    _dragStartOffset = _offset;
  }

  Offset _clampOffset(Offset offset, Size screenSize) {
    final maxX = (screenSize.width - 150.0).clamp(10.0, 500.0).toDouble();
    final maxY = (screenSize.height - 100.0).clamp(60.0, 1000.0).toDouble();
    return Offset(
      offset.dx.clamp(10.0, maxX).toDouble(),
      offset.dy.clamp(60.0, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        // A normal tap activates the button. Moving it requires an
        // intentional long press first, so a small finger movement cannot
        // make the button jump over the controls underneath it.
        onLongPressStart: (_) {
          _dragStartOffset = _offset;
          setState(() => _isDragging = true);
        },
        onLongPressMoveUpdate: (details) {
          setState(() {
            _offset = _clampOffset(
              _dragStartOffset + details.offsetFromOrigin,
              screenSize,
            );
          });
        },
        onLongPressEnd: (_) {
          setState(() => _isDragging = false);
        },
        onLongPressCancel: () => setState(() => _isDragging = false),
        child: AnimatedScale(
          scale: _isDragging ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Tooltip(
            message: 'اضغط مطولاً لتحريك الزر',
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
      ),
    );
  }
}
