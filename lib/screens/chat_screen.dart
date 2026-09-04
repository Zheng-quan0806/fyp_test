import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_chat_store.dart';
import '../services/ai_service.dart';
import '../services/clipboard_image_service.dart';
import '../services/google_auth_service.dart';
import '../utils/ai_text_formatter.dart';
import '../widgets/expandable_image.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final AiChatStore _store = AiChatStore.instance;

  List<AiChatThread> get _threads => _store.threads;
  AiChatThread? get _selectedThread => _store.selectedThread;
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

  List<AiChatMessage> get _messages => _store.messages;

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
        _selectedThread == null ||
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
          duration: const Duration(milliseconds: 250),
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
                'Notebook Tutor',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<GoogleAuthUser?>(
                valueListenable: GoogleAuthService.instance.currentUser,
                builder: (context, user, _) => Tooltip(
                  message: user?.email ?? 'Using a guest account',
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 170),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
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
                          size: 14,
                          color: const Color(0xFF0F9D58),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            user?.displayName ?? 'Guest mode',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
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
                  onTap: () => _store.selectThread(thread),
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
                                  color:
                                      selected ? const Color(0xFF0D7A60) : null,
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
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete chat',
                          onPressed: () => _deleteThread(thread),
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
    );
  }

  Widget _buildConversationArea(bool isDark) {
    final thread = _selectedThread;
    if (thread == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 42,
              color: Color(0xFF10A37F),
            ),
            const SizedBox(height: 14),
            const Text(
              'No tutor chats yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a new chat when you are ready to learn.',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _newChat,
              icon: const Icon(Icons.add),
              label: const Text('New Tutor Chat'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10A37F),
              ),
            ),
          ],
        ),
      );
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
                        'Tutor-first Gemini assistant',
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
          if (_pendingImage != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Stack(
                children: [
                  ExpandableImage.memory(
                    _pendingImage!.bytes,
                    width: 120,
                    height: 88,
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
                          size: 16,
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
                IconButton(
                  tooltip: 'Choose image',
                  onPressed: _pickImage,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 20,
                    color: Color(0xFF10A37F),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.keyV,
                          control: true): _pasteFromClipboard,
                    },
                    child: TextField(
                      controller: _inputCtrl,
                      onChanged: _store.updateDraft,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
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
            'Powered by Gemini through a secure Supabase Edge Function.',
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.image != null) ...[
                ExpandableImage.memory(
                  msg.image!.bytes,
                  width: 320,
                  height: 220,
                ),
                const SizedBox(height: 10),
              ],
              Text(
                msg.text,
                style: const TextStyle(color: Colors.white, height: 1.45),
              ),
            ],
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
              formatAiText(msg.text),
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
          Text('Notebook Tutor is thinking...'),
        ],
      ),
    );
  }
}
