import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/note.dart';
import 'paper_painter.dart';

enum DrawingTool {
  pen,
  highlighter,
  eraser,
  line,
  rectangle,
  circle,
  triangle,
  arrow,
  star,
  filledRectangle,
  filledCircle,
  filledTriangle,
}

class DrawingCanvas extends StatefulWidget {
  final NotePage page;
  final Color penColor;
  final double strokeWidth;
  final DrawingTool tool;
  final double opacity;
  final ValueChanged<NotePage> onPageChanged;

  const DrawingCanvas({
    super.key,
    required this.page,
    required this.penColor,
    required this.strokeWidth,
    required this.tool,
    required this.onPageChanged,
    this.opacity = 1.0,
  });

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  late List<DrawnPoint> _strokes;
  final List<List<DrawnPoint>> _history = [];

  Offset? _shapeStart;
  Offset? _shapeCurrent;
  Offset? _eraserPosition;

  ui.Image? _bgImage;
  String? _loadedBgKey;

  @override
  void initState() {
    super.initState();
    _strokes = List.from(widget.page.strokes);
    _loadBackground();
  }

  @override
  void didUpdateWidget(DrawingCanvas old) {
    super.didUpdateWidget(old);
    if (widget.page.id != old.page.id) {
      setState(() {
        _strokes = List.from(widget.page.strokes);
        _history.clear();
        _shapeStart = null;
        _shapeCurrent = null;
        _bgImage = null;
        _loadedBgKey = null;
      });
      _loadBackground();
    }
    if (widget.page.strokes.isEmpty && _strokes.isNotEmpty) {
      setState(() {
        _strokes = [];
        _history.clear();
      });
    }
  }

  Future<void> _loadBackground() async {
    final b64 = widget.page.backgroundImageBase64;
    if (b64 == null || b64 == _loadedBgKey) return;
    try {
      final bytes = base64Decode(b64);
      final codec =
          await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _bgImage = frame.image;
          _loadedBgKey = b64;
        });
      }
    } catch (e) {
      debugPrint('Background load error: $e');
    }
  }

  void _saveHistory() {
    _history.add(List.from(_strokes));
    if (_history.length > 60) _history.removeAt(0);
  }

  void _notify() {
    widget.page.strokes = List.from(_strokes);
    widget.onPageChanged(widget.page);
  }

  void undo() {
    if (_history.isEmpty) return;
    setState(() => _strokes = _history.removeLast());
    _notify();
  }

  bool get _isShape => _shapeTools.contains(widget.tool);

  static const _shapeTools = {
    DrawingTool.line,
    DrawingTool.rectangle,
    DrawingTool.circle,
    DrawingTool.triangle,
    DrawingTool.arrow,
    DrawingTool.star,
    DrawingTool.filledRectangle,
    DrawingTool.filledCircle,
    DrawingTool.filledTriangle,
  };

  Color get _effectiveColor =>
      widget.penColor.withOpacity(widget.opacity);
    
  double get _eraserRadius => widget.strokeWidth * 3 + 10;

  void _onPanStart(Offset pos) {
    _saveHistory();

    if (_isShape) {
      setState(() {
        _shapeStart = pos;
        _shapeCurrent = pos;
      });
    } else if (widget.tool == DrawingTool.eraser) {
      setState(() => _eraserPosition = pos);
      _eraseNear(pos);
    } else {
      _addFreePoint(pos);
    }
  }

  void _onPanUpdate(Offset pos) {
    if (_isShape) {
      setState(() => _shapeCurrent = pos);
    } else if (widget.tool == DrawingTool.eraser) {
      setState(() => _eraserPosition = pos);
      _eraseNear(pos);
    } else {
      _addFreePoint(pos);
    }
  }

  void _onPanEnd() {
    if (_isShape && _shapeStart != null && _shapeCurrent != null) {
      _commitShape(_shapeStart!, _shapeCurrent!);
      setState(() {
        _shapeStart = null;
        _shapeCurrent = null;
      });
    } else if (widget.tool == DrawingTool.eraser) {
      setState(() => _eraserPosition = null);
    } else {
      setState(() {
        _strokes.add(DrawnPoint(
          point: null,
          color: _effectiveColor,
          strokeWidth: widget.strokeWidth,
        ));
      });
      _notify();
    }
  }

  void _addFreePoint(Offset pos) {
    final isHL = widget.tool == DrawingTool.highlighter;

    final color = isHL
        ? widget.penColor.withOpacity(widget.opacity * 0.18)
        : _effectiveColor;

    final width = isHL ? widget.strokeWidth * 5 : widget.strokeWidth;

    setState(() {
      _strokes.add(DrawnPoint(
        point: pos,
        color: color,
        strokeWidth: width,
      ));
    });

    _notify();
  }

  void _commitShape(Offset s, Offset e) {
    final c = _effectiveColor;
    final w = widget.strokeWidth;
    final pts = <DrawnPoint>[];

    switch (widget.tool) {
      case DrawingTool.line:
        pts.addAll(_linePoints(s, e, c, w));
        break;
      case DrawingTool.arrow:
        pts.addAll(_arrowPoints(s, e, c, w));
        break;
      case DrawingTool.rectangle:
      case DrawingTool.filledRectangle:
        pts.addAll(_rectPoints(s, e, c, w));
        break;
      case DrawingTool.circle:
      case DrawingTool.filledCircle:
        pts.addAll(_ellipsePoints(s, e, c, w));
        break;
      case DrawingTool.triangle:
      case DrawingTool.filledTriangle:
        pts.addAll(_trianglePoints(s, e, c, w));
        break;
      case DrawingTool.star:
        pts.addAll(_starPoints(s, e, c, w));
        break;
      default:
        break;
    }

    setState(() => _strokes.addAll(pts));
    _notify();
  }

  List<DrawnPoint> _linePoints(Offset s, Offset e, Color c, double w) => [
        DrawnPoint(point: s, color: c, strokeWidth: w),
        DrawnPoint(point: e, color: c, strokeWidth: w),
        DrawnPoint(point: null, color: c, strokeWidth: w),
      ];

  List<DrawnPoint> _arrowPoints(Offset s, Offset e, Color c, double w) {
    final pts = <DrawnPoint>[];
    // Main line
    pts.add(DrawnPoint(point: s, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: e, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    // Arrowhead
    final angle = atan2(e.dy - s.dy, e.dx - s.dx);
    const headLen = 20.0;
    const headAngle = 0.45;
    final h1 = Offset(
      e.dx - headLen * cos(angle - headAngle),
      e.dy - headLen * sin(angle - headAngle),
    );
    final h2 = Offset(
      e.dx - headLen * cos(angle + headAngle),
      e.dy - headLen * sin(angle + headAngle),
    );
    pts.add(DrawnPoint(point: e, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: h1, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: e, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: h2, color: c, strokeWidth: w));
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    return pts;
  }

  List<DrawnPoint> _rectPoints(Offset s, Offset e, Color c, double w) {
    final pts = <DrawnPoint>[];
    for (final p in [s, Offset(e.dx, s.dy), e, Offset(s.dx, e.dy), s]) {
      pts.add(DrawnPoint(point: p, color: c, strokeWidth: w));
    }
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    return pts;
  }

  List<DrawnPoint> _ellipsePoints(Offset s, Offset e, Color c, double w) {
    final pts = <DrawnPoint>[];
    final cx = (s.dx + e.dx) / 2;
    final cy = (s.dy + e.dy) / 2;
    final rx = (e.dx - s.dx).abs() / 2;
    final ry = (e.dy - s.dy).abs() / 2;
    for (int i = 0; i <= 72; i++) {
      final a = 2 * pi * i / 72;
      pts.add(DrawnPoint(
        point: Offset(cx + rx * cos(a), cy + ry * sin(a)),
        color: c,
        strokeWidth: w,
      ));
    }
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    return pts;
  }

  List<DrawnPoint> _trianglePoints(Offset s, Offset e, Color c, double w) {
    final top = Offset((s.dx + e.dx) / 2, s.dy);
    final bl = Offset(s.dx, e.dy);
    final br = Offset(e.dx, e.dy);
    final pts = <DrawnPoint>[];
    for (final p in [top, br, bl, top]) {
      pts.add(DrawnPoint(point: p, color: c, strokeWidth: w));
    }
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    return pts;
  }

  List<DrawnPoint> _starPoints(Offset s, Offset e, Color c, double w) {
    final pts = <DrawnPoint>[];
    final cx = (s.dx + e.dx) / 2;
    final cy = (s.dy + e.dy) / 2;
    final outerR = min((e.dx - s.dx).abs(), (e.dy - s.dy).abs()) / 2;
    final innerR = outerR * 0.4;
    const points = 5;
    Offset? first;
    for (int i = 0; i < points * 2; i++) {
      final angle = pi / points * i - pi / 2;
      final r = i.isEven ? outerR : innerR;
      final p = Offset(cx + r * cos(angle), cy + r * sin(angle));
      if (first == null) first = p;
      pts.add(DrawnPoint(point: p, color: c, strokeWidth: w));
    }
    if (first != null) {
      pts.add(DrawnPoint(point: first, color: c, strokeWidth: w));
    }
    pts.add(DrawnPoint(point: null, color: c, strokeWidth: w));
    return pts;
  }

  void _eraseNear(Offset touch) {
    // Uses toolbar pen size as eraser size.
    // This erases only the touched part, not the whole word/stroke.
    final r = _eraserRadius;
    final r2 = r * r;

    final newStrokes = <DrawnPoint>[];
    bool erasedAny = false;
    bool needBreak = false;

    for (final s in _strokes) {
      final p = s.point;

      // Keep existing stroke separators.
      if (p == null) {
        if (newStrokes.isNotEmpty && newStrokes.last.point != null) {
          newStrokes.add(s);
        }
        needBreak = false;
        continue;
      }

      final dx = p.dx - touch.dx;
      final dy = p.dy - touch.dy;
      final hit = dx * dx + dy * dy <= r2;

      if (hit) {
        erasedAny = true;
        needBreak = true;
        continue;
      }

      // Add separator after erased area, so remaining line does not reconnect.
      if (needBreak) {
        if (newStrokes.isNotEmpty && newStrokes.last.point != null) {
          newStrokes.add(DrawnPoint(
            point: null,
            color: s.color,
            strokeWidth: s.strokeWidth,
          ));
        }
        needBreak = false;
      }

      newStrokes.add(s);
    }

    if (!erasedAny) return;

    setState(() {
      _strokes = newStrokes;
    });

    _notify();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.page.hasPdfBackground && _bgImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onPanStart: (d) => _onPanStart(d.localPosition),
      onPanUpdate: (d) => _onPanUpdate(d.localPosition),
      onPanEnd: (_) => _onPanEnd(),
      child: CustomPaint(
        painter: _CanvasPainter(
          strokes: _strokes,
          bgImage: _bgImage,
          shapeStart: _shapeStart,
          shapeCurrent: _shapeCurrent,
          tool: widget.tool,
          previewColor: _effectiveColor,
          previewWidth: widget.strokeWidth,
          paperStyle: widget.page.paperStyle,
          eraserPosition: _eraserPosition,
          eraserRadius: _eraserRadius,
        ),
        size: Size.infinite,
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<DrawnPoint> strokes;
  final ui.Image? bgImage;
  final Offset? shapeStart;
  final Offset? shapeCurrent;
  final DrawingTool tool;
  final Color previewColor;
  final double previewWidth;
  final PaperStyle paperStyle;
  final Offset? eraserPosition;
  final double eraserRadius;

  _CanvasPainter({
    required this.strokes,
    required this.bgImage,
    required this.shapeStart,
    required this.shapeCurrent,
    required this.tool,
    required this.previewColor,
    required this.previewWidth,
    required this.paperStyle,
    required this.eraserPosition,
    required this.eraserRadius,
  });

  static const _filledTools = {
    DrawingTool.filledRectangle,
    DrawingTool.filledCircle,
    DrawingTool.filledTriangle,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (bgImage != null) {
      final src = Rect.fromLTWH(
          0, 0, bgImage!.width.toDouble(), bgImage!.height.toDouble());
      canvas.drawImageRect(bgImage!, src,
          Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    } else {
      PaperPainter(paperStyle).paint(canvas, size);
    }

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < strokes.length - 1; i++) {
      final curr = strokes[i];
      final next = strokes[i + 1];
      if (curr.point == null || next.point == null) continue;
      paint.color = curr.color;
      paint.strokeWidth = curr.strokeWidth;
      canvas.drawLine(curr.point!, next.point!, paint);
    }

    // Shape preview
    if (shapeStart != null && shapeCurrent != null) {
      final isFilled = _filledTools.contains(tool);
      final prev = Paint()
        ..color = previewColor.withOpacity(isFilled ? 0.3 : 0.55)
        ..strokeWidth = previewWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style =
            isFilled ? PaintingStyle.fill : PaintingStyle.stroke;

      final s = shapeStart!;
      final e = shapeCurrent!;

      switch (tool) {
        case DrawingTool.line:
          canvas.drawLine(s, e, prev);
          break;
        case DrawingTool.rectangle:
        case DrawingTool.filledRectangle:
          canvas.drawRect(Rect.fromPoints(s, e), prev);
          if (isFilled) {
            canvas.drawRect(
                Rect.fromPoints(s, e),
                Paint()
                  ..color = previewColor
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = previewWidth);
          }
          break;
        case DrawingTool.circle:
        case DrawingTool.filledCircle:
          canvas.drawOval(Rect.fromPoints(s, e), prev);
          break;
        case DrawingTool.triangle:
        case DrawingTool.filledTriangle:
          final path = Path()
            ..moveTo((s.dx + e.dx) / 2, s.dy)
            ..lineTo(e.dx, e.dy)
            ..lineTo(s.dx, e.dy)
            ..close();
          canvas.drawPath(path, prev);
          break;
        case DrawingTool.arrow:
          canvas.drawLine(s, e, prev);
          final angle = atan2(e.dy - s.dy, e.dx - s.dx);
          const hl = 20.0, ha = 0.45;
          canvas.drawLine(
              e,
              Offset(e.dx - hl * cos(angle - ha),
                  e.dy - hl * sin(angle - ha)),
              prev);
          canvas.drawLine(
              e,
              Offset(e.dx - hl * cos(angle + ha),
                  e.dy - hl * sin(angle + ha)),
              prev);
          break;
        case DrawingTool.star:
          final cx = (s.dx + e.dx) / 2;
          final cy = (s.dy + e.dy) / 2;
          final outerR =
              min((e.dx - s.dx).abs(), (e.dy - s.dy).abs()) / 2;
          final innerR = outerR * 0.4;
          final path = Path();
          for (int i = 0; i < 10; i++) {
            final angle = pi / 5 * i - pi / 2;
            final r = i.isEven ? outerR : innerR;
            final p = Offset(cx + r * cos(angle), cy + r * sin(angle));
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          path.close();
          canvas.drawPath(path, prev);
          break;
        default:
          break;
      }
    }
    if (eraserPosition != null) {
      final fill = Paint()
        ..color = Colors.black.withOpacity(0.08)
        ..style = PaintingStyle.fill;

      final border = Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(eraserPosition!, eraserRadius, fill);
      canvas.drawCircle(eraserPosition!, eraserRadius, border);
    }
  }
  
  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}