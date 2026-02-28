import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const ProCarromApp());

class ProCarromApp extends StatelessWidget {
  const ProCarromApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const CarromMatch(),
    );
  }
}

// --- FIXED LOW-LATENCY SOUND ENGINE ---
class CarromAudio {
  // We use a pool of players to allow overlapping sounds without interruption
  static final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  static int _poolIndex = 0;
  static int _lastPlayTime = 0;

  static void playTok() async {
    // Throttling: Prevents "machine gun" sound errors during rapid physics updates
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPlayTime < 50) return; 
    _lastPlayTime = now;

    try {
      final player = _pool[_poolIndex];
      _poolIndex = (_poolIndex + 1) % _pool.length;

      // PlayerMode.lowLatency is critical for fixing the delay
      await player.play(
        AssetSource("tok.mp3"), 
        mode: PlayerMode.lowLatency
      );
    } catch (e) {
      debugPrint("Audio Ignored: $e");
    }
  }
}

enum PieceType { white, black, queen, striker }
enum PlayerTurn { whitePlayer, blackPlayer }
enum GamePhase { placing, aiming, moving, evaluating, gameOver }

class CarromPiece {
  Offset position;
  Offset velocity;
  final double radius;
  final PieceType type;
  bool isPocketed = false;

  CarromPiece({
    required this.position,
    this.velocity = Offset.zero,
    required this.radius,
    required this.type,
  });
}

class CarromMatch extends StatefulWidget {
  const CarromMatch({super.key});
  @override
  State<CarromMatch> createState() => _CarromMatchState();
}

class _CarromMatchState extends State<CarromMatch> with SingleTickerProviderStateMixin {
  late AnimationController _gameLoop;
  bool _isInitialized = false;
  double _lastBoardSize = 0;
  List<CarromPiece> pieces = [];
  
  PlayerTurn _currentTurn = PlayerTurn.whitePlayer;
  GamePhase _phase = GamePhase.placing;
  
  int _whiteInHoles = 0;
  int _blackInHoles = 0;
  int _timeLeft = 30;
  Timer? _turnTimer;
  Offset _dragPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _gameLoop = AnimationController(vsync: this, duration: const Duration(days: 365))
      ..addListener(_updatePhysics)..forward();
  }

  void _startTimer() {
    _turnTimer?.cancel();
    _timeLeft = 30;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_phase == GamePhase.moving || _phase == GamePhase.gameOver) return;
      setState(() { if (_timeLeft > 0) _timeLeft--; else _switchTurn(); });
    });
  }

  void _initBoard(double size) {
    _lastBoardSize = size;
    final center = Offset(size * 0.5, size * 0.5);
    final pr = size * 0.026; 
    pieces.clear();
    _whiteInHoles = 0; _blackInHoles = 0;
    
    pieces.add(CarromPiece(position: center, radius: pr, type: PieceType.queen));
    
    for (int i = 0; i < 6; i++) {
      double angle = i * (pi / 3);
      pieces.add(CarromPiece(
        position: center + Offset(cos(angle), sin(angle)) * (pr * 2.1),
        radius: pr, type: i % 2 == 0 ? PieceType.white : PieceType.black));
    }
    for (int i = 0; i < 12; i++) {
      double angle = i * (pi / 6) + (pi / 12);
      pieces.add(CarromPiece(
        position: center + Offset(cos(angle), sin(angle)) * (pr * 4.2),
        radius: pr, type: i % 2 == 0 ? PieceType.black : PieceType.white));
    }
    
    _resetStriker(size);
    _isInitialized = true;
    _startTimer();
  }

  void _resetStriker(double size) {
    double yPos = _currentTurn == PlayerTurn.whitePlayer ? size * 0.815 : size * 0.185;
    pieces.removeWhere((p) => p.type == PieceType.striker);
    pieces.add(CarromPiece(position: Offset(size * 0.5, yPos), radius: size * 0.042, type: PieceType.striker));
    _phase = GamePhase.placing;
  }

  void _updatePhysics() {
    if (_phase != GamePhase.moving) return;
    bool anyMoving = false;
    final pocketR = _lastBoardSize * 0.065;
    final margin = _lastBoardSize * 0.075;

    setState(() {
      for (var p in pieces) {
        if (p.isPocketed) continue;
        if (p.velocity.distance > 0.1) {
          anyMoving = true;
          p.position += p.velocity;
          p.velocity *= 0.985; 

          if (p.position.dx < margin + p.radius || p.position.dx > _lastBoardSize - margin - p.radius) {
            p.velocity = Offset(-p.velocity.dx, p.velocity.dy);
            CarromAudio.playTok();
          }
          if (p.position.dy < margin + p.radius || p.position.dy > _lastBoardSize - margin - p.radius) {
            p.velocity = Offset(p.velocity.dx, -p.velocity.dy);
            CarromAudio.playTok();
          }

          final pks = [Offset(margin, margin), Offset(_lastBoardSize-margin, margin), Offset(margin, _lastBoardSize-margin), Offset(_lastBoardSize-margin, _lastBoardSize-margin)];
          for (var pk in pks) {
            if ((p.position - pk).distance < pocketR) {
              p.isPocketed = true;
              CarromAudio.playTok(); 
              if (p.type == PieceType.white) _whiteInHoles++;
              if (p.type == PieceType.black) _blackInHoles++;
            }
          }
        }
      }
      
      for (int i = 0; i < pieces.length; i++) {
        for (int j = i + 1; j < pieces.length; j++) {
          var a = pieces[i]; var b = pieces[j];
          if (a.isPocketed || b.isPocketed) continue;
          double d = (a.position - b.position).distance;
          if (d < a.radius + b.radius && d > 0) {
            CarromAudio.playTok(); 
            Offset n = (a.position - b.position) / d;
            double pV = (a.velocity.dx * n.dx + a.velocity.dy * n.dy) - (b.velocity.dx * n.dx + b.velocity.dy * n.dy);
            a.velocity -= n * pV; b.velocity += n * pV;
            double overlap = (a.radius + b.radius) - d;
            a.position += n * (overlap / 2);
            b.position -= n * (overlap / 2);
          }
        }
      }
      if (!anyMoving) { _phase = GamePhase.evaluating; _checkStatus(); }
    });
  }

  void _checkStatus() { if (_whiteInHoles == 9) _gameOver("White Wins!"); else if (_blackInHoles == 9) _gameOver("Black Wins!"); else _switchTurn(); }
  void _gameOver(String msg) { _phase = GamePhase.gameOver; showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(msg), actions: [TextButton(onPressed: () {Navigator.pop(ctx); _initBoard(_lastBoardSize);}, child: const Text("Restart"))])); }
  void _switchTurn() { _currentTurn = _currentTurn == PlayerTurn.whitePlayer ? PlayerTurn.blackPlayer : PlayerTurn.whitePlayer; _resetStriker(_lastBoardSize); _startTimer(); }
  void _handleTouch(Offset pos, String type) {
    if (_phase == GamePhase.moving || _phase == GamePhase.gameOver) return;
    var s = pieces.firstWhere((p) => p.type == PieceType.striker);
    if (type == "start" && (pos - s.position).distance < 60) _phase = GamePhase.aiming;
    if (type == "update") { if (_phase == GamePhase.placing) { s.position = Offset(pos.dx.clamp(_lastBoardSize * 0.25, _lastBoardSize * 0.75), s.position.dy); } else { _dragPosition = pos; } }
    if (type == "end" && _phase == GamePhase.aiming) { CarromAudio.playTok(); s.velocity = (s.position - _dragPosition) * 0.28; _phase = GamePhase.moving; }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          _buildScoreboard(),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(builder: (context, constraints) {
                  if (!_isInitialized || _lastBoardSize != constraints.maxWidth) { _initBoard(constraints.maxWidth); }
                  return GestureDetector(
                    onPanStart: (d) => _handleTouch(d.localPosition, "start"),
                    onPanUpdate: (d) => _handleTouch(d.localPosition, "update"),
                    onPanEnd: (d) => _handleTouch(Offset.zero, "end"),
                    child: CustomPaint(painter: CarromUltraPainter(pieces, _phase == GamePhase.aiming ? _dragPosition : null)),
                  );
                }),
              ),
            ),
          ),
          _buildPlayerBanner(),
        ],
      ),
    );
  }

  Widget _buildScoreboard() => Container(padding: const EdgeInsets.only(top: 60, bottom: 20, left: 30, right: 30), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ _stat("WHITE", _whiteInHoles, Colors.white), _timer(), _stat("BLACK", _blackInHoles, Colors.black) ]));
  Widget _stat(String l, int c, Color col) => Column(children: [Text(l, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)), Text("$c", style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: col == Colors.white ? Colors.white : Colors.grey[400]))]);
  Widget _timer() => Stack(alignment: Alignment.center, children: [SizedBox(width: 50, height: 50, child: CircularProgressIndicator(value: _timeLeft/30, color: Colors.amber, strokeWidth: 3)), Text("$_timeLeft", style: const TextStyle(fontWeight: FontWeight.bold))]);
  Widget _buildPlayerBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 25), child: Center(child: Text(_currentTurn == PlayerTurn.whitePlayer ? "WHITE TO PLAY" : "BLACK TO PLAY", style: const TextStyle(letterSpacing: 6, color: Colors.amber, fontWeight: FontWeight.bold))));
}

class CarromUltraPainter extends CustomPainter {
  final List<CarromPiece> pieces;
  final Offset? drag;
  CarromUltraPainter(this.pieces, this.drag);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint();

    // Board Surface
    paint.color = const Color(0xFFFDE4B4);
    final margin = w * 0.075;
    canvas.drawRect(Rect.fromLTWH(margin, margin, w - margin*2, w - margin*2), paint);

    // DRAW THE HOLES
    final pR = w * 0.065;
    final hPos = [Offset(margin, margin), Offset(w - margin, margin), Offset(margin, w - margin), Offset(w - margin, w - margin)];
    for (var pos in hPos) {
      paint.shader = RadialGradient(colors: [Colors.black, Colors.grey[900]!], stops: const [0.8, 1.0]).createShader(Rect.fromCircle(center: pos, radius: pR));
      canvas.drawCircle(pos, pR, paint);
      paint.shader = null; paint.style = PaintingStyle.stroke; paint.color = Colors.black87; paint.strokeWidth = 2;
      canvas.drawCircle(pos, pR, paint);
      paint.style = PaintingStyle.fill;
    }

    _drawBoardDesign(canvas, w);
    for (var p in pieces) { if (!p.isPocketed) _drawSolidPiece(canvas, p); }
    if (drag != null) {
      final s = pieces.firstWhere((p) => p.type == PieceType.striker);
      paint.color = Colors.white.withOpacity(0.5); paint.strokeWidth = 2.5; paint.style = PaintingStyle.stroke;
      canvas.drawLine(s.position, s.position + (s.position - drag!), paint);
    }
  }

  void _drawSolidPiece(Canvas canvas, CarromPiece p) {
    final paint = Paint();
    canvas.drawCircle(p.position + const Offset(1.5, 1.5), p.radius, Paint()..color = Colors.black54..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

    Color base;
    switch (p.type) {
      case PieceType.white: base = const Color(0xFFF5F5F5); break;
      case PieceType.black: base = const Color(0xFF212121); break;
      case PieceType.queen: base = const Color(0xFFFF4081); break;
      case PieceType.striker: base = const Color(0xFF1E88E5); break;
    }

    paint.shader = RadialGradient(colors: [base, base.withOpacity(0.85)], center: const Alignment(-0.35, -0.35)).createShader(Rect.fromCircle(center: p.position, radius: p.radius));
    paint.style = PaintingStyle.fill; canvas.drawCircle(p.position, p.radius, paint);

    paint.shader = null; paint.style = PaintingStyle.stroke; paint.strokeWidth = 1.0;
    paint.color = p.type == PieceType.black ? Colors.white12 : Colors.black12;
    canvas.drawCircle(p.position, p.radius * 0.75, paint);
    canvas.drawCircle(p.position, p.radius * 0.5, paint);
    canvas.drawCircle(p.position, p.radius * 0.25, paint);
    paint.style = PaintingStyle.fill; paint.color = Colors.white.withOpacity(0.4);
    canvas.drawCircle(p.position + Offset(-p.radius*0.35, -p.radius*0.35), p.radius * 0.2, paint);
  }

  void _drawBoardDesign(Canvas canvas, double w) {
    final paint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.13, paint);
    paint.color = const Color(0xFFC62828); paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.035, paint);
    for (int i = 0; i < 4; i++) {
      canvas.save(); canvas.translate(w/2, w/2); canvas.rotate(i * pi/2); canvas.translate(-w/2, -w/2);
      paint.style = PaintingStyle.stroke; paint.color = Colors.black87;
      final y = w * 0.815;
      canvas.drawLine(Offset(w*0.25, y-w*0.012), Offset(w*0.75, y-w*0.012), paint);
      canvas.drawLine(Offset(w*0.25, y+w*0.012), Offset(w*0.75, y+w*0.012), paint);
      paint.style = PaintingStyle.fill; paint.color = const Color(0xFFC62828);
      canvas.drawCircle(Offset(w*0.25, y), w*0.018, paint);
      canvas.drawCircle(Offset(w*0.75, y), w*0.018, paint);
      paint.style = PaintingStyle.stroke; paint.color = Colors.black87;
      canvas.drawArc(Rect.fromCircle(center: Offset(w*0.19, w*0.81), radius: w*0.08), 0, pi, false, paint);
      canvas.drawLine(Offset(w*0.13, w*0.87), Offset(w*0.08, w*0.92), paint);
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}