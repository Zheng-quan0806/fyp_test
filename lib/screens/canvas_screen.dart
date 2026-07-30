import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/notes_service.dart';
import '../services/file_import_service.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/toolbar_widget.dart';
import 'floating_chat_button.dart';

class CanvasScreen extends StatefulWidget {
  final Note note;
  const CanvasScreen({super.key, required this.note});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final _service = NotesService();
  final Map<String, GlobalKey<DrawingCanvasState>> _canvasKeys = {};

  Color _penColor = const Color(0xFF1A1A1A);
  double _strokeWidth = 3.0;
  double _opacity = 1.0;
  DrawingTool _tool = DrawingTool.pen;
  PaperStyle _paperStyle = PaperStyle.lined;
  bool _hasChanges = false;
  bool _importing = false;

  late List<NotePage> _pages;

  final ScrollController _scrollCtrl = ScrollController();
  int _currentPageIndex = 0;


  static const double _maxA4PageWidth = 794.0;
  static const double _a4HeightRatio = 297.0 / 210.0;
  static const double _pageGap = 16.0;

double _pageWidthForScreen(double screenWidth) {
  final available = screenWidth - 24;
  if (available > _maxA4PageWidth) return _maxA4PageWidth;
  return available;
}

double _pageHeightForWidth(double width) => width * _a4HeightRatio;

double _currentPageHeight() {
  final width = _pageWidthForScreen(MediaQuery.of(context).size.width);
  return _pageHeightForWidth(width);
}

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.note.pages);
    for (final p in _pages) {
      _canvasKeys[p.id] = GlobalKey<DrawingCanvasState>();
    }
    _paperStyle = _pages.first.paperStyle;
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

void _onScroll() {
  final pageHeight = _currentPageHeight();
  final idx = (_scrollCtrl.offset / (pageHeight + _pageGap))
      .round()
      .clamp(0, _pages.length - 1);
  if (idx != _currentPageIndex) setState(() => _currentPageIndex = idx);
}

  GlobalKey<DrawingCanvasState> _keyFor(String id) {
    _canvasKeys.putIfAbsent(id, () => GlobalKey<DrawingCanvasState>());
    return _canvasKeys[id]!;
  }

  void _onPageChanged(NotePage updated) {
    final idx = _pages.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      setState(() {
        _pages[idx] = updated;
        _hasChanges = true;
      });
    }
  }

  void _addPage() {
    final newPage = NotePage(id: const Uuid().v4(), paperStyle: _paperStyle);
    setState(() {
      _pages.insert(_currentPageIndex + 1, newPage);
      _hasChanges = true;
    });
    Future.delayed(const Duration(milliseconds: 100),
        () => _scrollToPage(_currentPageIndex + 1));
  }

  void _scrollToPage(int index) {
    final pageHeight = _currentPageHeight();
    _scrollCtrl.animateTo(
      index * (pageHeight + _pageGap),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _deletePage(int index) async {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the only page')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text('Delete page ${index + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _pages.removeAt(index);

      // Fix RangeError when deleting the last page
      if (_currentPageIndex >= _pages.length) {
        _currentPageIndex = _pages.length - 1;
      }

      // Keep paper style matched with the current page
      _paperStyle = _pages[_currentPageIndex].paperStyle;

      _hasChanges = true;
    });

  Future.delayed(
    const Duration(milliseconds: 100),
    () {
      if (mounted) {
        _scrollToPage(_currentPageIndex);
      }
    },
  );
}

  void _changePaperStyle(PaperStyle style) {
    setState(() {
      _paperStyle = style;
      final p = _pages[_currentPageIndex];
      if (!p.hasPdfBackground) {
        _pages[_currentPageIndex] = NotePage(
          id: p.id, strokes: p.strokes, paperStyle: style,
          backgroundImageBase64: p.backgroundImageBase64,
          sourceFileName: p.sourceFileName,
        );
      }
      _hasChanges = true;
    });
  }

  void _undo() =>
      _canvasKeys[_pages[_currentPageIndex].id]?.currentState?.undo();

  Future<void> _importFile() async {
  setState(() => _importing = true);
  try {
    final imported = await FileImportService.pickAndImport(context);
    if (imported.isEmpty) return;

    final replaceBlankPage = _pages.length == 1 &&
        _pages.first.strokes.isEmpty &&
        !_pages.first.hasPdfBackground;

    setState(() {
      if (replaceBlankPage) {
        // For a new empty note, replace the blank page so imported PDF/image
        // starts from page 1 instead of page 2.
        _pages = imported;
        _currentPageIndex = 0;
        _canvasKeys.clear();
      } else {
        // If the note already has content, keep existing pages and insert after
        // the current page to avoid deleting the user's work.
        _pages.insertAll(_currentPageIndex + 1, imported);
        _currentPageIndex = _currentPageIndex + 1;
      }

      for (final p in imported) {
        _canvasKeys[p.id] = GlobalKey<DrawingCanvasState>();
      }

      _paperStyle = _pages[_currentPageIndex].paperStyle;
      _hasChanges = true;
    });

    Future.delayed(
      const Duration(milliseconds: 150),
      () => _scrollToPage(_currentPageIndex),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${imported.length} page(s) imported!'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  } finally {
      if (mounted) {
    setState(() => _importing = false);
  }

  }
}

  Future<void> _clearCurrentPage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear page?'),
        content: const Text('All strokes will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final p = _pages[_currentPageIndex];
    setState(() {
      _pages[_currentPageIndex] = NotePage(
        id: p.id, paperStyle: p.paperStyle,
        backgroundImageBase64: p.backgroundImageBase64,
        sourceFileName: p.sourceFileName,
      );
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    widget.note.pages = _pages;
    widget.note.updatedAt = DateTime.now();
    final all = await _service.loadNotes();
    final idx = all.indexWhere((n) => n.id == widget.note.id);
    if (idx >= 0) {
      all[idx] = widget.note;
    } else {
      all.insert(0, widget.note);
    }
    await _service.saveNotes(all);
    setState(() => _hasChanges = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved!'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == 'save') await _save();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _onWillPop() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF12121E)
            : const Color(0xFFEEEEF4),
        appBar: _buildAppBar(isDark),

        body: Stack(
          children: [
            Column(children: [
              ToolbarWidget(
                selectedColor: _penColor,
                strokeWidth: _strokeWidth,
                selectedTool: _tool,
                paperStyle: _paperStyle,
                opacity: _opacity,
                onUndo: _undo,
                onColorChanged: (c) => setState(() {
                  _penColor = c;
                  if (_tool == DrawingTool.eraser) _tool = DrawingTool.pen;
                }),
                onStrokeWidthChanged: (w) => setState(() => _strokeWidth = w),
                onToolChanged: (t) => setState(() => _tool = t),
                onPaperStyleChanged: _changePaperStyle,
                onOpacityChanged: (v) => setState(() => _opacity = v),
              ),

              // Page info bar
              Container(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  Text(
                    'Page ${_currentPageIndex + 1} of ${_pages.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  if (_pages[_currentPageIndex].sourceFileName != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 13,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        _pages[_currentPageIndex].sourceFileName!,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ]),
              ),

              const Divider(height: 1),

              Expanded(
                child: Stack(children: [
                  _buildPageList(),
                  if (_importing)
                    Container(
                      color: Colors.black38,
                      child: const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 14),
                                Text('Rendering PDF pages…'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),

            const Positioned.fill(
              child: FloatingChatButton(),
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton.small(
          heroTag: 'addPage',
          onPressed: _addPage,
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          tooltip: 'Add page',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildPageList() {
      final screenWidth = MediaQuery.of(context).size.width;
      final pageWidth = _pageWidthForScreen(screenWidth);
      final pageHeight = _pageHeightForWidth(pageWidth);
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      itemCount: _pages.length,
      itemBuilder: (ctx, i) {
        final page = _pages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: _pageGap),
          child: Column(children: [
            // Page card
            Center(
                  child: Container(
                    width: pageWidth,
                    height: pageHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: DrawingCanvas(
                        key: _keyFor(page.id),
                        page: page,
                        penColor: _penColor,
                        strokeWidth: _strokeWidth,
                        tool: _tool,
                        opacity: _opacity,
                        onPageChanged: _onPageChanged,
                      ),
                    ),
                  ),
                ),
            // Page number + delete
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _scrollToPage(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: _currentPageIndex == i
                            ? const Color(0xFF6C63FF)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _currentPageIndex == i
                                ? Colors.white
                                : Colors.grey.shade600,
                          )),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _deletePage(i),
                    child: Icon(Icons.delete_outline,
                        size: 18, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  AppBar _buildAppBar(bool isDark) => AppBar(
    backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new),
      onPressed: () async {
        if (await _onWillPop() && mounted) Navigator.of(context).pop();
      },
    ),
    title: Text(widget.note.title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
    actions: [
      IconButton(
        icon: const Icon(Icons.file_open_outlined),
        tooltip: 'Import PDF / image',
        onPressed: _importFile,
      ),
      IconButton(
        icon: const Icon(Icons.layers_clear_outlined),
        tooltip: 'Clear current page',
        onPressed: _clearCurrentPage,
      ),
      if (_hasChanges)
        TextButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Save'),
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6C63FF)),
        ),
      const SizedBox(width: 4),
    ],
  );
}