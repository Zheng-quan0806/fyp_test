import 'package:flutter/material.dart';
import 'drawing_canvas.dart';
import '../models/note.dart';

class ToolbarWidget extends StatelessWidget {
  final Color selectedColor;
  final double strokeWidth;
  final DrawingTool selectedTool;
  final PaperStyle paperStyle;
  final double opacity;
  final VoidCallback onUndo;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<PaperStyle> onPaperStyleChanged;
  final ValueChanged<double> onOpacityChanged;

  const ToolbarWidget({
    super.key,
    required this.selectedColor,
    required this.strokeWidth,
    required this.selectedTool,
    required this.paperStyle,
    required this.onUndo,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onToolChanged,
    required this.onPaperStyleChanged,
    required this.onOpacityChanged,
    this.opacity = 1.0,
  });

  static const _sizes = [2.0, 4.0, 7.0, 12.0];

  // All shape tools grouped
  static const _shapeTools = [
    (DrawingTool.line, Icons.horizontal_rule, 'Line'),
    (DrawingTool.arrow, Icons.arrow_forward, 'Arrow'),
    (DrawingTool.rectangle, Icons.crop_square_outlined, 'Rect'),
    (DrawingTool.circle, Icons.circle_outlined, 'Circle'),
    (DrawingTool.triangle, Icons.change_history_outlined, 'Triangle'),
    (DrawingTool.star, Icons.star_outline, 'Star'),
    (DrawingTool.filledRectangle, Icons.crop_square, 'Filled Rect'),
    (DrawingTool.filledCircle, Icons.circle, 'Filled Circle'),
    (DrawingTool.filledTriangle, Icons.change_history, 'Filled △'),
  ];

  bool get _isShapeTool => _shapeTools.any((s) => s.$1 == selectedTool);
  bool get _isSelectionTool =>
      selectedTool == DrawingTool.selectRectangle ||
      selectedTool == DrawingTool.selectLasso;

  // Label for currently selected shape
  String get _shapeLabel {
    if (!_isShapeTool) return 'Shape';
    return _shapeTools.firstWhere((s) => s.$1 == selectedTool).$3;
  }

  IconData get _shapeIcon {
    if (!_isShapeTool) return Icons.category_outlined;
    return _shapeTools.firstWhere((s) => s.$1 == selectedTool).$2;
  }

  static const _quickColors = [
    Color(0xFF1A1A1A),
    Color(0xFFFFFFFF),
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF6B7280),
    Color(0xFF78350F),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1A2E)
            : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Row 1: Tools ────────────────────────────────────────
        SizedBox(
          height: 46,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              _iconBtn(Icons.undo, 'Undo', onUndo),
              _sep(),
              _toolBtn(Icons.edit, 'Pen', DrawingTool.pen),
              _toolBtn(
                  Icons.format_paint, 'Highlight', DrawingTool.highlighter),
              _toolBtn(
                  Icons.auto_fix_normal_outlined, 'Eraser', DrawingTool.eraser),
              _toolBtn(Icons.comment_outlined, 'Comment', DrawingTool.text),
              _sep(),
              _selectionDropdown(),
              _sep(),

              // ── Shapes dropdown ──────────────────────────────
              _shapesDropdown(context),

              _sep(),
              _paperBtn(context),
            ]),
          ),
        ),

        Divider(height: 1, thickness: 0.5, color: Colors.grey.shade100),

        // ── Row 2: Colors + sizes + opacity ─────────────────────
        SizedBox(
          height: 46,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              // Color picker button
              GestureDetector(
                onTap: () => _showColorPicker(context),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Stack(alignment: Alignment.center, children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF6C63FF), width: 2.5),
                      ),
                      child: ClipOval(
                          child: Container(
                              color: selectedColor.withOpacity(opacity))),
                    ),
                    const Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 7,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.colorize,
                            size: 10, color: Color(0xFF6C63FF)),
                      ),
                    ),
                  ]),
                ),
              ),

              // Quick colors
              ..._quickColors.map((c) => _quickColor(c)),
              _sep(),

              // Stroke widths
              ..._sizes.map((s) => _sizeBtn(s)),
              _sep(),

              // Opacity
              const Icon(Icons.opacity, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              SizedBox(
                width: 80,
                child: Slider(
                  value: opacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  activeColor: const Color(0xFF6C63FF),
                  onChanged: onOpacityChanged,
                ),
              ),
              Text('${(opacity * 100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Shapes grouped dropdown ──────────────────────────────────────────
  Widget _selectionDropdown() {
    final icon = selectedTool == DrawingTool.selectLasso
        ? Icons.gesture
        : Icons.select_all;
    final label = selectedTool == DrawingTool.selectLasso ? 'Lasso' : 'Select';
    return PopupMenuButton<DrawingTool>(
      tooltip: 'Select, move, or copy handwriting',
      onSelected: onToolChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: DrawingTool.selectRectangle,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.select_all),
            title: Text('Rectangle selection'),
            subtitle: Text('Drag a rectangular area'),
          ),
        ),
        PopupMenuItem(
          value: DrawingTool.selectLasso,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.gesture),
            title: Text('Freeform lasso'),
            subtitle: Text('Draw any selection shape'),
          ),
        ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color:
              _isSelectionTool ? const Color(0xFFEEEDFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                _isSelectionTool ? const Color(0xFF6C63FF) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            icon,
            size: 17,
            color: _isSelectionTool
                ? const Color(0xFF6C63FF)
                : Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  _isSelectionTool ? FontWeight.w600 : FontWeight.normal,
              color: _isSelectionTool
                  ? const Color(0xFF6C63FF)
                  : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: _isSelectionTool
                ? const Color(0xFF6C63FF)
                : Colors.grey.shade500,
          ),
        ]),
      ),
    );
  }

  Widget _shapesDropdown(BuildContext context) {
    return GestureDetector(
      onTap: () => _showShapePicker(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _isShapeTool ? const Color(0xFFEEEDFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isShapeTool ? const Color(0xFF6C63FF) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_shapeIcon,
              size: 17,
              color: _isShapeTool
                  ? const Color(0xFF6C63FF)
                  : Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(_shapeLabel,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      _isShapeTool ? FontWeight.w600 : FontWeight.normal,
                  color: _isShapeTool
                      ? const Color(0xFF6C63FF)
                      : Colors.grey.shade600)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down,
              size: 16,
              color: _isShapeTool
                  ? const Color(0xFF6C63FF)
                  : Colors.grey.shade500),
        ]),
      ),
    );
  }

  void _showShapePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Shapes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: _shapeTools.map((s) {
              final sel = selectedTool == s.$1;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onToolChanged(s.$1);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFEEEDFE) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? const Color(0xFF6C63FF) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s.$2,
                          size: 18,
                          color: sel
                              ? const Color(0xFF6C63FF)
                              : Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(s.$3,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  sel ? FontWeight.w600 : FontWeight.normal,
                              color: sel
                                  ? const Color(0xFF6C63FF)
                                  : Colors.grey.shade700)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, DrawingTool tool) {
    final sel = selectedTool == tool;
    return GestureDetector(
      onTap: () => onToolChanged(tool),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFEEEDFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? const Color(0xFF6C63FF) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 17,
              color: sel ? const Color(0xFF6C63FF) : Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                  color: sel ? const Color(0xFF6C63FF) : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon, size: 20, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _paperBtn(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPaperPicker(context),
      child: Container(
        margin: const EdgeInsets.only(left: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.article_outlined, size: 17, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(paperStyle.label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey.shade500),
        ]),
      ),
    );
  }

  Widget _quickColor(Color c) {
    final isSel = selectedColor == c;
    return GestureDetector(
      onTap: () {
        if (selectedTool == DrawingTool.eraser) {
          onToolChanged(DrawingTool.pen);
        }
        onColorChanged(c);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 6),
        width: isSel ? 28 : 22,
        height: isSel ? 28 : 22,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSel
                ? const Color(0xFF6C63FF)
                : c == Colors.white
                    ? Colors.grey.shade300
                    : Colors.transparent,
            width: isSel ? 2.5 : 1,
          ),
          boxShadow: isSel
              ? [BoxShadow(color: c.withOpacity(0.4), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }

  Widget _sizeBtn(double s) {
    final sel = strokeWidth == s;
    return GestureDetector(
      onTap: () => onStrokeWidthChanged(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 6),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFEEEDFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Container(
            width: 20,
            height: s.clamp(2.0, 12.0),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFF6C63FF) : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sep() => Container(
      width: 1,
      height: 24,
      color: Colors.grey.shade200,
      margin: const EdgeInsets.only(right: 6));

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ColorPickerSheet(
        current: selectedColor,
        opacity: opacity,
        onColorChanged: onColorChanged,
        onOpacityChanged: onOpacityChanged,
      ),
    );
  }

  void _showPaperPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PaperStylePicker(
        current: paperStyle,
        onSelected: (s) {
          Navigator.pop(context);
          onPaperStyleChanged(s);
        },
      ),
    );
  }
}

// ── Color picker sheet ─────────────────────────────────────────────────────
class _ColorPickerSheet extends StatefulWidget {
  final Color current;
  final double opacity;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onOpacityChanged;

  const _ColorPickerSheet({
    required this.current,
    required this.opacity,
    required this.onColorChanged,
    required this.onOpacityChanged,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Color _selected;
  late double _opacity;
  final List<Color> _history = [];

  static const _presets = [
    Color(0xFFFFCDD2),
    Color(0xFFFFCCBC),
    Color(0xFFFFF9C4),
    Color(0xFFC8E6C9),
    Color(0xFFB2EBF2),
    Color(0xFFBBDEFB),
    Color(0xFFE1BEE7),
    Color(0xFFD7CCC8),
    Color(0xFFEF9A9A),
    Color(0xFFFFAB91),
    Color(0xFFFFE082),
    Color(0xFFA5D6A7),
    Color(0xFF80DEEA),
    Color(0xFF90CAF9),
    Color(0xFFCE93D8),
    Color(0xFFBCAAA4),
    Color(0xFFEF5350),
    Color(0xFFFF7043),
    Color(0xFFFFCA28),
    Color(0xFF66BB6A),
    Color(0xFF26C6DA),
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFF8D6E63),
    Color(0xFFE53935),
    Color(0xFFF4511E),
    Color(0xFFFFB300),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF6D4C41),
    Color(0xFFB71C1C),
    Color(0xFFBF360C),
    Color(0xFFF57F17),
    Color(0xFF1B5E20),
    Color(0xFF006064),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFF3E2723),
    Color(0xFF1A1A1A),
    Color(0xFF424242),
    Color(0xFF757575),
    Color(0xFF9E9E9E),
    Color(0xFFBDBDBD),
    Color(0xFFE0E0E0),
    Color(0xFFF5F5F5),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _selected = widget.current;
    _opacity = widget.opacity;
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _pick(Color c) {
    setState(() {
      if (!_history.contains(c)) {
        _history.insert(0, c);
        if (_history.length > 16) _history.removeLast();
      }
      _selected = c;
    });
    widget.onColorChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          Row(children: [
            const Text('Color',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _selected.withOpacity(_opacity),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Presets'),
              Tab(text: 'Custom'),
              Tab(text: 'History')
            ],
            labelColor: const Color(0xFF6C63FF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF6C63FF),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              GridView.builder(
                controller: ctrl,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10),
                itemCount: _presets.length,
                itemBuilder: (_, i) {
                  final c = _presets[i];
                  final sel = _selected == c;
                  return GestureDetector(
                    onTap: () => _pick(c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel
                              ? const Color(0xFF6C63FF)
                              : c == Colors.white
                                  ? Colors.grey.shade300
                                  : Colors.transparent,
                          width: sel ? 3 : 1,
                        ),
                      ),
                      child: sel
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  );
                },
              ),
              _CustomColorTab(current: _selected, onChanged: _pick),
              _history.isEmpty
                  ? Center(
                      child: Text('No history yet',
                          style: TextStyle(color: Colors.grey.shade400)))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10),
                      itemCount: _history.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _pick(_history[i]),
                        child: Container(
                          decoration: BoxDecoration(
                              color: _history[i],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade300)),
                        ),
                      ),
                    ),
            ]),
          ),
          const Divider(height: 24),
          Row(children: [
            const Text('Opacity', style: TextStyle(fontSize: 14)),
            Expanded(
              child: Slider(
                value: _opacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                activeColor: const Color(0xFF6C63FF),
                onChanged: (v) {
                  setState(() => _opacity = v);
                  widget.onOpacityChanged(v);
                },
              ),
            ),
            Text('${(_opacity * 100).toInt()}%',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }
}

class _CustomColorTab extends StatefulWidget {
  final Color current;
  final ValueChanged<Color> onChanged;
  const _CustomColorTab({required this.current, required this.onChanged});

  @override
  State<_CustomColorTab> createState() => _CustomColorTabState();
}

class _CustomColorTabState extends State<_CustomColorTab> {
  late double _h, _s, _v;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.current);
    _h = hsv.hue;
    _s = hsv.saturation;
    _v = hsv.value;
  }

  Color get _color => HSVColor.fromAHSV(1, _h, _s, _v).toColor();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(
        child: Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
        ),
      ),
      _label('Hue'),
      Slider(
          value: _h,
          min: 0,
          max: 360,
          activeColor: HSVColor.fromAHSV(1, _h, 1, 1).toColor(),
          onChanged: (v) {
            setState(() => _h = v);
            widget.onChanged(_color);
          }),
      _label('Saturation'),
      Slider(
          value: _s,
          min: 0,
          max: 1,
          activeColor: _color,
          onChanged: (v) {
            setState(() => _s = v);
            widget.onChanged(_color);
          }),
      _label('Brightness'),
      Slider(
          value: _v,
          min: 0,
          max: 1,
          activeColor: _color,
          onChanged: (v) {
            setState(() => _v = v);
            widget.onChanged(_color);
          }),
    ]);
  }

  Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child:
          Text(t, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)));
}

class _PaperStylePicker extends StatelessWidget {
  final PaperStyle current;
  final ValueChanged<PaperStyle> onSelected;
  const _PaperStylePicker({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Paper Style',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: PaperStyle.values
              .map((s) => _PaperPreview(
                  style: s, selected: s == current, onTap: () => onSelected(s)))
              .toList(),
        ),
      ]),
    );
  }
}

class _PaperPreview extends StatelessWidget {
  final PaperStyle style;
  final bool selected;
  final VoidCallback onTap;
  const _PaperPreview(
      {required this.style, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 56,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF6C63FF) : Colors.grey.shade300,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [const BoxShadow(color: Color(0x446C63FF), blurRadius: 8)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: CustomPaint(painter: _MiniPaper(style)),
          ),
        ),
        const SizedBox(height: 6),
        Text(style.label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color:
                    selected ? const Color(0xFF6C63FF) : Colors.grey.shade600)),
      ]),
    );
  }
}

class _MiniPaper extends CustomPainter {
  final PaperStyle style;
  _MiniPaper(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFDDE3F0)
      ..strokeWidth = 0.6;
    switch (style) {
      case PaperStyle.blank:
        break;
      case PaperStyle.lined:
        for (double y = 8; y < size.height; y += 10) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        canvas.drawLine(
            const Offset(8, 0),
            Offset(8, size.height),
            Paint()
              ..color = const Color(0xFFFFCDD2)
              ..strokeWidth = 0.8);
        break;
      case PaperStyle.grid:
        for (double x = 8; x < size.width; x += 8) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (double y = 8; y < size.height; y += 8) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        break;
      case PaperStyle.twoColumn:
        for (double y = 8; y < size.height; y += 10) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        canvas.drawLine(
            Offset(size.width / 2, 0),
            Offset(size.width / 2, size.height),
            Paint()
              ..color = Colors.grey.shade400
              ..strokeWidth = 0.8);
        break;
      case PaperStyle.dotted:
        final dot = Paint()
          ..color = const Color(0xFFB0BEC5)
          ..style = PaintingStyle.fill;
        for (double x = 8; x < size.width; x += 8) {
          for (double y = 8; y < size.height; y += 8) {
            canvas.drawCircle(Offset(x, y), 0.8, dot);
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPaper old) => old.style != style;
}
