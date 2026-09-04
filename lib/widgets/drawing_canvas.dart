import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/clipboard_image_service.dart';
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
  selectRectangle,
  selectLasso,
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

  final GlobalKey _repaintKey = GlobalKey();
  final Set<int> _selectedPointIndices = <int>{};
  List<Offset> _selectionPath = <Offset>[];
  Rect? _selectionBounds;
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  Offset? _lastMovePosition;
  bool _movingSelection = false;
  bool _copyingSelection = false;

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
        _selectedPointIndices.clear();
        _selectionPath = <Offset>[];
        _selectionBounds = null;
        _selectionStart = null;
        _selectionCurrent = null;
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
    if (old.tool != widget.tool &&
        (_isSelectionToolValue(old.tool) ||
            _isSelectionToolValue(widget.tool))) {
      _selectedPointIndices.clear();
      _selectionPath = <Offset>[];
      _selectionBounds = null;
      _selectionStart = null;
      _selectionCurrent = null;
      _lastMovePosition = null;
      _movingSelection = false;
    }
  }

  Future<void> _loadBackground() async {
    final b64 = widget.page.backgroundImageBase64;
    if (b64 == null || b64 == _loadedBgKey) return;
    try {
      final bytes = base64Decode(b64);
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
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
    setState(() {
      _strokes = _history.removeLast();
      _selectedPointIndices.clear();
      _selectionPath = <Offset>[];
      _selectionBounds = null;
      _selectionStart = null;
      _selectionCurrent = null;
    });
    _notify();
  }

  bool get _isShape => _shapeTools.contains(widget.tool);
  bool get _isSelectionTool => _isSelectionToolValue(widget.tool);
  Rect? get _visibleSelectionBounds {
    if (_selectionBounds != null) return _selectionBounds;
    if (_selectionStart != null && _selectionCurrent != null) {
      return Rect.fromPoints(_selectionStart!, _selectionCurrent!);
    }
    if (_selectionPath.isNotEmpty) return _boundsForPoints(_selectionPath);
    return null;
  }

  static bool _isSelectionToolValue(DrawingTool tool) =>
      tool == DrawingTool.selectRectangle || tool == DrawingTool.selectLasso;

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

  Color get _effectiveColor => widget.penColor.withOpacity(widget.opacity);

  double get _eraserRadius => widget.strokeWidth * 3 + 10;

  void _onPanStart(Offset pos) {
    if (_isSelectionTool) {
      _onSelectionStart(pos);
      return;
    }
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
    if (_isSelectionTool) {
      _onSelectionUpdate(pos);
      return;
    }
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
    if (_isSelectionTool) {
      _onSelectionEnd();
      return;
    }
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

  void _onSelectionStart(Offset position) {
    if (_selectionContains(position) && _selectedPointIndices.isNotEmpty) {
      _saveHistory();
      setState(() {
        _movingSelection = true;
        _lastMovePosition = position;
      });
      return;
    }

    setState(() {
      _selectedPointIndices.clear();
      _selectionStart = position;
      _selectionCurrent = position;
      _selectionPath = <Offset>[position];
      _selectionBounds = null;
      _movingSelection = false;
      _lastMovePosition = null;
    });
  }

  void _onSelectionUpdate(Offset position) {
    if (_movingSelection) {
      final previous = _lastMovePosition;
      if (previous == null) return;
      final delta = position - previous;
      if (delta == Offset.zero) return;
      setState(() {
        for (final index in _selectedPointIndices) {
          final item = _strokes[index];
          if (item.point == null) continue;
          _strokes[index] = DrawnPoint(
            point: item.point! + delta,
            color: item.color,
            strokeWidth: item.strokeWidth,
          );
        }
        _selectionPath = _selectionPath.map((point) => point + delta).toList();
        _selectionBounds = _selectionBounds?.shift(delta);
        _selectionStart =
            _selectionStart == null ? null : _selectionStart! + delta;
        _selectionCurrent =
            _selectionCurrent == null ? null : _selectionCurrent! + delta;
        _lastMovePosition = position;
      });
      _notify();
      return;
    }

    setState(() {
      _selectionCurrent = position;
      if (widget.tool == DrawingTool.selectLasso) {
        _selectionPath.add(position);
      }
    });
  }

  void _onSelectionEnd() {
    if (_movingSelection) {
      setState(() {
        _movingSelection = false;
        _lastMovePosition = null;
      });
      _notify();
      return;
    }

    final start = _selectionStart;
    final current = _selectionCurrent;
    if (start == null || current == null) return;

    if (widget.tool == DrawingTool.selectRectangle) {
      final rect = Rect.fromPoints(start, current);
      if (rect.width < 4 || rect.height < 4) {
        _clearSelection();
        return;
      }
      _selectionPath = <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ];
      _selectionBounds = rect;
    } else {
      if (_selectionPath.length < 3) {
        _clearSelection();
        return;
      }
      _selectionBounds = _boundsForPoints(_selectionPath);
    }

    _selectStrokeGroups();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedPointIndices.isEmpty
                ? 'Area selected. Long-press it to copy a screenshot.'
                : 'Drag inside to move handwriting. Long-press to copy or delete it.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _selectStrokeGroups() {
    _selectedPointIndices.clear();
    final group = <int>[];

    void finishGroup() {
      if (group.isEmpty) return;
      final selected = group.any((index) {
        final point = _strokes[index].point;
        return point != null && _pointInsideSelection(point);
      });
      if (selected) _selectedPointIndices.addAll(group);
      group.clear();
    }

    for (var index = 0; index < _strokes.length; index++) {
      if (_strokes[index].point == null) {
        finishGroup();
      } else {
        group.add(index);
      }
    }
    finishGroup();
  }

  bool _pointInsideSelection(Offset point) {
    final bounds = _selectionBounds;
    if (bounds == null || !bounds.contains(point)) return false;
    if (widget.tool == DrawingTool.selectRectangle) return true;
    return _pointInPolygon(point, _selectionPath);
  }

  bool _selectionContains(Offset point) {
    final bounds = _selectionBounds;
    if (bounds == null || !bounds.inflate(6).contains(point)) return false;
    if (widget.tool == DrawingTool.selectRectangle) return true;
    return _pointInPolygon(point, _selectionPath);
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  Rect _boundsForPoints(List<Offset> points) {
    var left = points.first.dx;
    var right = points.first.dx;
    var top = points.first.dy;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      left = min(left, point.dx);
      right = max(right, point.dx);
      top = min(top, point.dy);
      bottom = max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(() {
      _selectedPointIndices.clear();
      _selectionPath = <Offset>[];
      _selectionBounds = null;
      _selectionStart = null;
      _selectionCurrent = null;
      _lastMovePosition = null;
      _movingSelection = false;
    });
  }

  Future<void> _copySelection() async {
    final bounds = _selectionBounds;
    if (!_isSelectionTool || bounds == null || _copyingSelection) return;
    final renderObject = _repaintKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final canvasSize = renderObject.size;
    final safeBounds = bounds.intersect(Offset.zero & canvasSize);
    if (safeBounds.width < 2 || safeBounds.height < 2) return;

    setState(() => _copyingSelection = true);
    try {
      const scale = 2.0;
      final pixelWidth = max(1, (safeBounds.width * scale).ceil());
      final pixelHeight = max(1, (safeBounds.height * scale).ceil());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
        Paint()..color = Colors.white,
      );
      canvas.scale(scale);
      canvas.translate(-safeBounds.left, -safeBounds.top);

      if (widget.tool == DrawingTool.selectLasso) {
        final clip = Path()..addPolygon(_selectionPath, true);
        canvas.clipPath(clip);
      } else {
        canvas.clipRect(safeBounds);
      }

      _CanvasPainter(
        strokes: _strokes,
        bgImage: _bgImage,
        shapeStart: null,
        shapeCurrent: null,
        tool: widget.tool,
        previewColor: _effectiveColor,
        previewWidth: widget.strokeWidth,
        paperStyle: widget.page.paperStyle,
        eraserPosition: null,
        eraserRadius: _eraserRadius,
        selectionPath: const <Offset>[],
        selectionBounds: null,
        selectionTool: null,
      ).paint(canvas, canvasSize);

      final picture = recorder.endRecording();
      final image = await picture.toImage(pixelWidth, pixelHeight);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data == null) throw StateError('The selected image was empty.');
      await ClipboardImageService.writePngImage(data.buffer.asUint8List());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selection copied as an image. Paste it into GPT.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not copy the selection: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _copyingSelection = false);
    }
  }

  void _deleteSelection() {
    if (_selectedPointIndices.isEmpty) return;
    _saveHistory();

    final remaining = <DrawnPoint>[];
    for (var index = 0; index < _strokes.length; index++) {
      if (_selectedPointIndices.contains(index)) continue;
      final point = _strokes[index];
      if (point.point == null &&
          (remaining.isEmpty || remaining.last.point == null)) {
        continue;
      }
      remaining.add(point);
    }
    if (remaining.isNotEmpty && remaining.last.point == null) {
      remaining.removeLast();
    }

    setState(() {
      _strokes = remaining;
      _selectedPointIndices.clear();
      _selectionPath = <Offset>[];
      _selectionBounds = null;
      _selectionStart = null;
      _selectionCurrent = null;
      _lastMovePosition = null;
      _movingSelection = false;
    });
    _notify();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Selected handwriting deleted. You can use Undo to restore it.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmCopySelection() async {
    if (_selectionBounds == null || _copyingSelection) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Selected area'),
        content: const Text(
          'Copy this area as an image, or delete the selected handwriting?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: _selectedPointIndices.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, 'delete'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'copy'),
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy to clipboard'),
          ),
        ],
      ),
    );
    if (action == 'copy') await _copySelection();
    if (action == 'delete') _deleteSelection();
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
      onLongPressStart: _isSelectionTool && _selectionBounds != null
          ? (details) {
              if (_selectionContains(details.localPosition)) {
                _confirmCopySelection();
              }
            }
          : null,
      child: RepaintBoundary(
        key: _repaintKey,
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
            selectionPath: _selectionPath,
            selectionBounds: _visibleSelectionBounds,
            selectionTool: _isSelectionTool ? widget.tool : null,
          ),
          size: Size.infinite,
          child: Container(color: Colors.transparent),
        ),
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
  final List<Offset> selectionPath;
  final Rect? selectionBounds;
  final DrawingTool? selectionTool;

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
    required this.selectionPath,
    required this.selectionBounds,
    required this.selectionTool,
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
      canvas.drawImageRect(
          bgImage!, src, Rect.fromLTWH(0, 0, size.width, size.height), Paint());
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
        ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke;

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
              Offset(e.dx - hl * cos(angle - ha), e.dy - hl * sin(angle - ha)),
              prev);
          canvas.drawLine(
              e,
              Offset(e.dx - hl * cos(angle + ha), e.dy - hl * sin(angle + ha)),
              prev);
          break;
        case DrawingTool.star:
          final cx = (s.dx + e.dx) / 2;
          final cy = (s.dy + e.dy) / 2;
          final outerR = min((e.dx - s.dx).abs(), (e.dy - s.dy).abs()) / 2;
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

    if (selectionBounds != null && selectionTool != null) {
      final selectionPaint = Paint()
        ..color = const Color(0xFF6C63FF).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      final selectionBorder = Paint()
        ..color = const Color(0xFF6C63FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      if (selectionTool == DrawingTool.selectLasso &&
          selectionPath.length >= 3) {
        final path = Path()..addPolygon(selectionPath, true);
        canvas.drawPath(path, selectionPaint);
        canvas.drawPath(path, selectionBorder);
      } else {
        canvas.drawRect(selectionBounds!, selectionPaint);
        canvas.drawRect(selectionBounds!, selectionBorder);
      }

      final handlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final handleBorder = Paint()
        ..color = const Color(0xFF6C63FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final point in [
        selectionBounds!.topLeft,
        selectionBounds!.topRight,
        selectionBounds!.bottomLeft,
        selectionBounds!.bottomRight,
      ]) {
        canvas.drawCircle(point, 4.5, handlePaint);
        canvas.drawCircle(point, 4.5, handleBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}
