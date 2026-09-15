import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

class DoctorSignaturePad extends StatefulWidget {
  const DoctorSignaturePad({super.key});

  @override
  DoctorSignaturePadState createState() => DoctorSignaturePadState();
}

class DoctorSignaturePadState extends State<DoctorSignaturePad> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];

  bool get isEmpty => _strokes.isEmpty;

  List<List<List<double>>> get strokeData => _strokes
      .map((stroke) => stroke.map((point) => [point.dx, point.dy]).toList())
      .toList();

  void clear() => setState(_strokes.clear);

  Future<Uint8List?> exportPng() async {
    if (isEmpty) return null;
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  void _start(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox;
    setState(() => _strokes.add([box.globalToLocal(details.globalPosition)]));
  }

  void _draw(DragUpdateDetails details) {
    if (_strokes.isEmpty) return;
    final box = context.findRenderObject() as RenderBox;
    setState(
        () => _strokes.last.add(box.globalToLocal(details.globalPosition)));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _start,
        onPanUpdate: _draw,
        child: CustomPaint(
          painter: _SignaturePainter(_strokes),
          child: const SizedBox(width: double.infinity, height: 120),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  const _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFB8C5CC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      border,
    );
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.4
      ..color = const Color(0xFF18334A);
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.2, ink);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
