import 'dart:math';
import 'package:flutter/material.dart';

/// A draggable floating assistant button with a larger overlay.
/// The overlay can switch between a classic chat panel and a GPT-style panel.
class FloatingChatButton extends StatefulWidget {
  const FloatingChatButton({super.key});

  @override
  State<FloatingChatButton> createState() => _FloatingChatButtonState();
}

/// Full-page version of the classic group chat used by the sidebar.
class ClassicChatScreen extends StatelessWidget {
  const ClassicChatScreen({super.key});

  @override
  Widget build(BuildContext context) => const _CompactChatView();
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
          GestureDetector(
            onTap: _togglePanel,
            child: Container(color: Colors.black26),
          ),
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
              child: Icon(
                _panelOpen ? Icons.close : Icons.auto_awesome,
                color: Colors.white,
                size: 22,
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
                  _ModeChip(
                    label: 'Chat',
                    selected: mode == _OverlayMode.chat,
                    onTap: () => onModeChanged(_OverlayMode.chat),
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
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
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
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF0B8B6B) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelRoom {
  final String id;
  final String name;
  final String lastMessage;
  final String color;

  _PanelRoom(this.id, this.name, this.lastMessage, this.color);
}

class _PanelMsg {
  final String sender;
  final String text;
  final bool isMe;
  final String? color;

  _PanelMsg(this.sender, this.text, this.isMe, this.color);
}

class _CompactChatView extends StatefulWidget {
  const _CompactChatView();

  @override
  State<_CompactChatView> createState() => _CompactChatViewState();
}

class _CompactChatViewState extends State<_CompactChatView> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  _PanelRoom? _selectedRoom;

  final List<_PanelRoom> _rooms = [
    _PanelRoom(
      '1',
      'FYP Discussion',
      'Methodology section needs checking.',
      '6C63FF',
    ),
    _PanelRoom(
      '2',
      'Cloud Computing Group',
      'AWS architecture diagram is done.',
      '1E88E5',
    ),
  ];

  late final Map<String, List<_PanelMsg>> _messagesByRoom = {
    '1': [
      _PanelMsg(
        'Supervisor',
        'Your Agile methodology part is okay.',
        false,
        'E53935',
      ),
      _PanelMsg('Me', 'Thanks, I will refine the FYP2 SDLC.', true, null),
      _PanelMsg(
        'Teammate',
        'Remember testing and evaluation phase.',
        false,
        '43A047',
      ),
    ],
    '2': [
      _PanelMsg(
        'Jason',
        'Use S3 for clinic image and X-ray files.',
        false,
        '1E88E5',
      ),
      _PanelMsg('Me', 'Okay, and CloudWatch for monitoring.', true, null),
      _PanelMsg(
        'Aina',
        'SNS can notify admin when issue occurs.',
        false,
        'EC4899',
      ),
    ],
  };

  List<_PanelMsg> get _messages =>
      _messagesByRoom[_selectedRoom?.id] ?? const <_PanelMsg>[];

  @override
  void initState() {
    super.initState();
    _selectedRoom = _rooms.first;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _selectedRoom == null) return;
    setState(() {
      _messagesByRoom[_selectedRoom!.id]!.add(_PanelMsg('Me', text, true, null));
      _ctrl.clear();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roomColor = Color(int.parse('FF${_selectedRoom!.color}', radix: 16));

    return Row(
      children: [
        Container(
          width: 210,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _rooms.length,
            itemBuilder: (_, i) {
              final room = _rooms[i];
              final selected = _selectedRoom?.id == room.id;
              final color = Color(int.parse('FF${room.color}', radix: 16));
              return GestureDetector(
                onTap: () => setState(() => _selectedRoom = room),
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
                        child: Text(
                          room.name.substring(0, 1),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              room.lastMessage,
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
                    ],
                  ),
                ),
              );
            },
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
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedRoom!.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Chat mode',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _chatBubble(_messages[i], isDark),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1F2937)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _ctrl,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Message chat...',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: roomColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
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

  Widget _chatBubble(_PanelMsg msg, bool isDark) {
    if (msg.isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF10A37F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(msg.text, style: const TextStyle(color: Colors.white)),
        ),
      );
    }

    final color = msg.color != null
        ? Color(int.parse('FF${msg.color}', radix: 16))
        : Colors.grey;

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
              msg.sender.substring(0, 1),
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
                  msg.sender,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(msg.text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GptThread {
  final String id;
  String title;
  final List<_GptMessage> messages;
  DateTime updatedAt;

  _GptThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });
}

class _GptMessage {
  final String text;
  final bool isUser;

  _GptMessage(this.text, this.isUser);
}

class _CompactGptView extends StatefulWidget {
  const _CompactGptView();

  @override
  State<_CompactGptView> createState() => _CompactGptViewState();
}

class _CompactGptViewState extends State<_CompactGptView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _random = Random();
  bool _thinking = false;

  late final List<_GptThread> _threads = [
    _GptThread(
      id: 'g1',
      title: 'Research assistant',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
      messages: [
        _GptMessage(
          'Hi! I can help brainstorm notes, summarize content, and rewrite rough ideas.',
          false,
        ),
      ],
    ),
    _GptThread(
      id: 'g2',
      title: 'Study outline',
      updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      messages: [
        _GptMessage('Help me revise chapter 3 quickly.', true),
        _GptMessage(
          'Start with the key concepts, then examples, then short recall questions.',
          false,
        ),
      ],
    ),
  ];

  _GptThread? _selected;

  List<_GptMessage> get _messages => _selected?.messages ?? const <_GptMessage>[];

  @override
  void initState() {
    super.initState();
    _selected = _threads.first;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _newChat() {
    final thread = _GptThread(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New chat',
      updatedAt: DateTime.now(),
      messages: [
        _GptMessage('Ask anything. This floating GPT view opens directly.', false),
      ],
    );

    setState(() {
      _threads.insert(0, thread);
      _selected = thread;
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    final thread = _selected;
    if (text.isEmpty || thread == null || _thinking) return;

    setState(() {
      thread.messages.add(_GptMessage(text, true));
      thread.updatedAt = DateTime.now();
      if (thread.title == 'New chat') {
        thread.title = text.split(RegExp(r'\s+')).take(4).join(' ');
      }
      _inputCtrl.clear();
      _thinking = true;
    });
    _scrollToBottom();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() {
      thread.messages.add(_GptMessage(_replyFor(text), false));
      thread.updatedAt = DateTime.now();
      _thinking = false;
      _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _selected = _threads.firstWhere((t) => t.id == thread.id);
    });
    _scrollToBottom();
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

  String _replyFor(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('note')) {
      return 'A simple note structure is heading, three key points, one example, and a one-line takeaway.';
    }
    if (lower.contains('fyp') || lower.contains('project')) {
      return 'For an FYP, focus on problem, objective, method, implementation, and evaluation.';
    }
    if (lower.contains('flutter') || lower.contains('code')) {
      return 'I can help break Flutter work into UI, state, services, and testing so it stays manageable.';
    }
    final starters = [
      'Here is a simple way to think about it.',
      'A clean starting point would be this.',
      'You can structure it like this.',
    ];
    return '${starters[_random.nextInt(starters.length)]} Break the idea into smaller sections, then turn each section into a short actionable note.';
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
    if (thread == null) return const SizedBox.shrink();

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
                  label: const Text('New GPT Chat'),
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
                      onTap: () => setState(() => _selected = item),
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
                                color: const Color(0xFF10A37F).withOpacity(0.12),
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
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Notebook GPT',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9FFF5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'No login',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F9D58),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'GPT mode',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Icon(
                              Icons.auto_awesome_outlined,
                              color: Color(0xFF10A37F),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _inputCtrl,
                              minLines: 1,
                              maxLines: 4,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'Message Notebook GPT...',
                                border: InputBorder.none,
                                isCollapsed: true,
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
                                _thinking ? Icons.hourglass_top : Icons.arrow_upward,
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
                      'Floating GPT is still a local assistant UI, not a real API connection yet.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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

  Widget _gptBubble(_GptMessage msg, bool isDark) {
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
          child: Text(msg.text, style: const TextStyle(color: Colors.white)),
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
          Expanded(child: Text(msg.text)),
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
          Text('Notebook GPT is thinking...'),
        ],
      ),
    );
  }
}
