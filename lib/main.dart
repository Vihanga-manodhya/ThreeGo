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
    final pr = size * 0.026; 
    pieces.clear();
    _whiteInHoles = 0;
    _blackInHoles = 0;
    
    // Queen
    pieces.add(CarromPiece(position: center, radius: pr, type: PieceType.queen));
    
    // Standard Piece Arrangement
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
    final pocketR = _boardSize * 0.065;
    final margin = _boardSize * 0.075;

    setState(() {
      for (var p in pieces) {
        if (p.isPocketed) continue;
        if (p.velocity.distance > 0.1) {
          anyMoving = true;
          p.position += p.velocity;
          p.velocity *= 0.985; 

          // Wall Collisions
          if (p.position.dx < margin + p.radius || p.position.dx > _boardSize - margin - p.radius) p.velocity = Offset(-p.velocity.dx, p.velocity.dy);
          if (p.position.dy < margin + p.radius || p.position.dy > _boardSize - margin - p.radius) p.velocity = Offset(p.velocity.dx, -p.velocity.dy);

          // Pocketing
          final pks = [Offset(margin, margin), Offset(_boardSize-margin, margin), Offset(margin, _boardSize-margin), Offset(_boardSize-margin, _boardSize-margin)];
          for (var pk in pks) {
            if ((p.position - pk).distance < pocketR) {
              p.isPocketed = true;
              if (p.type == PieceType.white) _whiteInHoles++;
              if (p.type == PieceType.black) _blackInHoles++;
            }
          }
        }
      }
      
      // Piece Collisions
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

  void _checkStatus() {
    if (_whiteInHoles == 9) _gameOver("White Wins!");
    else if (_blackInHoles == 9) _gameOver("Black Wins!");
    else _switchTurn();
  }

  void _gameOver(String msg) {
    _phase = GamePhase.gameOver;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(msg), actions: [TextButton(onPressed: () {Navigator.pop(ctx); _initBoard(_boardSize);}, child: const Text("Restart"))]));
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
      backgroundColor: const Color(0xFF1A1A1A),
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
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildScoreboard() {
    return Container(
      padding: const EdgeInsets.only(top: 60, bottom: 20, left: 30, right: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat("WHITE", _whiteInHoles, Colors.white),
          _timer(),
          _stat("BLACK", _blackInHoles, Colors.black),
        ],
      ),
    );
  }

  Widget _stat(String label, int count, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
      Text("$count", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: color == Colors.white ? Colors.white : Colors.grey[400])),
    ]);
  }

  Widget _timer() {
    return Stack(alignment: Alignment.center, children: [
      SizedBox(width: 50, height: 50, child: CircularProgressIndicator(value: _timeLeft/30, color: Colors.amber, strokeWidth: 3)),
      Text("$_timeLeft", style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 25),
      child: Text(_currentTurn == PlayerTurn.whitePlayer ? "WHITE PLAYER" : "BLACK PLAYER", 
        style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, color: Colors.amber[100])),
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

    // 1. Solid Beveled Frame
    paint.shader = const LinearGradient(
      colors: [Color(0xFF3E2723), Color(0xFF1B0000)],
      begin: Alignment.topLeft, end: Alignment.bottomRight
    ).createShader(Rect.fromLTWH(0, 0, w, w));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, w), const Radius.circular(15)), paint);

    // 2. High-Grade Plywood Surface
    paint.shader = null;
    paint.color = const Color(0xFFF3D5A2);
    final margin = w * 0.075;
    canvas.drawRect(Rect.fromLTWH(margin, margin, w - margin*2, w - margin*2), paint);

    // 3. Realistic Board Markings (The Arcs, Arrows, and Baselines)
    _drawBoardDesign(canvas, w);

    // 4. Pockets (Depth and Shadows)
    final pR = w * 0.065;
    final hPos = [Offset(margin, margin), Offset(w-margin, margin), Offset(margin, w-margin), Offset(w-margin, w-margin)];
    for (var pos in hPos) {
      paint.shader = RadialGradient(colors: [Colors.black, Colors.grey[900]!]).createShader(Rect.fromCircle(center: pos, radius: pR));
      canvas.drawCircle(pos, pR, paint);
      paint.shader = null; paint.style = PaintingStyle.stroke; paint.color = Colors.black45; paint.strokeWidth = 2;
      canvas.drawCircle(pos, pR, paint);
      paint.style = PaintingStyle.fill;
    }

    // 5. 3D SOLID RINGED PIECES (Design Match)
    for (var p in pieces) {
      if (p.isPocketed) continue;
      _drawPiece(canvas, p);
    }

    // 6. Aim Line
    if (drag != null) {
      final s = pieces.firstWhere((p) => p.type == PieceType.striker);
      paint.color = Colors.white54; paint.strokeWidth = 2; paint.style = PaintingStyle.stroke;
      canvas.drawLine(s.position, s.position + (s.position - drag!), paint);
    }
  }

  void _drawPiece(Canvas canvas, CarromPiece p) {
    final paint = Paint();
    
    // Contact Shadow
    canvas.drawCircle(p.position + const Offset(1.5, 1.5), p.radius, Paint()..color = Colors.black45..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    
    Color base;
    switch (p.type) {
      case PieceType.white: base = const Color(0xFFF5F5F5); break;
      case PieceType.black: base = const Color(0xFF212121); break;
      case PieceType.queen: base = const Color(0xFFFF4081); break;
      case PieceType.striker: base = const Color(0xFF1E88E5); break;
    }

    // Main Body Gradient
    paint.shader = RadialGradient(
      colors: [base.withOpacity(1.0), base.withOpacity(0.8)],
      center: const Alignment(-0.3, -0.3),
    ).createShader(Rect.fromCircle(center: p.position, radius: p.radius));
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(p.position, p.radius, paint);

    // Specular Highlight (The Glint)
    paint.shader = null;
    paint.color = Colors.white.withOpacity(0.4);
    canvas.drawCircle(p.position + Offset(-p.radius*0.35, -p.radius*0.35), p.radius * 0.2, paint);

    // 3D Concentric Rings (As seen in reference image)
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.2;
    paint.color = p.type == PieceType.black ? Colors.white12 : Colors.black12;
    canvas.drawCircle(p.position, p.radius * 0.8, paint);
    canvas.drawCircle(p.position, p.radius * 0.6, paint);
    canvas.drawCircle(p.position, p.radius * 0.4, paint);
    canvas.drawCircle(p.position, p.radius * 0.2, paint);
    paint.style = PaintingStyle.fill;
  }

  void _drawBoardDesign(Canvas canvas, double w) {
    final paint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 1.2;

    // Center Flower
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.13, paint);
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.135, paint);
    paint.color = Colors.red[900]!;
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w*0.5, w*0.5), w*0.035, paint);

    // Baselines & Arcs (Design Match)
    _drawSideGraphics(canvas, w, 0); // Bottom
    _drawSideGraphics(canvas, w, pi / 2); // Left
    _drawSideGraphics(canvas, w, pi); // Top
    _drawSideGraphics(canvas, w, 3 * pi / 2); // Right
  }

  void _drawSideGraphics(Canvas canvas, double w, double rotation) {
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(rotation);
    canvas.translate(-w / 2, -w / 2);

    final paint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final y = w * 0.815;

    // Double Baseline
    canvas.drawLine(Offset(w*0.25, y-w*0.012), Offset(w*0.75, y-w*0.012), paint);
    canvas.drawLine(Offset(w*0.25, y+w*0.012), Offset(w*0.75, y+w*0.012), paint);

    // Baseline End Circles
    paint.style = PaintingStyle.fill; paint.color = Colors.red[800]!;
    canvas.drawCircle(Offset(w*0.25, y), w*0.018, paint);
    canvas.drawCircle(Offset(w*0.75, y), w*0.018, paint);

    // Corner Arcs & Arrows
    paint.style = PaintingStyle.stroke; paint.color = Colors.black87;
    // The "U" shape arc near pockets
    final arcRect = Rect.fromCircle(center: Offset(w*0.19, w*0.81), radius: w*0.08);
    canvas.drawArc(arcRect, 0, pi, false, paint);
    
    // Arrows pointing to pockets
    canvas.drawLine(Offset(w*0.13, w*0.87), Offset(w*0.08, w*0.92), paint);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}