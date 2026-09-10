import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/notes_service.dart';
import '../services/file_import_service.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/toolbar_widget.dart';
import '../widgets/study_activity_region.dart';
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
  bool _saving = false;
  bool _saveAgain = false;
  bool _allowPop = false;
  bool _handlingClose = false;
  String? _saveError;
  int _changeRevision = 0;
  Timer? _autoSaveTimer;

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
    _autoSaveTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _markChanged() {
    if (!mounted) return;
    _hasChanges = true;
    _saveError = null;
    _changeRevision++;
    _scheduleAutoSave();
  }

  void _scheduleAutoSave([
    Duration delay = const Duration(milliseconds: 900),
  ]) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(delay, () {
      if (mounted) unawaited(_save());
    });
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
        _markChanged();
      });
    }
  }

  void _addPage() {
    final newPage = NotePage(id: const Uuid().v4(), paperStyle: _paperStyle);
    setState(() {
      _pages.insert(_currentPageIndex + 1, newPage);
      _markChanged();
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

      _markChanged();
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
          id: p.id,
          strokes: p.strokes,
          textBoxes: p.textBoxes,
          paperStyle: style,
          backgroundImageBase64: p.backgroundImageBase64,
          sourceFileName: p.sourceFileName,
        );
      }
      _markChanged();
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
        _markChanged();
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
        content:
            const Text('All handwriting, shapes, and text will be removed.'),
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
        id: p.id,
        paperStyle: p.paperStyle,
        backgroundImageBase64: p.backgroundImageBase64,
        sourceFileName: p.sourceFileName,
      );
      _markChanged();
    });
  }

  Future<bool> _save() async {
    if (!mounted) return false;
    _autoSaveTimer?.cancel();
    if (_saving) {
      _saveAgain = true;
      while (_saving) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!mounted) return false;
      }
      if (_hasChanges) return _save();
      return true;
    }

    final savingRevision = _changeRevision;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final savedNote = Note(
        id: widget.note.id,
        title: widget.note.title,
        pages: List<NotePage>.from(_pages),
        updatedAt: DateTime.now(),
        folderId: widget.note.folderId,
      );
      final cloudSynced = await _service.saveNote(savedNote);

      widget.note.pages = savedNote.pages;
      widget.note.updatedAt = savedNote.updatedAt;
      if (!mounted) return true;
      setState(() {
        if (savingRevision == _changeRevision) _hasChanges = false;
        _saveError = cloudSynced
            ? null
            : 'Saved on this device. Supabase synchronization will retry.';
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _saveError = error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-save failed: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_hasChanges && (_saveAgain || savingRevision != _changeRevision)) {
          _saveAgain = false;
          _scheduleAutoSave(const Duration(milliseconds: 350));
        }
      }
    }
  }

  Future<bool> _onWillPop() async {
    for (final key in _canvasKeys.values) {
      key.currentState?.finishTextEditing();
    }
    _autoSaveTimer?.cancel();
    if (!_hasChanges && !_saving) return true;
    final saved = await _save();
    return saved && !_hasChanges;
  }

  Future<void> _requestClose() async {
    if (_handlingClose || !mounted) return;
    _handlingClose = true;
    final canClose = await _onWillPop();
    if (!mounted) return;
    if (!canClose) {
      _handlingClose = false;
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StudyActivityRegion(
      child: PopScope<Object?>(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_requestClose());
        },
        child: Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF12121E) : const Color(0xFFEEEEF4),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    Text(
                      'Page ${_currentPageIndex + 1} of ${_pages.length}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
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
          onPressed: _requestClose,
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
          Tooltip(
            message: _saveError ?? 'Changes are saved automatically',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (_saving)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _saveError == null
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 18,
                      color: _saveError == null
                          ? const Color(0xFF6C63FF)
                          : Colors.red,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _saving
                        ? 'Saving...'
                        : _saveError != null
                            ? 'Sync pending'
                            : _hasChanges
                                ? 'Saving soon...'
                                : 'Auto-saved',
                    style: TextStyle(
                      color: _saveError == null
                          ? const Color(0xFF6C63FF)
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      );
}
