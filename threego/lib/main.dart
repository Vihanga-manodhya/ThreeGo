import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

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

// Logic Enums
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
  double _boardSize = 0;
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
    _boardSize = size;
    final center = Offset(size * 0.5, size * 0.5);
    final pr = size * 0.026; // Slightly smaller for better spacing
    pieces.clear();
    _whiteInHoles = 0;
    _blackInHoles = 0;
    
    // Queen
    pieces.add(CarromPiece(position: center, radius: pr, type: PieceType.queen));
    
    // Pieces arrangement (Standard Honeycomb Circle)
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
    
    _resetStriker();
    _isInitialized = true;
    _startTimer();
  }

  void _resetStriker() {
    double yPos = _currentTurn == PlayerTurn.whitePlayer ? _boardSize * 0.815 : _boardSize * 0.185;
    pieces.removeWhere((p) => p.type == PieceType.striker);
    pieces.add(CarromPiece(position: Offset(_boardSize * 0.5, yPos), radius: _boardSize * 0.042, type: PieceType.striker));
    _phase = GamePhase.placing;
  }

  void _updatePhysics() {
    if (_phase != GamePhase.moving) return;
    bool anyMoving = false;
    final pocketR = _boardSize * 0.062;
    final margin = _boardSize * 0.075;

    setState(() {
      for (var p in pieces) {
        if (p.isPocketed) continue;
        if (p.velocity.distance > 0.1) {
          anyMoving = true;
          p.position += p.velocity;
          p.velocity *= 0.984; // Friction coefficient

          // Wall bounces
          if (p.position.dx < margin + p.radius || p.position.dx > _boardSize - margin - p.radius) p.velocity = Offset(-p.velocity.dx, p.velocity.dy);
          if (p.position.dy < margin + p.radius || p.position.dy > _boardSize - margin - p.radius) p.velocity = Offset(p.velocity.dx, -p.velocity.dy);

          // Pockets logic
          final pks = [Offset(margin, margin), Offset(_boardSize-margin, margin), Offset(margin, _boardSize-margin), Offset(_boardSize-margin, _boardSize-margin)];
          for (var pk in pks) {
            if ((p.position - pk).distance < pocketR) {
              p.isPocketed = true;
              if (p.type == PieceType.white) _whiteInHoles++;
              if (p.type == PieceType.black) _blackInHoles++;
              if (p.type == PieceType.striker) _handleFoul();
            }
          }
        }
      }
      
      // Piece to Piece Collision
      for (int i = 0; i < pieces.length; i++) {
        for (int j = i + 1; j < pieces.length; j++) {
          var a = pieces[i]; var b = pieces[j];
          if (a.isPocketed || b.isPocketed) continue;
          double d = (a.position - b.position).distance;
          if (d < a.radius + b.radius) {
            Offset n = (a.position - b.position) / d;
            double p = (a.velocity.dx * n.dx + a.velocity.dy * n.dy) - (b.velocity.dx * n.dx + b.velocity.dy * n.dy);
            a.velocity -= n * p; b.velocity += n * p;
          }
        }
      }
      if (!anyMoving) { _phase = GamePhase.evaluating; _checkStatus(); }
    });
  }

  void _handleFoul() {
    // Return one piece if available
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Striker Foul!"), duration: Duration(seconds: 1)));
  }

  void _checkStatus() {
    if (_whiteInHoles == 9) _gameOver("White Wins!");
    else if (_blackInHoles == 9) _gameOver("Black Wins!");
    else _switchTurn();
  }

  void _gameOver(String msg) {
    _phase = GamePhase.gameOver;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(msg), actions: [TextButton(onPressed: () {Navigator.pop(ctx); _initBoard(_boardSize);}, child: const Text("Play Again"))]));
  }

  void _switchTurn() {
    _currentTurn = _currentTurn == PlayerTurn.whitePlayer ? PlayerTurn.blackPlayer : PlayerTurn.whitePlayer;
    _resetStriker();
    _startTimer();
  }

  void _handleTouch(Offset pos, String type) {
    if (_phase == GamePhase.moving || _phase == GamePhase.gameOver) return;
    var s = pieces.firstWhere((p) => p.type == PieceType.striker);
    if (type == "start" && (pos - s.position).distance < 60) _phase = GamePhase.aiming;
    if (type == "update") {
      if (_phase == GamePhase.placing) {
        s.position = Offset(pos.dx.clamp(_boardSize * 0.25, _boardSize * 0.75), s.position.dy);
      } else { _dragPosition = pos; }
    }
    if (type == "end" && _phase == GamePhase.aiming) {
      s.velocity = (s.position - _dragPosition) * 0.28;
      _phase = GamePhase.moving;
    }
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
                  if (!_isInitialized) _initBoard(constraints.maxWidth);
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
          _buildTurnBanner(),
        ],
      ),
    );
  }

  Widget _buildScoreboard() {
    return Container(
      padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _scoreCard("WHITE", _whiteInHoles, Colors.white),
          _timerCircle(),
          _scoreCard("BLACK", _blackInHoles, Colors.black),
        ],
      ),
    );
  }

  Widget _scoreCard(String title, int val, Color color) {
    return Column(children: [
      Text(title, style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 8),
      Text("$val", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
      const Text("HOLES", style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
    ]);
  }

  Widget _timerCircle() {
    return Stack(alignment: Alignment.center, children: [
      SizedBox(width: 50, height: 50, child: CircularProgressIndicator(value: _timeLeft/30, color: Colors.amber, strokeWidth: 2)),
      Text("$_timeLeft", style: const TextStyle(fontWeight: FontWeight.bold))
    ]);
  }

  Widget _buildTurnBanner() {
    bool isWhite = _currentTurn == PlayerTurn.whitePlayer;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 25),
      decoration: BoxDecoration(color: isWhite ? Colors.white.withOpacity(0.05) : Colors.black45),
      child: Center(child: Text(isWhite ? "WHITE'S TURN" : "BLACK'S TURN", style: TextStyle(letterSpacing: 6, color: isWhite ? Colors.amber : Colors.grey[600], fontWeight: FontWeight.bold))),
    );
  }
}

class CarromUltraPainter extends CustomPainter {
  final List<CarromPiece> pieces;
  final Offset? drag;
  CarromUltraPainter(this.pieces, this.drag);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint();

    // 1. Heavy 3D Wooden Frame
    paint.shader = LinearGradient(colors: [const Color(0xFF2D1B10), const Color(0xFF4E342E)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Rect.fromLTWH(0, 0, w, w));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, w), const Radius.circular(15)), paint);

    // 2. Premium Surface (Beige/Plywood)
    paint.shader = null;
    paint.color = const Color(0xFFF3D5A2);
    final margin = w * 0.075;
    canvas.drawRect(Rect.fromLTWH(margin, margin, w - margin*2, w - margin*2), paint);

    // 3. Ultra Realistic Board Markings (The Image pattern)
    _drawBoardGraphics(canvas, size);

    // 4. Pockets (Depth and Rim)
    final pocketR = w * 0.062;
    final holePos = [Offset(margin, margin), Offset(w-margin, margin), Offset(margin, w-margin), Offset(w-margin, w-margin)];
    for (var pos in holePos) {
      paint.shader = RadialGradient(colors: [Colors.black, Colors.grey[900]!]).createShader(Rect.fromCircle(center: pos, radius: pocketR));
      canvas.drawCircle(pos, pocketR, paint);
      paint.shader = null; paint.style = PaintingStyle.stroke; paint.color = Colors.black45;
      canvas.drawCircle(pos, pocketR, paint);
      paint.style = PaintingStyle.fill;
    }

    // 5. 3D Pieces (Shadows and Gradients)
    for (var p in pieces) {
      if (p.isPocketed) continue;
      
      // Drop shadow for 3D depth
      canvas.drawCircle(p.position + const Offset(2.5, 2.5), p.radius, Paint()..color = Colors.black38..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      
      Color c = p.type == PieceType.white ? Colors.white : (p.type == PieceType.black ? const Color(0xFF1A1A1A) : (p.type == PieceType.queen ? Colors.red[800]! : Colors.blueAccent));
      
      paint.shader = RadialGradient(colors: [c, c.withOpacity(0.7)], center: const Alignment(-0.35, -0.35)).createShader(Rect.fromCircle(center: p.position, radius: p.radius));
      canvas.drawCircle(p.position, p.radius, paint);
      
      // Piece detail
      paint.shader = null; paint.style = PaintingStyle.stroke; paint.strokeWidth = 1;
      paint.color = p.type == PieceType.black ? Colors.white12 : Colors.black12;
      canvas.drawCircle(p.position, p.radius * 0.7, paint);
      paint.style = PaintingStyle.fill;
    }

    // 6. Aiming Guide
    if (drag != null) {
      final s = pieces.firstWhere((p) => p.type == PieceType.striker);
      paint.shader = LinearGradient(colors: [Colors.amber, Colors.amber.withOpacity(0)]).createShader(Rect.fromPoints(s.position, s.position + (s.position - drag!)));
      paint.strokeWidth = 3; paint.style = PaintingStyle.stroke;
      canvas.drawLine(s.position, s.position + (s.position - drag!), paint);
    }
  }

  void _drawBoardGraphics(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 1.2;

    // Baselines (Double lines with Red circles like in your photo)
    final bLine1 = w * 0.185; final bLine2 = w * 0.815;
    _drawBaseLine(canvas, w, bLine1);
    _drawBaseLine(canvas, w, bLine2);
    _drawSideBaseLine(canvas, w, bLine1);
    _drawSideBaseLine(canvas, w, bLine2);

    // Center Flower Pattern
    paint.style = PaintingStyle.stroke; paint.color = Colors.black54;
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.13, paint);
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.135, paint);
    
    // Diagonal Corner Arrows
    _drawCornerArrows(canvas, w);
  }

  void _drawBaseLine(Canvas canvas, double w, double y) {
    final paint = Paint()..color = Colors.black87..strokeWidth = 1.5;
    canvas.drawLine(Offset(w*0.25, y-w*0.012), Offset(w*0.75, y-w*0.012), paint);
    canvas.drawLine(Offset(w*0.25, y+w*0.012), Offset(w*0.75, y+w*0.012), paint);
    // Red circles at ends
    paint.style = PaintingStyle.fill; paint.color = Colors.red[900]!;
    canvas.drawCircle(Offset(w*0.25, y), w*0.018, paint);
    canvas.drawCircle(Offset(w*0.75, y), w*0.018, paint);
  }

  void _drawSideBaseLine(Canvas canvas, double w, double x) {
     final paint = Paint()..color = Colors.black87..strokeWidth = 1.5;
     canvas.drawLine(Offset(x-w*0.012, w*0.25), Offset(x-w*0.012, w*0.75), paint);
     canvas.drawLine(Offset(x+w*0.012, w*0.25), Offset(x+w*0.012, w*0.75), paint);
     paint.style = PaintingStyle.fill; paint.color = Colors.red[900]!;
     canvas.drawCircle(Offset(x, w*0.25), w*0.018, paint);
     canvas.drawCircle(Offset(x, w*0.75), w*0.018, paint);
  }

  void _drawCornerArrows(Canvas canvas, double w) {
    final paint = Paint()..color = Colors.black45..strokeWidth = 1;
    // Four corner diagonal lines
    canvas.drawLine(Offset(w*0.14, w*0.14), Offset(w*0.35, w*0.35), paint);
    canvas.drawLine(Offset(w*0.86, w*0.14), Offset(w*0.65, w*0.35), paint);
    canvas.drawLine(Offset(w*0.14, w*0.86), Offset(w*0.35, w*0.65), paint);
    canvas.drawLine(Offset(w*0.86, w*0.86), Offset(w*0.65, w*0.65), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}