import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/notes_service.dart';
import 'canvas_screen.dart';
import 'floating_chat_button.dart';

class FolderScreen extends StatefulWidget {
  final NoteFolder folder;
  final List<Note> allNotes;
  final List<NoteFolder> allFolders;
  final VoidCallback onNotesChanged;

  const FolderScreen({
    super.key,
    required this.folder,
    required this.allNotes,
    required this.allFolders,
    required this.onNotesChanged,
  });

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final _service = NotesService();
  late List<Note> _allNotes;
  late List<Note> _folderNotes;
  late List<NoteFolder> _allFolders;
  late List<NoteFolder> _subFolders;
  bool _draggingOverRoot = false;
  String? _draggingOverFolderId;

  @override
  void initState() {
    super.initState();
    _refresh(widget.allNotes, widget.allFolders);
  }

  void _refresh(List<Note> allNotes, List<NoteFolder> allFolders) {
    _allNotes = allNotes;
    _allFolders = allFolders;
    _folderNotes = allNotes.where((n) => n.folderId == widget.folder.id).toList();
    _subFolders = allFolders
        .where((f) => f.parentFolderId == widget.folder.id)
        .toList();
  }

  List<Note> _notesInFolder(String folderId) =>
      _allNotes.where((n) => n.folderId == folderId).toList();

  List<NoteFolder> _subFoldersIn(String folderId) =>
      _allFolders.where((f) => f.parentFolderId == folderId).toList();

  Future<void> _reloadLocal() async {
    final notes = await _service.loadNotes();
    final folders = await _service.loadFolders();
    setState(() => _refresh(notes, folders));
    widget.onNotesChanged();
  }

  Future<void> _moveToRoot(Note note) async {
    final allNotes = await _service.loadNotes();
    final idx = allNotes.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      allNotes[idx] = Note(
        id: note.id,
        title: note.title,
        pages: note.pages,
        updatedAt: note.updatedAt,
        folderId: null,
      );
      await _service.saveNotes(allNotes);
    }
    await _reloadLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${note.title}" moved to root'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _moveNoteToFolder(Note note, NoteFolder folder) async {
    final allNotes = await _service.loadNotes();
    final idx = allNotes.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      allNotes[idx] = Note(
        id: note.id,
        title: note.title,
        pages: note.pages,
        updatedAt: note.updatedAt,
        folderId: folder.id,
      );
      await _service.saveNotes(allNotes);
    }
    setState(() => _draggingOverFolderId = null);
    await _reloadLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${note.title}" moved to "${folder.name}"'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showNewMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: widget.folder.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.note_add_outlined, color: widget.folder.color),
              ),
              title: const Text('New Note', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Create a note inside this folder'),
              onTap: () { Navigator.pop(context); _createNote(); },
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E0),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.folder_outlined, color: Color(0xFFFF8C00)),
              ),
              title: const Text('New Folder', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Create a folder inside this folder'),
              onTap: () { Navigator.pop(context); _createFolder(); },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _createNote() async {
    final ctrl = TextEditingController(text: 'Untitled Note');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New note'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Note title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;

    final note = Note(
      id: const Uuid().v4(),
      title: title,
      updatedAt: DateTime.now(),
      folderId: widget.folder.id,
    );
    final allNotes = await _service.loadNotes();
    allNotes.insert(0, note);
    await _service.saveNotes(allNotes);
    widget.onNotesChanged();

    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CanvasScreen(note: note)));
    await _reloadLocal();
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController(text: 'New Folder');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New sub-folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final folders = await _service.loadFolders();
    folders.insert(0, NoteFolder(
      id: const Uuid().v4(),
      name: name,
      colorHex: widget.folder.colorHex,
      createdAt: DateTime.now(),
      parentFolderId: widget.folder.id,
    ));
    await _service.saveFolders(folders);
    await _reloadLocal();
  }

  Future<void> _openNote(Note note) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CanvasScreen(note: note)));
    await _reloadLocal();
  }

  Future<void> _openFolder(NoteFolder folder) async {
    final notes = await _service.loadNotes();
    final folders = await _service.loadFolders();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderScreen(
          folder: folder,
          allNotes: notes,
          allFolders: folders,
          onNotesChanged: widget.onNotesChanged,
        ),
      ),
    );
    await _reloadLocal();
  }

  Future<void> _deleteNote(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('Delete "${note.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final allNotes = await _service.loadNotes();
    allNotes.removeWhere((n) => n.id == note.id);
    await _service.saveNotes(allNotes);
    await _reloadLocal();
  }

  Future<void> _deleteFolder(NoteFolder folder) async {
    final folders = await _service.loadFolders();
    final folderIds = <String>{folder.id};
    bool added = true;
    while (added) {
      added = false;
      for (final f in folders) {
        if (f.parentFolderId != null &&
            folderIds.contains(f.parentFolderId) &&
            folderIds.add(f.id)) {
          added = true;
        }
      }
    }

    final allNotes = await _service.loadNotes();
    final noteCount = allNotes.where((n) => folderIds.contains(n.folderId)).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text('Delete "${folder.name}"? $noteCount note(s) inside will move to current folder.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final updatedNotes = allNotes.map((n) {
      if (folderIds.contains(n.folderId)) {
        return Note(
          id: n.id,
          title: n.title,
          pages: n.pages,
          updatedAt: n.updatedAt,
          folderId: widget.folder.id,
        );
      }
      return n;
    }).toList();
    folders.removeWhere((f) => folderIds.contains(f.id));
    await _service.saveNotes(updatedNotes);
    await _service.saveFolders(folders);
    await _reloadLocal();
  }

  String _fmt(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final folderColor = widget.folder.color;
    final isWide = MediaQuery.of(context).size.width > 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalItems = _folderNotes.length + _subFolders.length + 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: DragTarget<Note>(
          onWillAcceptWithDetails: (_) {
            setState(() => _draggingOverRoot = true);
            return true;
          },
          onLeave: (_) => setState(() => _draggingOverRoot = false),
          onAcceptWithDetails: (d) {
            setState(() => _draggingOverRoot = false);
            _moveToRoot(d.data);
          },
          builder: (_, candidate, __) => AppBar(
            backgroundColor: _draggingOverRoot
                ? Colors.orange.shade100
                : isDark ? const Color(0xFF1A1A2E) : Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(children: [
              Icon(Icons.folder_rounded, color: folderColor, size: 22),
              const SizedBox(width: 8),
              Text(widget.folder.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_draggingOverRoot) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Drop here to move to root',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ]
            ]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${_folderNotes.length} notes • ${_subFolders.length} folders',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.82,
          ),
          itemCount: totalItems,
          itemBuilder: (_, i) {
            if (i == 0) return _newCard(folderColor);
            if (i <= _subFolders.length) {
              return _folderCard(_subFolders[i - 1]);
            }
            return _noteCard(
              _folderNotes[i - _subFolders.length - 1],
              folderColor,
            );
          },
        ),

        const Positioned.fill(
          child: FloatingChatButton(),
        ),
      ],
    ),
    );
  }

  Widget _newCard(Color folderColor) {
    return GestureDetector(
      onTap: _showNewMenu,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: folderColor.withOpacity(0.5), width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: folderColor.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.add, size: 32, color: folderColor),
          ),
          const SizedBox(height: 12),
          Text('New', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: folderColor)),
        ]),
      ),
    );
  }

  Widget _folderCard(NoteFolder folder) {
    final count = _notesInFolder(folder.id).length;
    final subCount = _subFoldersIn(folder.id).length;
    final isHovered = _draggingOverFolderId == folder.id;

    return DragTarget<Note>(
      onWillAcceptWithDetails: (_) {
        setState(() => _draggingOverFolderId = folder.id);
        return true;
      },
      onLeave: (_) => setState(() => _draggingOverFolderId = null),
      onAcceptWithDetails: (d) => _moveNoteToFolder(d.data, folder),
      builder: (_, __, ___) => GestureDetector(
        onTap: () => _openFolder(folder),
        onLongPress: () => _deleteFolder(folder),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isHovered
                ? folder.color.withOpacity(0.15)
                : Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E1E2E)
                    : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isHovered ? folder.color : folder.color.withOpacity(0.35),
              width: isHovered ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: folder.color.withOpacity(isHovered ? 0.25 : 0.1),
                blurRadius: isHovered ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(alignment: Alignment.center, children: [
              Icon(Icons.folder_rounded, size: 64, color: folder.color),
              if (count > 0 || subCount > 0)
                Positioned(
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Text('${count + subCount}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: folder.color)),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(folder.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 4),
            Text('$count note${count == 1 ? '' : 's'} • $subCount folder${subCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            if (isHovered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Drop here',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: folder.color)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _noteCard(Note note, Color folderColor) {
    final pastels = [
      const Color(0xFFFFF0F0), const Color(0xFFF0F4FF),
      const Color(0xFFF0FFF4), const Color(0xFFFFFBF0),
      const Color(0xFFF8F0FF), const Color(0xFFF0FAFF),
    ];
    final accents = [
      const Color(0xFFFFCDD2), const Color(0xFFBBDEFB),
      const Color(0xFFC8E6C9), const Color(0xFFFFECB3),
      const Color(0xFFE1BEE7), const Color(0xFFB2EBF2),
    ];
    final idx = note.id.codeUnits.first % pastels.length;
    final bg = pastels[idx];
    final accent = accents[idx];

    final inner = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            child: Container(
              color: Colors.white.withOpacity(0.6),
              child: note.pages.first.strokes.isEmpty
                  ? Center(child: Icon(Icons.edit_outlined, color: accent, size: 36))
                  : CustomPaint(painter: _PreviewPainter(note.pages.first.strokes), size: Size.infinite),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.layers_outlined, size: 11, color: Colors.grey.shade500),
              const SizedBox(width: 3),
              Text('${note.pages.length}p', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const Spacer(),
              Text(_fmt(note.updatedAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ]),
          ]),
        ),
      ]),
    );

    return Draggable<Note>(
      data: note,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 110,
          height: 130,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: accent, width: 1.5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.note, size: 32, color: accent),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(note.title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: inner),
      child: GestureDetector(
        onTap: () => _openNote(note),
        onLongPress: () => _deleteNote(note),
        child: inner,
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final List<DrawnPoint> strokes;
  _PreviewPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    double minX = double.infinity, minY = double.infinity, maxX = 0, maxY = 0;
    for (final s in strokes) {
      if (s.point != null) {
        if (s.point!.dx < minX) minX = s.point!.dx;
        if (s.point!.dy < minY) minY = s.point!.dy;
        if (s.point!.dx > maxX) maxX = s.point!.dx;
        if (s.point!.dy > maxY) maxY = s.point!.dy;
      }
    }
    if (minX == double.infinity) return;
    final sw = maxX - minX, sh = maxY - minY;
    if (sw == 0 || sh == 0) return;
    final scale = ((size.width / (sw + 40)) < (size.height / (sh + 40)))
        ? size.width / (sw + 40)
        : size.height / (sh + 40);
    canvas.save();
    canvas.translate((size.width - sw * scale) / 2 - minX * scale,
        (size.height - sh * scale) / 2 - minY * scale);
    canvas.scale(scale);
    final p = Paint()..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (int i = 0; i < strokes.length - 1; i++) {
      final c = strokes[i], n = strokes[i + 1];
      if (c.point == null || n.point == null) continue;
      p.color = c.color;
      p.strokeWidth = c.strokeWidth;
      canvas.drawLine(c.point!, n.point!, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}
