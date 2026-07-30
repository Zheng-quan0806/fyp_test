import 'dart:math';
import 'package:flutter/material.dart';

class AiChatThread {
  final String id;
  String title;
  final List<AiChatMessage> messages;
  DateTime updatedAt;

  AiChatThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });
}

class AiChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime time;

  AiChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.time,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Random _random = Random();

  late final List<AiChatThread> _threads = [
    AiChatThread(
      id: 'thread-1',
      title: 'Research assistant',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
      messages: [
        AiChatMessage(
          id: 'm1',
          text: 'Hi! I can help you brainstorm notes, summarize ideas, or turn rough points into cleaner study content.',
          isUser: false,
          time: DateTime.now().subtract(const Duration(minutes: 9)),
        ),
      ],
    ),
    AiChatThread(
      id: 'thread-2',
      title: 'FYP outline help',
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      messages: [
        AiChatMessage(
          id: 'm2',
          text: 'Can you help me structure my final year project report?',
          isUser: true,
          time: DateTime.now().subtract(const Duration(hours: 2, minutes: 4)),
        ),
        AiChatMessage(
          id: 'm3',
          text: 'Yes. A solid structure is: introduction, problem statement, objectives, literature review, methodology, implementation, testing, results, and conclusion.',
          isUser: false,
          time: DateTime.now().subtract(const Duration(hours: 2, minutes: 3)),
        ),
      ],
    ),
  ];

  AiChatThread? _selectedThread;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _selectedThread = _threads.first;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<AiChatMessage> get _messages =>
      _selectedThread?.messages ?? const <AiChatMessage>[];

  void _newChat() {
    final thread = AiChatThread(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New chat',
      updatedAt: DateTime.now(),
      messages: [
        AiChatMessage(
          id: 'welcome-${DateTime.now().millisecondsSinceEpoch}',
          text: 'Ask me anything about your notes, assignments, or ideas. No account is needed here.',
          isUser: false,
          time: DateTime.now(),
        ),
      ],
    );

    setState(() {
      _threads.insert(0, thread);
      _selectedThread = thread;
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    final thread = _selectedThread;
    if (text.isEmpty || thread == null || _thinking) return;

    final userMessage = AiChatMessage(
      id: 'u-${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      isUser: true,
      time: DateTime.now(),
    );

    setState(() {
      thread.messages.add(userMessage);
      thread.updatedAt = DateTime.now();
      if (thread.title == 'New chat') {
        thread.title = _titleFromPrompt(text);
      }
      _thinking = true;
      _inputCtrl.clear();
    });

    _scrollToBottom();

    await Future.delayed(const Duration(milliseconds: 550));

    if (!mounted) return;

    final reply = AiChatMessage(
      id: 'a-${DateTime.now().millisecondsSinceEpoch}',
      text: _buildAssistantReply(text),
      isUser: false,
      time: DateTime.now(),
    );

    setState(() {
      thread.messages.add(reply);
      thread.updatedAt = DateTime.now();
      _thinking = false;
      _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _selectedThread = _threads.firstWhere((t) => t.id == thread.id);
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _titleFromPrompt(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .take(4)
        .toList();
    return words.isEmpty ? 'New chat' : words.join(' ');
  }

  String _buildAssistantReply(String prompt) {
    final lower = prompt.toLowerCase();

    if (lower.contains('note') || lower.contains('summary')) {
      return 'Here is a simple note-taking pattern: topic, 3 key points, one example, then a short summary at the end. If you want, I can format your content that way.';
    }
    if (lower.contains('fyp') || lower.contains('project')) {
      return 'For an FYP, I would usually break it into problem, objective, approach, implementation, and evaluation. If you paste your topic, I can turn it into a cleaner outline.';
    }
    if (lower.contains('study') || lower.contains('exam')) {
      return 'A good study flow is: review concepts, test recall, then create a compact cheat-sheet style summary. I can help generate that from your notes.';
    }
    if (lower.contains('code') || lower.contains('flutter')) {
      return 'If this is a Flutter task, I can help with UI structure, widget breakdown, state flow, or debugging steps. Paste the part you are stuck on and I will walk through it.';
    }

    final starters = [
      'Here is a clean starting point.',
      'This is how I would approach it.',
      'A simple way to structure that is this.',
    ];
    return '${starters[_random.nextInt(starters.length)]} '
        'First define the goal clearly, then break it into smaller sections, and finally turn each section into concrete actions or notes. '
        'If you want, send me the exact text and I can rewrite it in a more polished way.';
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          height: 64,
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text(
                'Notebook GPT',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9FFF5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'No login',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F9D58),
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Chat'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10A37F),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
        Expanded(
          child: Row(
            children: [
              _buildThreadRail(isDark),
              Expanded(child: _buildConversationArea(isDark)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThreadRail(bool isDark) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16162A) : const Color(0xFFF7F8FB),
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10A37F), Color(0xFF43C59E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your built-in assistant',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Open and chat immediately, similar to a GPT app experience.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              itemCount: _threads.length,
              itemBuilder: (_, i) {
                final thread = _threads[i];
                final selected = _selectedThread?.id == thread.id;
                final preview = thread.messages.isEmpty
                    ? 'Start chatting'
                    : thread.messages.last.text;

                return GestureDetector(
                  onTap: () => setState(() => _selectedThread = thread),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFE8F7F2)
                          : isDark
                              ? const Color(0xFF1E1E2E)
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
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10A37F).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
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
                                thread.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? const Color(0xFF0D7A60)
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                preview,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(thread.updatedAt),
                          style: TextStyle(
                            fontSize: 11,
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
    );
  }

  Widget _buildConversationArea(bool isDark) {
    final thread = _selectedThread;
    if (thread == null) {
      return const Center(child: Text('Select a conversation'));
    }

    return Container(
      color: isDark ? const Color(0xFF12121E) : const Color(0xFFFDFDFC),
      child: Column(
        children: [
          Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10A37F).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF10A37F),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        thread.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'ChatGPT-style assistant without sign-in',
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
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              itemCount: _messages.length + (_thinking ? 1 : 0),
              itemBuilder: (_, i) {
                if (_thinking && i == _messages.length) {
                  return _thinkingBubble(isDark);
                }
                return _messageBubble(_messages[i], isDark);
              },
            ),
          ),
          _buildComposer(isDark),
        ],
      ),
    );
  }

  Widget _buildComposer(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16162A) : const Color(0xFFF4F6F8),
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
                    size: 18,
                    color: Color(0xFF10A37F),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
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
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10A37F),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _thinking ? Icons.hourglass_top : Icons.arrow_upward,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This version opens directly without account setup. It is a local GPT-style assistant UI.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(AiChatMessage msg, bool isDark) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.only(bottom: 14, left: 80),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF10A37F),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: Colors.white, height: 1.45),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF10A37F).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF10A37F),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg.text,
              style: const TextStyle(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thinkingBubble(bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Notebook GPT is thinking...'),
        ],
      ),
    );
  }
}
