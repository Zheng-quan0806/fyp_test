import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      // Top bar
      Container(
        height: 64,
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(children: [
          Text('Brain Games',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
      ),
      Divider(height: 1, color: Colors.grey.shade200),

      // Game cards
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Improve your concentration & focus',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _gameCard(
                  title: 'Stroop Test',
                  subtitle: 'Inhibition control',
                  description:
                      'Name the COLOR of each word, not what it says. Trains your brain to suppress automatic responses.',
                  icon: Icons.format_color_text,
                  color: const Color(0xFF6C63FF),
                  onPlay: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StroopGameScreen()),
                  ),
                )),
                const SizedBox(width: 20),
                Expanded(child: _gameCard(
                  title: 'Schulte Grid',
                  subtitle: 'Peripheral vision & focus',
                  description:
                      'Find numbers 1–25 in order as fast as possible. Expands peripheral vision and improves focus speed.',
                  icon: Icons.grid_4x4,
                  color: const Color(0xFF1E88E5),
                  onPlay: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SchulteGridScreen()),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _gameCard({
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onPlay,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icon
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(description,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade500, height: 1.5)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play Now'),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── STROOP GAME ────────────────────────────────────────────────────────────
class StroopGameScreen extends StatefulWidget {
  const StroopGameScreen({super.key});

  @override
  State<StroopGameScreen> createState() => _StroopGameScreenState();
}

class _StroopGameScreenState extends State<StroopGameScreen> {
  static const _words = ['RED', 'BLUE', 'GREEN', 'YELLOW', 'PURPLE', 'ORANGE'];
  static const _colors = [
    Colors.red, Colors.blue, Colors.green,
    Colors.yellow, Colors.purple, Colors.orange,
  ];
  static const _colorNames = [
    'Red', 'Blue', 'Green', 'Yellow', 'Purple', 'Orange',
  ];

  final _rng = Random();
  int _score = 0;
  int _wrong = 0;
  int _round = 0;
  static const _totalRounds = 10;
  int _secondsLeft = 0;
  Timer? _timer;
  bool _gameOver = false;
  bool _started = false;

  // Current question
  late String _word;
  late Color _inkColor;
  late int _correctColorIdx;
  late List<int> _options;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startGame() {
    setState(() {
      _score = 0; _wrong = 0; _round = 0;
      _gameOver = false; _started = true;
      _secondsLeft = 60;
    });
    _nextQuestion();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) { t.cancel(); _endGame(); }
    });
  }

  void _nextQuestion() {
    final wordIdx = _rng.nextInt(_words.length);
    // Ink color different from word meaning (the classic Stroop conflict)
    int inkIdx;
    do { inkIdx = _rng.nextInt(_colors.length); } while (inkIdx == wordIdx);

    _correctColorIdx = inkIdx;
    _word = _words[wordIdx];
    _inkColor = _colors[inkIdx];

    // 4 answer choices including correct
    final opts = {inkIdx};
    while (opts.length < 4) opts.add(_rng.nextInt(_colors.length));
    _options = opts.toList()..shuffle();
  }

  void _answer(int idx) {
    if (_gameOver) return;
    setState(() {
      if (idx == _correctColorIdx) { _score++; } else { _wrong++; }
      _round++;
      if (_round >= _totalRounds) { _endGame(); } else { _nextQuestion(); }
    });
  }

  void _endGame() {
    _timer?.cancel();
    setState(() => _gameOver = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        title: const Text('Stroop Test',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_started && !_gameOver)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 4),
                Text('$_secondsLeft s',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
      body: Center(
        child: _gameOver
            ? _resultView()
            : !_started
                ? _startView()
                : _questionView(),
      ),
    );
  }

  Widget _startView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.format_color_text,
              size: 80, color: Color(0xFF6C63FF)),
          const SizedBox(height: 24),
          const Text('Stroop Test',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'You\'ll see a color word written in a different ink color.\n'
              'Tap the button matching the INK COLOR — not the word!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600,
                  height: 1.6),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start — 60 seconds'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
            ),
          ),
        ],
      );

  Widget _questionView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Score row
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _scorePill('✓ $_score', Colors.green),
            const SizedBox(width: 12),
            _scorePill('✗ $_wrong', Colors.red),
            const SizedBox(width: 12),
            _scorePill('${_round + 1}/$_totalRounds', Colors.grey),
          ]),
          const SizedBox(height: 48),

          // The word
          Text(_word,
              style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: _inkColor,
                  letterSpacing: 4)),
          const SizedBox(height: 16),
          Text('What color is the ink?',
              style: TextStyle(
                  fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 40),

          // Answer buttons
          Wrap(
            spacing: 16, runSpacing: 16,
            alignment: WrapAlignment.center,
            children: _options.map((idx) {
              return GestureDetector(
                onTap: () => _answer(idx),
                child: Container(
                  width: 140, height: 56,
                  decoration: BoxDecoration(
                    color: _colors[idx],
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: _colors[idx].withOpacity(0.4),
                          blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Center(
                    child: Text(_colorNames[idx],
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );

  Widget _resultView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events, size: 80,
              color: Color(0xFF6C63FF)),
          const SizedBox(height: 20),
          const Text('Game Over!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('Score: $_score / $_totalRounds',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Accuracy: ${_score + _wrong == 0 ? 0 : ((_score / (_score + _wrong)) * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.refresh),
            label: const Text('Play Again'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14)),
          ),
        ],
      );

  Widget _scorePill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color, fontSize: 15)),
      );
}

// ── SCHULTE GRID ───────────────────────────────────────────────────────────
class SchulteGridScreen extends StatefulWidget {
  const SchulteGridScreen({super.key});

  @override
  State<SchulteGridScreen> createState() => _SchulteGridScreenState();
}

class _SchulteGridScreenState extends State<SchulteGridScreen> {
  static const _size = 5; // 5×5 = 25 numbers
  List<int> _grid = [];
  int _next = 1;
  int _seconds = 0;
  Timer? _timer;
  bool _started = false;
  bool _done = false;
  int? _lastTapped;
  bool _lastCorrect = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startGame() {
    final nums = List.generate(_size * _size, (i) => i + 1)..shuffle();
    setState(() {
      _grid = nums;
      _next = 1; _seconds = 0;
      _started = true; _done = false;
      _lastTapped = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  void _tap(int num) {
    if (!_started || _done) return;
    setState(() {
      _lastTapped = num;
      _lastCorrect = num == _next;
      if (num == _next) {
        _next++;
        if (_next > _size * _size) {
          _timer?.cancel();
          _done = true;
        }
      }
    });
  }

  String _timeStr() {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
        title: const Text('Schulte Grid',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_started)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 4),
                Text(_timeStr(),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
      body: Center(
        child: _done
            ? _resultView()
            : !_started
                ? _startView()
                : _gridView(),
      ),
    );
  }

  Widget _startView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.grid_4x4, size: 80, color: Color(0xFF1E88E5)),
          const SizedBox(height: 24),
          const Text('Schulte Grid',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Find numbers 1 to 25 in order, as fast as you can.\n'
              'Keep your eyes on the CENTER of the grid\nand use peripheral vision.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15,
                  color: Colors.grey.shade600, height: 1.6),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
            ),
          ),
        ],
      );

  Widget _gridView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Target
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E88E5).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Find: ',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            Text('$_next',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E88E5))),
          ]),
        ),

        // Grid
        SizedBox(
          width: 340, height: 340,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _size,
              mainAxisSpacing: 6, crossAxisSpacing: 6,
            ),
            itemCount: _grid.length,
            itemBuilder: (_, i) {
              final num = _grid[i];
              final found = num < _next;
              final isLast = num == _lastTapped;
              Color bg;
              Color textColor;
              if (found) {
                bg = const Color(0xFF43A047).withOpacity(0.15);
                textColor = const Color(0xFF43A047);
              } else if (isLast && !_lastCorrect) {
                bg = Colors.red.withOpacity(0.1);
                textColor = Colors.red;
              } else {
                bg = Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E1E2E)
                    : Colors.white;
                textColor =
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87;
              }

              return GestureDetector(
                onTap: () => _tap(num),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: found
                          ? const Color(0xFF43A047).withOpacity(0.3)
                          : Colors.grey.shade200,
                    ),
                    boxShadow: found
                        ? null
                        : [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2)),
                          ],
                  ),
                  child: Center(
                    child: Text('$num',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _resultView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events,
              size: 80, color: Color(0xFF1E88E5)),
          const SizedBox(height: 20),
          const Text('Completed!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('Time: ${_timeStr()}',
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700,
                  color: Color(0xFF1E88E5))),
          const SizedBox(height: 8),
          Text(
            _seconds < 30
                ? '🏆 Excellent! Top performance!'
                : _seconds < 60
                    ? '⭐ Great job! Keep training!'
                    : '💪 Good effort! Try to beat your time!',
            style: TextStyle(
                fontSize: 15, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.refresh),
            label: const Text('Play Again'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
            ),
          ),
        ],
      );
}