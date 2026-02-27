import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Responsive Pro Carrom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown)),
      home: const CarromMatch(),
    );
  }
}

enum PieceType { white, black, queen, striker }
enum PlayerTurn { whitePlayer, blackPlayer }
enum GamePhase { placingStriker, aiming, moving, evaluating }

class CarromPiece {
  Offset position;
  Offset velocity;
  final double radius;
  final Color color;
  final PieceType type;
  bool isPocketed = false;

  CarromPiece({
    required this.position,
    this.velocity = Offset.zero,
    required this.radius,
    required this.color,
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
  CarromPiece? _striker;
  
  PlayerTurn _currentTurn = PlayerTurn.whitePlayer;
  GamePhase _phase = GamePhase.placingStriker;
  
  // Game State for Rules
  int _whiteScore = 0;
  int _blackScore = 0;
  bool _queenPocketedThisTurn = false;
  bool _queenWaitingForCover = false;
  PlayerTurn? _queenPocketedBy;
  
  int _timeLeft = 30;
  Timer? _turnTimer;
  Offset _dragPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _gameLoop = AnimationController(vsync: this, duration: const Duration(days: 365))
      ..addListener(_updatePhysics)
      ..forward();
  }

  void _startTimer() {
    _turnTimer?.cancel();
    _timeLeft = 30;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_phase == GamePhase.moving || _phase == GamePhase.evaluating) return;
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          _switchTurn(timeOut: true);
        }
      });
    });
  }

  // --- RESPONSIVE INITIALIZATION ---
  void _initBoard(double size) {
    _boardSize = size;
    final center = Offset(size * 0.5, size * 0.5);
    final pieceRadius = size * 0.028; 
    pieces.clear();

    // Queen
    pieces.add(CarromPiece(position: center, radius: pieceRadius, color: Colors.red[700]!, type: PieceType.queen));

    // Inner Circle (6 pieces)
    final innerDist = pieceRadius * 2.1;
    for (int i = 0; i < 6; i++) {
      double angle = i * (pi / 3);
      pieces.add(CarromPiece(
        position: Offset(center.dx + cos(angle) * innerDist, center.dy + sin(angle) * innerDist),
        radius: pieceRadius, 
        color: i % 2 == 0 ? Colors.white : Colors.black87, 
        type: i % 2 == 0 ? PieceType.white : PieceType.black,
      ));
    }

    // Outer Circle (12 pieces)
    final outerDist = pieceRadius * 4.2;
    for (int i = 0; i < 12; i++) {
      double angle = i * (pi / 6) + (pi / 12);
      pieces.add(CarromPiece(
        position: Offset(center.dx + cos(angle) * outerDist, center.dy + sin(angle) * outerDist),
        radius: pieceRadius, 
        color: i % 2 == 0 ? Colors.black87 : Colors.white, 
        type: i % 2 == 0 ? PieceType.black : PieceType.white,
      ));
    }

    _resetStriker();
    _isInitialized = true;
    _startTimer();
  }

  void _resetStriker() {
    final strikerRadius = _boardSize * 0.045;
    double yPos = _currentTurn == PlayerTurn.whitePlayer ? _boardSize * 0.82 : _boardSize * 0.18;
    
    _striker = CarromPiece(
      position: Offset(_boardSize * 0.5, yPos),
      radius: strikerRadius,
      color: Colors.amber[200]!,
      type: PieceType.striker,
    );
    pieces.removeWhere((p) => p.type == PieceType.striker);
    pieces.add(_striker!);
    _phase = GamePhase.placingStriker;
  }

  // --- PHYSICS & COLLISION ---
  void _updatePhysics() {
    if (!_isInitialized || _phase != GamePhase.moving) return;

    bool anyMoving = false;
    final minBound = _boardSize * 0.06;
    final maxBound = _boardSize - minBound;
    final pocketRadius = _boardSize * 0.065;
    final stopThreshold = _boardSize * 0.0005;

    final pockets = [
      Offset(minBound, minBound), Offset(maxBound, minBound),
      Offset(minBound, maxBound), Offset(maxBound, maxBound),
    ];

    setState(() {
      for (int i = 0; i < pieces.length; i++) {
        var p = pieces[i];
        if (p.isPocketed) continue;

        if (p.velocity.distance > stopThreshold) {
          anyMoving = true;
          p.position += p.velocity;
          p.velocity *= 0.982; // Friction

          // Wall Collisions
          if (p.position.dx - p.radius < minBound || p.position.dx + p.radius > maxBound) {
            p.velocity = Offset(-p.velocity.dx, p.velocity.dy);
            p.position = Offset(p.position.dx.clamp(minBound + p.radius, maxBound - p.radius), p.position.dy);
          }
          if (p.position.dy - p.radius < minBound || p.position.dy + p.radius > maxBound) {
            p.velocity = Offset(p.velocity.dx, -p.velocity.dy);
            p.position = Offset(p.position.dx, p.position.dy.clamp(minBound + p.radius, maxBound - p.radius));
          }

          // Pocket Detection
          for (var pocket in pockets) {
            if ((p.position - pocket).distance < pocketRadius) {
              p.isPocketed = true;
              p.velocity = Offset.zero;
              _handlePocketing(p);
            }
          }
        } else {
          p.velocity = Offset.zero;
        }

        // Piece to Piece Collision
        for (int j = i + 1; j < pieces.length; j++) {
          var p2 = pieces[j];
          if (p2.isPocketed) continue;

          Offset delta = p.position - p2.position;
          double dist = delta.distance;
          double minDist = p.radius + p2.radius;

          if (dist < minDist && dist > 0) {
            // Static resolution (no overlap)
            Offset resolve = delta * (minDist - dist) / dist;
            p.position += resolve * 0.5;
            p2.position -= resolve * 0.5;

            // Elastic Collision
            Offset normal = delta / dist;
            double p1V = p.velocity.dx * normal.dx + p.velocity.dy * normal.dy;
            double p2V = p2.velocity.dx * normal.dx + p2.velocity.dy * normal.dy;
            double impulse = (p1V - p2V) * 0.9;
            p.velocity -= normal * impulse;
            p2.velocity += normal * impulse;
          }
        }
      }

      if (!anyMoving) {
        _phase = GamePhase.evaluating;
        _evaluateTurnEnd();
      }
    });
  }

  // --- RULE LOGIC ---
  bool _strikerFouledThisTurn = false;
  int _ownPiecesPocketed = 0;

  void _handlePocketing(CarromPiece p) {
    if (p.type == PieceType.striker) {
      _strikerFouledThisTurn = true;
    } else if (p.type == PieceType.queen) {
      _queenPocketedThisTurn = true;
      _queenPocketedBy = _currentTurn;
    } else {
      bool isOwn = (_currentTurn == PlayerTurn.whitePlayer && p.type == PieceType.white) ||
                   (_currentTurn == PlayerTurn.blackPlayer && p.type == PieceType.black);
      if (isOwn) {
        _ownPiecesPocketed++;
        if (_currentTurn == PlayerTurn.whitePlayer) _whiteScore++; else _blackScore++;
      }
    }
  }

  void _evaluateTurnEnd() {
    bool keepTurn = false;

    // 1. Foul Penalty (Striker Pocketed)
    if (_strikerFouledThisTurn) {
      _applyFoulPenalty();
      keepTurn = false;
    } 
    // 2. Queen Logic
    else if (_queenPocketedThisTurn) {
      _queenWaitingForCover = true;
      keepTurn = true; // Must try to cover
    } 
    else if (_queenWaitingForCover) {
      if (_ownPiecesPocketed > 0) {
        _queenWaitingForCover = false; // COVERED!
        if (_currentTurn == PlayerTurn.whitePlayer) _whiteScore += 3; else _blackScore += 3;
        keepTurn = true;
      } else {
        _returnQueenToCenter();
        _queenWaitingForCover = false;
        keepTurn = false;
      }
    }
    // 3. Standard Pocketing
    else if (_ownPiecesPocketed > 0) {
      keepTurn = true;
    }

    // Reset Turn Params
    _strikerFouledThisTurn = false;
    _ownPiecesPocketed = 0;
    _queenPocketedThisTurn = false;

    if (keepTurn) {
      _resetStriker();
      _startTimer();
    } else {
      _switchTurn();
    }
  }

  void _applyFoulPenalty() {
    // Return one pocketed piece to center (simplified logic)
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("FOUL! Striker Pocketed.")));
  }

  void _returnQueenToCenter() {
    var queen = pieces.firstWhere((p) => p.type == PieceType.queen);
    queen.isPocketed = false;
    queen.position = Offset(_boardSize * 0.5, _boardSize * 0.5);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Queen NOT covered. Returned to center.")));
  }

  void _switchTurn({bool timeOut = false}) {
    if (timeOut) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Time Out!")));
    setState(() {
      _currentTurn = _currentTurn == PlayerTurn.whitePlayer ? PlayerTurn.blackPlayer : PlayerTurn.whitePlayer;
      _resetStriker();
      _startTimer();
    });
  }

  // --- TOUCH CONTROLS ---
  void _onPanStart(DragStartDetails details) {
    if (_phase == GamePhase.moving) return;
    if ((details.localPosition - _striker!.position).distance < _striker!.radius * 3) {
      _phase = GamePhase.aiming;
      _dragPosition = details.localPosition;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_phase == GamePhase.placingStriker) {
      double minX = _boardSize * 0.22;
      double maxX = _boardSize * 0.78;
      setState(() {
        _striker!.position = Offset(details.localPosition.dx.clamp(minX, maxX), _striker!.position.dy);
      });
    } else if (_phase == GamePhase.aiming) {
      setState(() { _dragPosition = details.localPosition; });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_phase == GamePhase.aiming) {
      Offset force = _striker!.position - _dragPosition;
      double maxPull = _boardSize * 0.3;
      if (force.distance > maxPull) force = (force / force.distance) * maxPull;
      
      _striker!.velocity = force * 0.35;
      _phase = GamePhase.moving;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text('W: $_whiteScore | B: $_blackScore | ${_currentTurn.name.toUpperCase()}', 
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.brown[900],
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 20), child: Text("Time: $_timeLeft")))],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800), // Max for desktop
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!_isInitialized || _boardSize != constraints.maxWidth) {
                  _initBoard(constraints.maxWidth);
                }
                return GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    painter: CarromBoardPainter(
                      pieces: pieces,
                      aimingStart: _phase == GamePhase.aiming ? _striker?.position : null,
                      aimingEnd: _phase == GamePhase.aiming ? _dragPosition : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class CarromBoardPainter extends CustomPainter {
  final List<CarromPiece> pieces;
  final Offset? aimingStart;
  final Offset? aimingEnd;
  CarromBoardPainter({required this.pieces, this.aimingStart, this.aimingEnd});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint();

    // 1. Draw Frame
    paint.color = const Color(0xFF3E2723);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, w), paint);
    
    // 2. Playing Surface
    paint.color = const Color(0xFFF5DEB3);
    final innerMargin = w * 0.06;
    canvas.drawRect(Rect.fromLTWH(innerMargin, innerMargin, w - innerMargin * 2, w - innerMargin * 2), paint);

    // 3. Pockets
    paint.color = Colors.black87;
    final pr = w * 0.065;
    canvas.drawCircle(Offset(innerMargin, innerMargin), pr, paint);
    canvas.drawCircle(Offset(w - innerMargin, innerMargin), pr, paint);
    canvas.drawCircle(Offset(innerMargin, w - innerMargin), pr, paint);
    canvas.drawCircle(Offset(w - innerMargin, w - innerMargin), pr, paint);

    // 4. Baseline (Visual guides)
    paint.color = Colors.black38;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawLine(Offset(w * 0.22, w * 0.82), Offset(w * 0.78, w * 0.82), paint);
    canvas.drawLine(Offset(w * 0.22, w * 0.18), Offset(w * 0.78, w * 0.18), paint);

    // 5. Center Circle
    canvas.drawCircle(Offset(w * 0.5, w * 0.5), w * 0.15, paint);

    // 6. Aiming Line
    if (aimingStart != null && aimingEnd != null) {
      paint.color = Colors.redAccent.withOpacity(0.6);
      paint.strokeWidth = 3;
      Offset dir = aimingStart! - aimingEnd!;
      canvas.drawLine(aimingStart!, aimingStart! + dir, paint);
    }

    // 7. Pieces
    paint.style = PaintingStyle.fill;
    for (var piece in pieces) {
      if (piece.isPocketed) continue;
      paint.color = piece.color;
      canvas.drawCircle(piece.position, piece.radius, paint);
      
      // Piece detail
      paint.color = Colors.white.withOpacity(0.2);
      paint.style = PaintingStyle.stroke;
      canvas.drawCircle(piece.position, piece.radius * 0.7, paint);
      paint.style = PaintingStyle.fill;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}