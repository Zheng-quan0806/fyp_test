import 'dart:async';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_chat_store.dart';
import '../services/ai_service.dart';
import '../services/clipboard_image_service.dart';
import '../services/community_chat_service.dart';
import '../services/community_unread_service.dart';
import '../services/google_auth_service.dart';
import '../utils/ai_text_formatter.dart';
import '../widgets/expandable_image.dart';

/// A draggable floating assistant button with a larger overlay.
/// The overlay can switch between a classic chat panel and a GPT-style panel.
class FloatingChatButton extends StatefulWidget {
  const FloatingChatButton({super.key});

  @override
  State<FloatingChatButton> createState() => _FloatingChatButtonState();
}

/// Full-page version of the classic group chat used by the sidebar.
class ClassicChatScreen extends StatelessWidget {
  final bool isVisible;

  const ClassicChatScreen({super.key, this.isVisible = true});

  @override
  Widget build(BuildContext context) => _CompactChatView(isVisible: isVisible);
}

enum _OverlayMode { chat, gpt }

class _FloatingChatButtonState extends State<FloatingChatButton>
    with SingleTickerProviderStateMixin {
  double _x = 0;
  double _y = 200;
  bool _panelOpen = false;
  bool _initialized = false;
  _OverlayMode _mode = _OverlayMode.gpt;

  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    unawaited(CommunityUnreadService.instance.initialize());
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _snapToEdge(Size screen) {
    final mid = screen.width / 2;
    setState(() => _x = _x + 44 < mid ? 8 : screen.width - 52);
  }

  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    if (_panelOpen) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    if (!_initialized) {
      _x = screen.width - 60;
      _initialized = true;
    }

    final panelWidth = min(screen.width - 24, 560.0);
    final panelHeight = min(screen.height - 110, 640.0);

    return Stack(
      children: [
        if (_panelOpen)
          Positioned(
            right: screen.width - _x < screen.width / 2 ? 12 : null,
            left: _x < screen.width / 2 ? 12 : null,
            top: _y.clamp(60, max(60.0, screen.height - panelHeight - 24)),
            child: ScaleTransition(
              scale: _scaleAnim,
              alignment: _x < screen.width / 2
                  ? Alignment.topLeft
                  : Alignment.topRight,
              child: _OverlayPanel(
                width: panelWidth,
                height: panelHeight,
                mode: _mode,
                onModeChanged: (mode) => setState(() => _mode = mode),
                onClose: _togglePanel,
              ),
            ),
          ),
        Positioned(
          left: _x,
          top: _y.clamp(60, screen.height - 60),
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _x = (_x + d.delta.dx).clamp(0, screen.width - 52);
                _y = (_y + d.delta.dy).clamp(60, screen.height - 60);
              });
            },
            onPanEnd: (_) => _snapToEdge(screen),
            onTap: _togglePanel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _panelOpen
                    ? const Color(0xFF0B8B6B)
                    : const Color(0xFF10A37F),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10A37F).withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: CommunityUnreadService.instance.unreadCount,
                builder: (context, unreadCount, _) => Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      _panelOpen ? Icons.close : Icons.auto_awesome,
                      color: Colors.white,
                      size: 22,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 1,
                        top: 1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayPanel extends StatelessWidget {
  final double width;
  final double height;
  final _OverlayMode mode;
  final ValueChanged<_OverlayMode> onModeChanged;
  final VoidCallback onClose;

  const _OverlayPanel({
    required this.width,
    required this.height,
    required this.mode,
    required this.onModeChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      elevation: 18,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            _OverlayHeader(
              mode: mode,
              onModeChanged: onModeChanged,
              onClose: onClose,
            ),
            Expanded(
              child: mode == _OverlayMode.chat
                  ? const _CompactChatView()
                  : const _CompactGptView(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayHeader extends StatelessWidget {
  final _OverlayMode mode;
  final ValueChanged<_OverlayMode> onModeChanged;
  final VoidCallback onClose;

  const _OverlayHeader({
    required this.mode,
    required this.onModeChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF10A37F), Color(0xFF39C39A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable:
                        CommunityUnreadService.instance.unreadCount,
                    builder: (context, unreadCount, _) => _ModeChip(
                      label: 'Chat',
                      selected: mode == _OverlayMode.chat,
                      showUnread: unreadCount > 0,
                      onTap: () => onModeChanged(_OverlayMode.chat),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _ModeChip(
                    label: 'GPT',
                    selected: mode == _OverlayMode.gpt,
                    onTap: () => onModeChanged(_OverlayMode.gpt),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool showUnread;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    this.showUnread = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF0B8B6B) : Colors.white,
                ),
              ),
              if (showUnread) ...[
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactChatView extends StatefulWidget {
  final bool isVisible;

  const _CompactChatView({this.isVisible = true});

  @override
  State<_CompactChatView> createState() => _CompactChatViewState();
}

class _CompactChatViewState extends State<_CompactChatView> {
  final Object _visibilityToken = Object();
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _service = CommunityChatService.instance;
  StreamSubscription<List<CommunityProfile>>? _profilesSubscription;
  StreamSubscription<List<CommunityFriendship>>? _friendshipsSubscription;
  StreamSubscription<List<CommunityMessage>>? _messagesSubscription;

  CommunityIdentity? _identity;
  CommunityRoom? _selectedRoom;
  List<CommunityRoom> _rooms = [];
  List<CommunityMessage> _messages = [];
  Map<String, CommunityProfile> _profiles = {};
  List<CommunityFriendship> _friendships = [];
  final Map<String, Future<String>> _attachmentUrls = {};
  CommunityPendingAttachment? _pendingCommunityAttachment;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(CommunityUnreadService.instance.initialize());
    CommunityUnreadService.instance.setChatVisible(
      _visibilityToken,
      widget.isVisible,
    );
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _CompactChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      CommunityUnreadService.instance.setChatVisible(
        _visibilityToken,
        widget.isVisible,
      );
    }
  }

  @override
  void dispose() {
    CommunityUnreadService.instance.setChatVisible(_visibilityToken, false);
    _profilesSubscription?.cancel();
    _friendshipsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _profilesSubscription?.cancel();
      await _friendshipsSubscription?.cancel();
      await _messagesSubscription?.cancel();
      _profilesSubscription = null;
      _friendshipsSubscription = null;
      _messagesSubscription = null;

      final identity = await _service.ensureSignedIn();
      final rooms = await _service.loadRooms();
      final friendships = await _service.loadFriendships();
      if (!mounted) return;

      _profilesSubscription = _service.watchProfiles().listen(
        (profiles) {
          if (!mounted) return;
          setState(() {
            _profiles = {for (final profile in profiles) profile.id: profile};
          });
        },
        onError: _showStreamError,
      );
      _friendshipsSubscription = _service.watchFriendships().listen(
        (friendships) {
          if (!mounted) return;
          setState(() => _friendships = friendships);
        },
        onError: _showStreamError,
      );

      setState(() {
        _identity = identity;
        _rooms = rooms;
        _friendships = friendships;
        _loading = false;
      });
      if (rooms.isNotEmpty) _selectRoom(rooms.first);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _selectRoom(CommunityRoom room) {
    _messagesSubscription?.cancel();
    setState(() {
      _selectedRoom = room;
      _messages = [];
      _error = null;
    });
    _messagesSubscription = _service.watchMessages(room.id).listen(
      (messages) {
        if (!mounted) return;
        setState(() => _messages = messages);
        _scrollToBottom();
      },
      onError: _showStreamError,
    );
  }

  void _showStreamError(Object error) {
    if (!mounted) return;
    setState(() => _error = error.toString());
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final room = _selectedRoom;
    final pendingAttachment = _pendingCommunityAttachment;
    if ((text.isEmpty && pendingAttachment == null) ||
        room == null ||
        _sending) {
      return;
    }

    setState(() => _sending = true);
    CommunityUpload? uploadedAttachment;
    try {
      if (pendingAttachment != null) {
        uploadedAttachment = await _service.uploadAttachment(
          roomId: room.id,
          attachment: pendingAttachment,
        );
      }
      await _service.sendMessage(
        roomId: room.id,
        body: text,
        attachment: uploadedAttachment,
      );
      _ctrl.clear();
      if (mounted) setState(() => _pendingCommunityAttachment = null);
    } catch (error) {
      if (uploadedAttachment != null) {
        try {
          await _service.deleteUpload(uploadedAttachment.path);
        } catch (_) {
          // The unused upload can also be removed later from Supabase Storage.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message could not be sent: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickCommunityFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'pdf',
          'txt',
          'md',
          'csv',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'zip',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('The selected file could not be read.');
      }
      _attachCommunityFile(
        CommunityPendingAttachment(
          bytes: bytes,
          name: file.name,
          mimeType: _communityMimeType(file.extension),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to attach file: $error')),
      );
    }
  }

  Future<void> _pasteCommunityClipboard(
      {bool pasteTextIfNoImage = true}) async {
    try {
      final image = await ClipboardImageService.readImage();
      if (image != null) {
        _attachCommunityImage(image);
        return;
      }
      if (pasteTextIfNoImage) {
        await ClipboardImageService.pastePlainText(_ctrl);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The clipboard has no image.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard image could not be read ($error). Use the image button to choose the file.',
          ),
        ),
      );
    }
  }

  void _attachCommunityImage(AiImageAttachment image) {
    final extension = switch (image.mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'png',
    };
    _attachCommunityFile(
      CommunityPendingAttachment(
        bytes: image.bytes,
        name: 'pasted-image.$extension',
        mimeType: image.mimeType,
      ),
    );
  }

  void _attachCommunityFile(CommunityPendingAttachment attachment) {
    if (!mounted) return;
    if (attachment.bytes.length > CommunityChatService.maxAttachmentBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use a file smaller than 10 MB.')),
      );
      return;
    }
    setState(() => _pendingCommunityAttachment = attachment);
  }

  String _communityMimeType(String? extension) =>
      switch (extension?.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'md' => 'text/markdown',
        'csv' => 'text/csv',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'zip' => 'application/zip',
        _ => 'application/octet-stream',
      };

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  String _displayName(String userId) {
    if (userId == _identity?.userId) return _identity!.displayName;
    return _profiles[userId]?.displayName ?? 'Community user';
  }

  Color _userColor(String userId) {
    const colors = [
      Color(0xFF6C63FF),
      Color(0xFF1E88E5),
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFFEC4899),
      Color(0xFFFF8C00),
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }

  String _roomDisplayName(CommunityRoom room) {
    if (!room.isDirect) return room.name;
    final myId = _identity?.userId;
    for (final memberId in room.memberIds) {
      if (memberId != myId) return _displayName(memberId);
    }
    return 'Private chat';
  }

  String _roomSubtitle(CommunityRoom room) {
    if (room.isDirect) return 'Private chat';
    if (room.isGroup) {
      final count = room.memberIds.length;
      return '$count member${count == 1 ? '' : 's'}';
    }
    return 'Live community room';
  }

  IconData _roomIcon(CommunityRoom room) {
    if (room.isDirect) return Icons.person_outline;
    if (room.isGroup) return Icons.groups_outlined;
    return Icons.public;
  }

  Future<void> _reloadRooms({String? selectRoomId}) async {
    final rooms = await _service.loadRooms();
    if (!mounted) return;
    setState(() => _rooms = rooms);
    if (rooms.isEmpty) {
      await _messagesSubscription?.cancel();
      _messagesSubscription = null;
      if (!mounted) return;
      setState(() {
        _selectedRoom = null;
        _messages = [];
      });
      return;
    }
    CommunityRoom room = rooms.first;
    if (selectRoomId != null) {
      for (final candidate in rooms) {
        if (candidate.id == selectRoomId) {
          room = candidate;
          break;
        }
      }
    }
    _selectRoom(room);
  }

  bool _canDeleteRoom(CommunityRoom room) => room.isDirect || room.isGroup;

  Future<void> _deleteConversation(CommunityRoom room) async {
    if (!_canDeleteRoom(room)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
          '“${_roomDisplayName(room)}” will be removed from your chat list. '
          'Other members will keep their conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final selectedId = _selectedRoom?.id;
      await _service.hideRoom(room.id);
      await _reloadRooms(
        selectRoomId: selectedId == room.id ? null : selectedId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted from your list.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete chat: $error')),
      );
    }
  }

  Future<void> _showNewConversationMenu() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Start a conversation'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'friends'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.people_outline)),
              title: const Text('Friends'),
              subtitle: Text(
                _incomingRequestCount == 0
                    ? 'Search, add, and manage friends'
                    : '$_incomingRequestCount request${_incomingRequestCount == 1 ? '' : 's'} waiting',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'direct'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.person_add_outlined)),
              title: Text('New private chat'),
              subtitle: Text('Chat directly with a friend'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'group'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.group_add_outlined)),
              title: Text('Create group'),
              subtitle: Text('Choose friends for a group chat'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'friends') {
      await _showFriendsPanel();
    } else if (action == 'direct') {
      await _createDirectConversation();
    } else {
      await _createGroupConversation();
    }
  }

  List<CommunityProfile> get _availableFriends {
    final identity = _identity;
    if (identity == null) return const <CommunityProfile>[];
    final friendIds = _friendships
        .where((friendship) => friendship.status == 'accepted')
        .map((friendship) => friendship.otherUserId(identity.userId))
        .toSet();
    final profiles = _profiles.values
        .where((profile) => friendIds.contains(profile.id))
        .toList();
    profiles.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );
    return profiles;
  }

  int get _incomingRequestCount {
    final userId = _identity?.userId;
    if (userId == null) return 0;
    return _friendships
        .where(
          (friendship) =>
              friendship.status == 'pending' &&
              friendship.addresseeId == userId,
        )
        .length;
  }

  Future<void> _showFriendsPanel() async {
    final identity = _identity;
    if (identity == null) return;
    final selectedFriend = await showDialog<CommunityProfile>(
      context: context,
      builder: (context) => _CommunityFriendsDialog(
        identity: identity,
        profiles: _profiles,
      ),
    );
    try {
      final friendships = await _service.loadFriendships();
      final refreshedIdentity = await _service.ensureSignedIn();
      if (mounted) {
        setState(() {
          _friendships = friendships;
          _identity = refreshedIdentity;
        });
      }
      if (selectedFriend != null) {
        final room = await _service.createDirectChat(selectedFriend.id);
        await _reloadRooms(selectRoomId: room.id);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friends could not be refreshed: $error')),
      );
    }
  }

  Widget _friendsButton(Color color) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Friends and requests',
          onPressed: _showFriendsPanel,
          icon: const Icon(Icons.people_outline),
          color: color,
        ),
        if (_incomingRequestCount > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$_incomingRequestCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _createDirectConversation() async {
    final friends = _availableFriends;
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No accepted friends yet. Open Friends to search and send a request.',
          ),
        ),
      );
      return;
    }
    final friend = await showDialog<CommunityProfile>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New private chat'),
        content: SizedBox(
          width: 360,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: friends.length,
            itemBuilder: (_, index) {
              final profile = friends[index];
              return ListTile(
                leading: CircleAvatar(
                  child:
                      Text(profile.displayName.substring(0, 1).toUpperCase()),
                ),
                title: Text(profile.displayName),
                subtitle: Text('User ${profile.id.substring(0, 6)}'),
                onTap: () => Navigator.pop(context, profile),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || friend == null) return;
    try {
      final room = await _service.createDirectChat(friend.id);
      await _reloadRooms(selectRoomId: room.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Private chat could not be created: $error')),
      );
    }
  }

  Future<void> _createGroupConversation() async {
    final friends = _availableFriends;
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No accepted friends yet. Open Friends to search and send a request.',
          ),
        ),
      );
      return;
    }
    final nameController = TextEditingController();
    final selectedIds = <String>{};
    final result = await showDialog<({String name, List<String> memberIds})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create group'),
          content: SizedBox(
            width: 380,
            height: 390,
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 60,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose members',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (_, index) {
                      final profile = friends[index];
                      return CheckboxListTile(
                        value: selectedIds.contains(profile.id),
                        title: Text(profile.displayName),
                        secondary: CircleAvatar(
                          child: Text(
                            profile.displayName.substring(0, 1).toUpperCase(),
                          ),
                        ),
                        onChanged: (selected) {
                          setDialogState(() {
                            if (selected == true) {
                              selectedIds.add(profile.id);
                            } else {
                              selectedIds.remove(profile.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  nameController.text.trim().isEmpty || selectedIds.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            (
                              name: nameController.text.trim(),
                              memberIds: selectedIds.toList(),
                            ),
                          ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (!mounted || result == null) return;
    try {
      final room = await _service.createGroupChat(
        name: result.name,
        memberIds: result.memberIds,
      );
      await _reloadRooms(selectRoomId: room.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group could not be created: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rooms.isEmpty) {
      return _CommunityStatus(
        icon: Icons.cloud_off_outlined,
        title: 'Community could not connect',
        message: _error!,
        buttonLabel: 'Try again',
        onPressed: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _initialize();
        },
      );
    }
    if (_selectedRoom == null) {
      return _CommunityStatus(
        icon: Icons.forum_outlined,
        title: 'No chats yet',
        message: 'Start a private conversation or create a group.',
        buttonLabel: 'New chat',
        onPressed: _showNewConversationMenu,
      );
    }

    const roomColor = Color(0xFF10A37F);

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (constraints.maxWidth >= 700)
            Container(
              width: 210,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Chats',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _friendsButton(roomColor),
                        IconButton(
                          tooltip: 'New chat or group',
                          onPressed: _showNewConversationMenu,
                          icon: const Icon(Icons.add_circle_outline),
                          color: roomColor,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _rooms.length,
                      itemBuilder: (_, i) {
                        final room = _rooms[i];
                        final selected = _selectedRoom?.id == room.id;
                        const color = Color(0xFF10A37F);
                        final roomName = _roomDisplayName(room);
                        return GestureDetector(
                          onTap: () => _selectRoom(room),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withOpacity(0.12)
                                  : isDark
                                      ? const Color(0xFF111827)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected ? color : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: color.withOpacity(0.15),
                                  child: Icon(
                                    _roomIcon(room),
                                    color: color,
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        roomName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _roomSubtitle(room),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_canDeleteRoom(room))
                                  IconButton(
                                    tooltip: 'Delete chat',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _deleteConversation(room),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 19,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111827) : Colors.white,
                    border:
                        Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      if (constraints.maxWidth < 700)
                        PopupMenuButton<CommunityRoom>(
                          tooltip: 'Choose chat',
                          icon: Icon(
                            _roomIcon(_selectedRoom!),
                            color: roomColor,
                          ),
                          onSelected: _selectRoom,
                          itemBuilder: (_) => _rooms
                              .map(
                                (room) => PopupMenuItem(
                                  value: room,
                                  child: Row(
                                    children: [
                                      Icon(_roomIcon(room), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_roomDisplayName(room)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      Expanded(
                        child: Text(
                          _roomDisplayName(_selectedRoom!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _friendsButton(roomColor),
                      IconButton(
                        tooltip: 'New chat or group',
                        onPressed: _showNewConversationMenu,
                        icon: const Icon(Icons.add_comment_outlined),
                        color: roomColor,
                      ),
                      if (_canDeleteRoom(_selectedRoom!))
                        IconButton(
                          tooltip: 'Delete chat',
                          onPressed: () => _deleteConversation(_selectedRoom!),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            'No messages yet. Say hello!',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) =>
                              _chatBubble(_messages[i], isDark),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111827) : Colors.white,
                    border:
                        Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingCommunityAttachment != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Stack(
                            children: [
                              if (_pendingCommunityAttachment!.isImage)
                                ExpandableImage.memory(
                                  _pendingCommunityAttachment!.bytes,
                                  width: 112,
                                  height: 80,
                                  borderRadius: 10,
                                )
                              else
                                Container(
                                  width: 280,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    34,
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1F2937)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file_outlined,
                                        color: roomColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _pendingCommunityAttachment!.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: GestureDetector(
                                  onTap: _sending
                                      ? null
                                      : () => setState(
                                            () => _pendingCommunityAttachment =
                                                null,
                                          ),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Attach file or image',
                            onPressed: _sending ? null : _pickCommunityFile,
                            icon: const Icon(
                              Icons.attach_file,
                              color: roomColor,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Paste image from clipboard',
                            onPressed: _sending
                                ? null
                                : () => _pasteCommunityClipboard(
                                      pasteTextIfNoImage: false,
                                    ),
                            icon: const Icon(
                              Icons.content_paste_go_outlined,
                              color: roomColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1F2937)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: CallbackShortcuts(
                                bindings: {
                                  const SingleActivator(
                                    LogicalKeyboardKey.keyV,
                                    control: true,
                                  ): _pasteCommunityClipboard,
                                },
                                child: TextField(
                                  controller: _ctrl,
                                  enabled: !_sending,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(
                                    hintText: 'Message chat...',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _sending ? null : _send,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: roomColor,
                                shape: BoxShape.circle,
                              ),
                              child: _sending
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_sending && _pendingCommunityAttachment != null) ...[
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: LinearProgressIndicator(
                                color: roomColor,
                                minHeight: 3,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Uploading attachment...',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatBubble(CommunityMessage message, bool isDark) {
    final isMe = message.senderId == _identity?.userId;
    final sender = _displayName(message.senderId);
    final color = _userColor(message.senderId);
    final dateAndTime = _messageDateAndTime(message.createdAt);

    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF10A37F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.hasAttachment) ...[
                _communityAttachment(message, isMe: true),
                const SizedBox(height: 8),
              ],
              Text(
                message.body,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                dateAndTime,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 60),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withOpacity(0.15),
            child: Text(
              sender.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                if (message.hasAttachment) ...[
                  _communityAttachment(message, isMe: false),
                  const SizedBox(height: 8),
                ],
                Text(message.body),
                const SizedBox(height: 4),
                Text(
                  dateAndTime,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _messageDateAndTime(DateTime dateTime) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final time = TimeOfDay.fromDateTime(dateTime).format(context);
    return '${weekdays[dateTime.weekday - 1]}, '
        '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year} • $time';
  }

  Widget _communityAttachment(
    CommunityMessage message, {
    required bool isMe,
  }) {
    final isImage = message.attachmentIsImage;
    final path = message.attachmentPath!;
    final url = _attachmentUrls.putIfAbsent(
      path,
      () => _service.createAttachmentUrl(path),
    );

    return FutureBuilder<String>(
      future: url,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            width: 230,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.white12 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isImage
                      ? Icons.broken_image_outlined
                      : Icons.insert_drive_file_outlined,
                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${isImage ? 'Image' : 'File'} could not be loaded',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Container(
            width: 230,
            height: isImage ? 150 : 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isMe ? Colors.white12 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isMe ? Colors.white : const Color(0xFF10A37F),
            ),
          );
        }

        if (isImage) {
          return ExpandableImage.network(
            snapshot.data!,
            width: 280,
            height: 190,
            borderRadius: 10,
          );
        }

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => unawaited(_openCommunityAttachment(snapshot.data!)),
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.white12 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  color: isMe ? Colors.white : const Color(0xFF10A37F),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message.attachmentName ?? 'Shared file',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCommunityAttachment(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('No application could open this file.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open file: $error')),
      );
    }
  }
}

class _CommunityFriendsDialog extends StatefulWidget {
  final CommunityIdentity identity;
  final Map<String, CommunityProfile> profiles;

  const _CommunityFriendsDialog({
    required this.identity,
    required this.profiles,
  });

  @override
  State<_CommunityFriendsDialog> createState() =>
      _CommunityFriendsDialogState();
}

class _CommunityFriendsDialogState extends State<_CommunityFriendsDialog> {
  final _service = CommunityChatService.instance;
  final _searchController = TextEditingController();
  late final Map<String, CommunityProfile> _profiles;
  List<CommunityFriendship> _friendships = [];
  List<CommunityProfile> _searchResults = [];
  late String _username;
  bool _loading = true;
  bool _searching = false;
  bool _searchHasRun = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _profiles = Map<String, CommunityProfile>.from(widget.profiles);
    _username = widget.identity.username;
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final friendships = await _service.loadFriendships();
      if (!mounted) return;
      setState(() {
        _friendships = friendships;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchHasRun = false;
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchHasRun = true;
    });
    try {
      final results = await _service.searchProfiles(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        for (final profile in results) {
          _profiles[profile.id] = profile;
        }
      });
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  CommunityFriendship? _friendshipWith(String userId) {
    for (final friendship in _friendships) {
      if (friendship.involves(widget.identity.userId) &&
          friendship.otherUserId(widget.identity.userId) == userId) {
        return friendship;
      }
    }
    return null;
  }

  CommunityProfile _profileFor(String userId) {
    return _profiles[userId] ??
        CommunityProfile(
          id: userId,
          displayName: 'Community user',
          username: 'user_${userId.replaceAll('-', '').substring(0, 8)}',
        );
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Friend action failed: $error')),
    );
  }

  Future<void> _editUsername() async {
    final controller = TextEditingController(text: _username);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change username'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            prefixText: '@',
            helperText: '3–24 letters, numbers, or underscores',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    await _perform(() async {
      final username = await _service.updateUsername(value);
      if (mounted) setState(() => _username = username);
    });
  }

  List<Widget> _relationshipSections() {
    final userId = widget.identity.userId;
    final accepted =
        _friendships.where((item) => item.status == 'accepted').toList();
    final incoming = _friendships
        .where(
          (item) => item.status == 'pending' && item.addresseeId == userId,
        )
        .toList();
    final outgoing = _friendships
        .where(
          (item) => item.status == 'pending' && item.requesterId == userId,
        )
        .toList();

    if (accepted.isEmpty && incoming.isEmpty && outgoing.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: Text(
              'No friends yet. Search for someone by username above.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }

    return [
      if (incoming.isNotEmpty) ...[
        _sectionTitle('Friend requests (${incoming.length})'),
        ...incoming.map(
          (item) => _profileTile(
            _profileFor(item.requesterId),
            friendship: item,
          ),
        ),
      ],
      if (accepted.isNotEmpty) ...[
        _sectionTitle('Friends (${accepted.length})'),
        ...accepted.map(
          (item) => _profileTile(
            _profileFor(item.otherUserId(userId)),
            friendship: item,
          ),
        ),
      ],
      if (outgoing.isNotEmpty) ...[
        _sectionTitle('Sent requests (${outgoing.length})'),
        ...outgoing.map(
          (item) => _profileTile(
            _profileFor(item.addresseeId),
            friendship: item,
          ),
        ),
      ],
    ];
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );

  Widget _profileTile(
    CommunityProfile profile, {
    CommunityFriendship? friendship,
  }) {
    friendship ??= _friendshipWith(profile.id);
    Widget trailing;
    if (friendship?.status == 'accepted') {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton.icon(
          onPressed: _busy ? null : () => Navigator.pop(context, profile),
          icon: const Icon(Icons.chat_bubble_outline, size: 17),
          label: const Text('Chat'),
        ),
        IconButton(
          tooltip: 'Remove friend',
          onPressed: _busy
              ? null
              : () => _perform(
                    () => _service.removeFriendship(friendship!.id),
                  ),
          icon: const Icon(Icons.person_remove_outlined, size: 19),
        ),
      ]);
    } else if (friendship?.status == 'pending' &&
        friendship!.addresseeId == widget.identity.userId) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Accept',
          onPressed: _busy
              ? null
              : () => _perform(
                    () => _service.respondToFriendRequest(
                      friendshipId: friendship!.id,
                      accept: true,
                    ),
                  ),
          icon: const Icon(Icons.check_circle_outline, color: Colors.green),
        ),
        IconButton(
          tooltip: 'Reject',
          onPressed: _busy
              ? null
              : () => _perform(
                    () => _service.respondToFriendRequest(
                      friendshipId: friendship!.id,
                      accept: false,
                    ),
                  ),
          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
        ),
      ]);
    } else if (friendship?.status == 'pending') {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('Pending', style: TextStyle(color: Colors.orange)),
        IconButton(
          tooltip: 'Cancel request',
          onPressed: _busy
              ? null
              : () => _perform(
                    () => _service.removeFriendship(friendship!.id),
                  ),
          icon: const Icon(Icons.close, size: 18),
        ),
      ]);
    } else {
      trailing = FilledButton.tonalIcon(
        onPressed: _busy
            ? null
            : () => _perform(() => _service.sendFriendRequest(profile.id)),
        icon: const Icon(Icons.person_add_outlined, size: 17),
        label: const Text('Add'),
      );
    }

    return ListTile(
      leading: CircleAvatar(
        child: Text(profile.displayName.substring(0, 1).toUpperCase()),
      ),
      title: Text(profile.displayName),
      subtitle: Text('@${profile.username}'),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Community friends'),
      content: SizedBox(
        width: 560,
        height: 570,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10A37F).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.alternate_email, color: Color(0xFF10A37F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your username',
                          style: TextStyle(fontSize: 11)),
                      SelectableText(
                        '@$_username',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Change username',
                  onPressed: _busy ? null : _editUsername,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (value) {
                if (value.trim().isEmpty && _searchHasRun) {
                  setState(() {
                    _searchHasRun = false;
                    _searchResults = [];
                  });
                }
              },
              decoration: InputDecoration(
                hintText: 'Search username or name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: _searchHasRun
                          ? (_searchResults.isEmpty
                              ? const [
                                  Padding(
                                    padding: EdgeInsets.only(top: 40),
                                    child: Center(
                                      child: Text('No matching users found.'),
                                    ),
                                  ),
                                ]
                              : _searchResults
                                  .map((profile) => _profileTile(profile))
                                  .toList())
                          : _relationshipSections(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CommunityStatus extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _CommunityStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF10A37F)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactGptView extends StatefulWidget {
  const _CompactGptView();

  @override
  State<_CompactGptView> createState() => _CompactGptViewState();
}

class _CompactGptViewState extends State<_CompactGptView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final AiChatStore _store = AiChatStore.instance;

  List<AiChatThread> get _threads => _store.threads;
  AiChatThread? get _selected => _store.selectedThread;
  List<AiChatMessage> get _messages => _store.messages;
  bool get _thinking => _store.thinking;
  AiImageAttachment? get _pendingImage => _store.pendingImage;

  @override
  void initState() {
    super.initState();
    _store.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_handleStoreChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    if (_inputCtrl.text != _store.draft) {
      _inputCtrl.value = TextEditingValue(
        text: _store.draft,
        selection: TextSelection.collapsed(offset: _store.draft.length),
      );
    }
    setState(() {});
    _scrollToBottom();
  }

  void _newChat() => _store.newChat();

  Future<void> _deleteThread(AiChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
          '“${thread.title}” and all of its messages will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _store.deleteThread(thread);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete chat: $error')),
      );
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if ((text.isEmpty && _pendingImage == null) ||
        _selected == null ||
        _thinking) {
      return;
    }
    _inputCtrl.clear();
    await _store.send(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final image = await ClipboardImageService.readImage();
      if (image == null) {
        await ClipboardImageService.pastePlainText(_inputCtrl);
        _store.updateDraft(_inputCtrl.text);
        return;
      }

      _attachImage(image);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard image could not be read ($error). Use the image button to choose the file.',
          ),
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await ClipboardImageService.pickImage();
      if (image != null) _attachImage(image);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to attach image: $error')),
      );
    }
  }

  void _attachImage(AiImageAttachment image) {
    if (!mounted) return;
    if (image.bytes.length > ClipboardImageService.maxImageBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use an image smaller than 6 MB.')),
      );
      return;
    }
    _store.attachImage(image);
  }

  String _time(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thread = _selected;
    if (thread == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _newChat,
          icon: const Icon(Icons.add),
          label: const Text('New Tutor Chat'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10A37F),
          ),
        ),
      );
    }

    return Row(
      children: [
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _newChat,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Tutor Chat'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: const Color(0xFF10A37F),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: _threads.length,
                  itemBuilder: (_, i) {
                    final item = _threads[i];
                    final selected = _selected?.id == item.id;
                    return GestureDetector(
                      onTap: () => _store.selectThread(item),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE8F7F2)
                              : isDark
                                  ? const Color(0xFF111827)
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF10A37F)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF10A37F).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF10A37F),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _time(item.updatedAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete chat',
                              onPressed: () => _deleteThread(item),
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  border:
                      Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Notebook Tutor',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<GoogleAuthUser?>(
                      valueListenable: GoogleAuthService.instance.currentUser,
                      builder: (context, user, _) => Tooltip(
                        message: user?.email ?? 'Using a guest account',
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9FFF5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                user == null
                                    ? Icons.person_outline
                                    : Icons.verified_user_outlined,
                                size: 13,
                                color: const Color(0xFF0F9D58),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  user?.displayName ?? 'Guest mode',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F9D58),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'GPT mode',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(18),
                  itemCount: _messages.length + (_thinking ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_thinking && i == _messages.length) {
                      return _gptThinkingBubble(isDark);
                    }
                    return _gptBubble(_messages[i], isDark);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    if (_pendingImage != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Stack(
                          children: [
                            ExpandableImage.memory(
                              _pendingImage!.bytes,
                              width: 104,
                              height: 76,
                              borderRadius: 10,
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: GestureDetector(
                                onTap: _store.removePendingImage,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1F2937)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Choose image',
                            onPressed: _pickImage,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Color(0xFF10A37F),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: CallbackShortcuts(
                              bindings: {
                                const SingleActivator(
                                  LogicalKeyboardKey.keyV,
                                  control: true,
                                ): _pasteFromClipboard,
                              },
                              child: TextField(
                                controller: _inputCtrl,
                                onChanged: _store.updateDraft,
                                minLines: 1,
                                maxLines: 4,
                                onSubmitted: (_) => _send(),
                                decoration: const InputDecoration(
                                  hintText: 'Ask Notebook Tutor...',
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _send,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10A37F),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _thinking
                                    ? Icons.hourglass_top
                                    : Icons.arrow_upward,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Powered by Gemini through a secure Supabase Edge Function.',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gptBubble(AiChatMessage msg, bool isDark) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 90),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF10A37F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.image != null) ...[
                ExpandableImage.memory(
                  msg.image!.bytes,
                  width: 260,
                  height: 180,
                  borderRadius: 10,
                ),
                const SizedBox(height: 8),
              ],
              Text(msg.text, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12, right: 40),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF10A37F).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF10A37F),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(formatAiText(msg.text))),
        ],
      ),
    );
  }

  Widget _gptThinkingBubble(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, right: 40),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Notebook Tutor is thinking...'),
        ],
      ),
    );
  }
}
