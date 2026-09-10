import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/notes_service.dart';
import '../services/community_unread_service.dart';
import '../services/study_streak_service.dart';
import '../widgets/study_activity_region.dart';
import 'calendar_screen.dart';
import 'canvas_screen.dart';
import 'chat_screen.dart';
import 'floating_chat_button.dart';
import 'folder_screen.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = NotesService();
  List<Note> _notes = [];
  List<NoteFolder> _folders = [];
  bool _loading = true;
  bool _openingRoute = false;
  int _selectedTab = 0; // 0=Note, 1=Calendar, 2=Chat, 3=GPT, 4=Game
  String? _draggingOverFolderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await _service.loadNotes();
    final folders = await _service.loadFolders();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _folders = folders;
      _loading = false;
    });
  }

  List<Note> get _rootNotes => _notes.where((n) => n.folderId == null).toList();

  List<NoteFolder> get _rootFolders =>
      _folders.where((f) => f.parentFolderId == null).toList();

  List<Note> notesInFolder(String folderId) =>
      _notes.where((n) => n.folderId == folderId).toList();

  List<NoteFolder> subFoldersIn(String folderId) =>
      _folders.where((f) => f.parentFolderId == folderId).toList();

  // ── Move note (supports folder→folder and folder→root) ─────────────────
  Future<void> _moveNoteToFolder(Note note, NoteFolder folder) async {
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx < 0) return;
    setState(() {
      _notes[idx] = Note(
        id: note.id,
        title: note.title,
        pages: note.pages,
        updatedAt: note.updatedAt,
        folderId: folder.id,
      );
      _draggingOverFolderId = null;
    });
    await _service.saveNotes(_notes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${note.title}" moved to "${folder.name}"'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _moveNoteToRoot(Note note) async {
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx < 0) return;
    setState(() {
      _notes[idx] = Note(
        id: note.id,
        title: note.title,
        pages: note.pages,
        updatedAt: note.updatedAt,
        folderId: null,
      );
    });
    await _service.saveNotes(_notes);
  }

  // Show move-to dialog for a note (allows choosing any folder or root)
  void _showMoveDialog(Note note) {
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
          Text('Move "${note.title}" to…',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          // Root option
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.home_outlined, color: Colors.grey),
            ),
            title: const Text('Root (no folder)'),
            trailing: note.folderId == null
                ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                : null,
            onTap: () {
              Navigator.pop(context);
              if (note.folderId != null) _moveNoteToRoot(note);
            },
          ),
          // Each folder option
          ..._folders.map((f) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: f.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.folder_rounded, color: f.color),
                ),
                title: Text(f.name),
                subtitle: Text('${notesInFolder(f.id).length} notes'),
                trailing: note.folderId == f.id
                    ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  if (note.folderId != f.id) _moveNoteToFolder(note, f);
                },
              )),
        ]),
      ),
    );
  }

  // ── Create ─────────────────────────────────────────────────────────────
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
                    color: const Color(0xFFEEEDFE),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.note_add_outlined,
                    color: Color(0xFF6C63FF)),
              ),
              title: const Text('New Note',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Create a blank note'),
              onTap: () {
                Navigator.pop(context);
                _createNote();
              },
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E0),
                    borderRadius: BorderRadius.circular(12)),
                child:
                    const Icon(Icons.folder_outlined, color: Color(0xFFFF8C00)),
              ),
              title: const Text('New Folder',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Group notes together'),
              onTap: () {
                Navigator.pop(context);
                _createFolder();
              },
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final note =
        Note(id: const Uuid().v4(), title: title, updatedAt: DateTime.now());
    _notes.insert(0, note);
    await _service.saveNotes(_notes);
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CanvasScreen(note: note)));
    await _load();
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController(text: 'New Folder');
    String selectedColor = '6C63FF';
    final folderColors = [
      ('6C63FF', 'Purple'),
      ('FF8C00', 'Orange'),
      ('E53935', 'Red'),
      ('43A047', 'Green'),
      ('1E88E5', 'Blue'),
      ('EC4899', 'Pink'),
      ('00ACC1', 'Cyan'),
      ('8D6E63', 'Brown'),
    ];

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New folder'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Folder name')),
            const SizedBox(height: 16),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Color',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: folderColors.map((c) {
                final color = Color(int.parse('FF${c.$1}', radix: 16));
                final sel = selectedColor == c.$1;
                return GestureDetector(
                  onTap: () => setS(() => selectedColor = c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: sel ? 34 : 28,
                    height: sel ? 34 : 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: sel ? Colors.black54 : Colors.transparent,
                          width: 2.5),
                    ),
                    child: sel
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final folder = NoteFolder(
      id: const Uuid().v4(),
      name: name,
      colorHex: selectedColor,
      createdAt: DateTime.now(),
      parentFolderId: null,
    );
    setState(() => _folders.insert(0, folder));
    await _service.saveFolders(_folders);
  }

  Future<void> _openNote(Note note) async {
    if (_openingRoute || !mounted) return;
    _openingRoute = true;
    try {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => CanvasScreen(note: note)));
      if (!mounted) return;
      await _load();
    } finally {
      _openingRoute = false;
    }
  }

  Future<void> _openFolder(NoteFolder folder) async {
    if (_openingRoute || !mounted) return;
    _openingRoute = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderScreen(
            folder: folder,
            allNotes: _notes,
            allFolders: _folders,
            onNotesChanged: _load,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
    } finally {
      _openingRoute = false;
    }
  }

  Future<void> _deleteNote(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('Delete "${note.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _notes.removeWhere((n) => n.id == note.id));
    await _service.saveNotes(_notes);
  }

  Future<void> _deleteFolder(NoteFolder folder) async {
    final folderIds = <String>{folder.id};
    bool added = true;
    while (added) {
      added = false;
      for (final f in _folders) {
        if (f.parentFolderId != null &&
            folderIds.contains(f.parentFolderId) &&
            folderIds.add(f.id)) {
          added = true;
        }
      }
    }

    final noteCount =
        _notes.where((n) => folderIds.contains(n.folderId)).length;
    final subCount = folderIds.length - 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          'Delete "${folder.name}"? $noteCount note(s) will be moved to root${subCount > 0 ? ' and $subCount sub-folder(s) will be removed' : ''}.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final updated = _notes.map((n) {
      if (folderIds.contains(n.folderId)) {
        return Note(
            id: n.id,
            title: n.title,
            pages: n.pages,
            updatedAt: n.updatedAt,
            folderId: null);
      }
      return n;
    }).toList();
    setState(() {
      _notes = updated;
      _folders.removeWhere((f) => folderIds.contains(f.id));
    });
    await _service.saveNotes(_notes);
    await _service.saveFolders(_folders);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(children: [
        Row(children: [
          _buildSidebar(isDark),
          Container(width: 1, color: Colors.grey.shade200),
          Expanded(child: _buildMainContent()),
        ]),
        // Floating chat button (on top of everything)
        const FloatingChatButton(),
      ]),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 88,
      color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(bottom: 32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF9C94FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.auto_stories, color: Colors.white, size: 24),
        ),
        _sidebarItem(0, Icons.book_outlined, Icons.book, 'Note'),
        _sidebarItem(
            1, Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
        _sidebarItem(2, Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
        _sidebarItem(3, Icons.auto_awesome_outlined, Icons.auto_awesome, 'GPT'),
        _sidebarItem(
            4, Icons.sports_esports_outlined, Icons.sports_esports, 'Game'),
        const Spacer(),
        _buildStreakBadge(),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.settings_outlined,
                  color: Colors.grey.shade600, size: 24),
            ),
            const SizedBox(height: 4),
            Text('Settings',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _sidebarItem(
      int index, IconData icon, IconData activeIcon, String label) {
    final sel = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 72,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFEEEDFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          if (index == 2)
            ValueListenableBuilder<int>(
              valueListenable: CommunityUnreadService.instance.unreadCount,
              builder: (context, unreadCount, _) => SizedBox(
                width: 32,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      sel ? activeIcon : icon,
                      size: 26,
                      color:
                          sel ? const Color(0xFF6C63FF) : Colors.grey.shade500,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            Icon(
              sel ? activeIcon : icon,
              size: 26,
              color: sel ? const Color(0xFF6C63FF) : Colors.grey.shade500,
            ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                  color: sel ? const Color(0xFF6C63FF) : Colors.grey.shade500)),
        ]),
      ),
    );
  }

  Widget _buildMainContent() {
    return IndexedStack(
      index: _selectedTab,
      children: [
        StudyActivityRegion(
          enabled: _selectedTab == 0,
          child: _buildNotesPanel(),
        ),
        const CalendarScreen(),
        ClassicChatScreen(isVisible: _selectedTab == 2),
        StudyActivityRegion(
          enabled: _selectedTab == 3,
          child: const ChatScreen(),
        ),
        StudyActivityRegion(
          enabled: _selectedTab == 4,
          child: const GameScreen(),
        ),
      ],
    );
  }

  Widget _buildStreakBadge() {
    final streak = StudyStreakService.instance;
    return AnimatedBuilder(
      animation: streak,
      builder: (context, _) => Tooltip(
        message: streak.isProbation
            ? 'Streak Recovery: ${streak.visibleRecoveryDays}/${StudyStreakService.recoveryGoalDays} days completed'
            : '${streak.currentStreak} day study streak',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showStreakDialog(streak),
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: streak.isProbation
                  ? Colors.orange.withValues(alpha: 0.13)
                  : const Color(0xFFFFF0E0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Icon(
                streak.isProbation
                    ? Icons.hourglass_bottom_rounded
                    : Icons.local_fire_department_rounded,
                color: streak.isProbation ? Colors.orange : Colors.deepOrange,
                size: 25,
              ),
              Text(
                streak.isProbation
                    ? '${streak.visibleRecoveryDays}/${StudyStreakService.recoveryGoalDays}'
                    : '${streak.currentStreak}',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showStreakDialog(StudyStreakService streak) {
    showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: streak,
        builder: (context, _) {
          final studied = Duration(seconds: streak.todaySeconds);
          final remaining = Duration(seconds: streak.remainingSeconds);
          return AlertDialog(
            title: Row(children: [
              Icon(
                streak.isProbation
                    ? Icons.hourglass_bottom_rounded
                    : Icons.local_fire_department_rounded,
                color: streak.isProbation ? Colors.orange : Colors.deepOrange,
              ),
              const SizedBox(width: 8),
              Text(streak.statusLabel),
            ]),
            content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: streak.progress, minHeight: 10),
                const SizedBox(height: 12),
                Text(
                  streak.goalComplete
                      ? 'Today\'s ${StudyStreakService.dailyGoalMinutes}-minute goal is complete!'
                      : 'Studied ${studied.inMinutes} min today. '
                          '${remaining.inMinutes + (remaining.inSeconds % 60 == 0 ? 0 : 1)} min remaining.',
                ),
                const SizedBox(height: 8),
                Text('Longest streak: ${streak.longestStreak} days'),
                if (streak.isProbation) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Complete ${StudyStreakService.dailyGoalMinutes} minutes on '
                    '${StudyStreakService.recoveryGoalDays} consecutive days to '
                    'restore your streak. Missing 2 consecutive days resets it.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Only active time in Notes, Tutor, and Games counts. '
                  'The timer pauses after 3 minutes without activity.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotesPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Container(
        height: 64,
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          const Text('My Notes',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.search, color: Colors.grey.shade600),
            onPressed: _showSearch,
          ),
        ]),
      ),
      Divider(height: 1, color: Colors.grey.shade200),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildGrid(),
      ),
    ]);
  }

  Widget _buildGrid() {
    final isWide = MediaQuery.of(context).size.width > 900;
    final crossCount = isWide ? 4 : 3;
    final folderItems = _rootFolders.map((f) => _GridItem.folder(f)).toList();
    final noteItems = _rootNotes.map((n) => _GridItem.note(n)).toList();
    final allItems = [...folderItems, ...noteItems];
    final total = allItems.length + 1;

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: total,
      itemBuilder: (_, i) {
        if (i == 0) return _newCard();
        final item = allItems[i - 1];
        if (item.folder != null) return _folderCard(item.folder!);
        return _noteCard(item.note!);
      },
    );
  }

  Widget _newCard() {
    return GestureDetector(
      onTap: _showNewMenu,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E2E)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFF6C63FF).withOpacity(0.4), width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: const Color(0xFFEEEDFE),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.add, size: 32, color: Color(0xFF6C63FF)),
          ),
          const SizedBox(height: 12),
          const Text('New',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6C63FF))),
        ]),
      ),
    );
  }

  Widget _folderCard(NoteFolder folder) {
    final count = notesInFolder(folder.id).length;
    final subCount = subFoldersIn(folder.id).length;
    final isHovered = _draggingOverFolderId == folder.id;

    return DragTarget<Note>(
      onWillAcceptWithDetails: (d) {
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
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(alignment: Alignment.center, children: [
              Icon(Icons.folder_rounded, size: 64, color: folder.color),
              if (count > 0 || subCount > 0)
                Positioned(
                  bottom: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('${count + subCount}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: folder.color)),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(folder.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 4),
            Text(
                subCount == 0
                    ? '$count note${count == 1 ? '' : 's'}'
                    : '$count note${count == 1 ? '' : 's'} • $subCount folder${subCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            if (isHovered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Drop here',
                    style: TextStyle(
                        fontSize: 11,
                        color: folder.color,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _noteCard(Note note) {
    final pastels = [
      const Color(0xFFFFF0F0),
      const Color(0xFFF0F4FF),
      const Color(0xFFF0FFF4),
      const Color(0xFFFFFBF0),
      const Color(0xFFF8F0FF),
      const Color(0xFFF0FAFF),
    ];
    final accents = [
      const Color(0xFFFFCDD2),
      const Color(0xFFBBDEFB),
      const Color(0xFFC8E6C9),
      const Color(0xFFFFECB3),
      const Color(0xFFE1BEE7),
      const Color(0xFFB2EBF2),
    ];
    final idx = note.id.codeUnits.first % pastels.length;
    final bg = pastels[idx];
    final accent = accents[idx];

    final feedback = Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        height: 130,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent, width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.note, size: 32, color: accent),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(note.title,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );

    return Draggable<Note>(
      data: note,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging:
          Opacity(opacity: 0.35, child: _noteCardInner(note, bg, accent)),
      onDragStarted: () => setState(() => _draggingOverFolderId = null),
      onDragEnd: (_) => setState(() => _draggingOverFolderId = null),
      child: GestureDetector(
        onTap: () => _openNote(note),
        onLongPress: () => _showNoteOptions(note),
        child: _noteCardInner(note, bg, accent),
      ),
    );
  }

  // Long-press options: Move or Delete
  void _showNoteOptions(Note note) {
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
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Text(note.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined,
                  color: Color(0xFF6C63FF)),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(context);
                _showMoveDialog(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteNote(note);
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _noteCardInner(Note note, Color bg, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: accent.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            child: Container(
              color: Colors.white.withOpacity(0.6),
              child: note.pages.first.strokes.isEmpty
                  ? Center(
                      child: Icon(Icons.edit_outlined, color: accent, size: 36))
                  : CustomPaint(
                      painter: _PreviewPainter(note.pages.first.strokes),
                      size: Size.infinite,
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.layers_outlined,
                  size: 11, color: Colors.grey.shade500),
              const SizedBox(width: 3),
              Text('${note.pages.length}p',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const Spacer(),
              Text(_fmt(note.updatedAt),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ]),
          ]),
        ),
      ]),
    );
  }

  void _showSearch() {
    showDialog(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Search notes'),
            content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Note title…', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setS(() => query = v),
                ),
                const SizedBox(height: 12),
                ..._notes
                    .where((n) =>
                        n.title.toLowerCase().contains(query.toLowerCase()))
                    .map((n) => ListTile(
                          leading: const Icon(Icons.note_outlined),
                          title: Text(n.title),
                          subtitle: Text(_fmt(n.updatedAt)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openNote(n);
                          },
                        )),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          ),
        );
      },
    );
  }
}

class _GridItem {
  final Note? note;
  final NoteFolder? folder;
  const _GridItem.note(Note n)
      : note = n,
        folder = null;
  const _GridItem.folder(NoteFolder f)
      : folder = f,
        note = null;
}

class _PreviewPainter extends CustomPainter {
  final List<DrawnPoint> strokes;
  _PreviewPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    double minX = double.infinity, minY = double.infinity;
    double maxX = 0, maxY = 0;
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
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
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
