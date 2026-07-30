import 'package:flutter/material.dart';
import '../models/note.dart';

class PaperPainter extends CustomPainter {
  final PaperStyle style;

  PaperPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case PaperStyle.blank:
        break;
      case PaperStyle.lined:
        _drawLined(canvas, size);
        break;
      case PaperStyle.grid:
        _drawGrid(canvas, size);
        break;
      case PaperStyle.twoColumn:
        _drawTwoColumn(canvas, size);
        break;
      case PaperStyle.dotted:
        _drawDotted(canvas, size);
        break;
    }
  }

  void _drawLined(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFDDE3F0)
      ..strokeWidth = 0.8;
    final margin = Paint()
      ..color = const Color(0xFFFFCDD2)
      ..strokeWidth = 1.2;
    for (double y = 44; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(const Offset(60, 0), Offset(60, size.height), margin);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFDDE3F0)
      ..strokeWidth = 0.7;
    const spacing = 32.0;
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  void _drawTwoColumn(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFDDE3F0)
      ..strokeWidth = 0.8;
    final divider = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 1.0;
    final redMargin = Paint()
      ..color = const Color(0xFFFFCDD2)
      ..strokeWidth = 1.0;
    final midX = size.width / 2;
    for (double y = 44; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), divider);
    canvas.drawLine(const Offset(40, 0), Offset(40, size.height), redMargin);
    canvas.drawLine(
        Offset(midX + 40, 0), Offset(midX + 40, size.height), redMargin);
  }

  void _drawDotted(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PaperPainter old) => old.style != style;
}