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
      title: 'Carrom Blitz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown)),
      home: const CarromHomePage(),
    );
  }
}

// --- DATA MODEL FOR CARROM PIECES ---
class CarromPiece {
  Offset position;
  Offset velocity;
  final double radius;
  final Color color;
  final bool isStriker;
  bool isPocketed = false;

  CarromPiece({
    required this.position,
    this.velocity = Offset.zero,
    required this.radius,
    required this.color,
    this.isStriker = false,
  });
}

class CarromHomePage extends StatefulWidget {
  const CarromHomePage({super.key});

  @override
  State<CarromHomePage> createState() => _CarromHomePageState();
}

// Notice the SingleTickerProviderStateMixin: This gives us the 60fps Game Loop!
class _CarromHomePageState extends State<CarromHomePage> with SingleTickerProviderStateMixin {
  late AnimationController _gameLoop;
  
  // Board & Physics State
  bool _isInitialized = false;
  double _boardSize = 0;
  List<CarromPiece> pieces = [];
  
  // Interaction State
  bool _isAiming = false;
  Offset _dragPosition = Offset.zero;
  CarromPiece? _striker;

  @override
  void initState() {
    super.initState();
    // The game loop runs constantly, updating physics
    _gameLoop = AnimationController(vsync: this, duration: const Duration(days: 365))
      ..addListener(_updatePhysics)
      ..forward();
  }

  // --- 1. SETUP THE BOARD ---
  void _initBoard(double size) {
    _boardSize = size;
    final center = Offset(size / 2, size / 2);
    final pieceRadius = size * 0.03;
    final strikerRadius = size * 0.045;

    pieces.clear();

    // Queen (Red)
    pieces.add(CarromPiece(position: center, radius: pieceRadius, color: Colors.red[700]!));

    // Whites and Blacks around the Queen
    final offsetDist = pieceRadius * 2.1;
    final positions = [
      Offset(center.dx, center.dy - offsetDist), // Top
      Offset(center.dx, center.dy + offsetDist), // Bottom
      Offset(center.dx - offsetDist, center.dy), // Left
      Offset(center.dx + offsetDist, center.dy), // Right
    ];
    
    for (int i = 0; i < positions.length; i++) {
      pieces.add(CarromPiece(
        position: positions[i], 
        radius: pieceRadius, 
        color: i % 2 == 0 ? Colors.white : Colors.black87,
      ));
    }

    // Striker at the bottom baseline
    _striker = CarromPiece(
      position: Offset(center.dx, size * 0.8),
      radius: strikerRadius,
      color: Colors.amber[200]!,
      isStriker: true,
    );
    pieces.add(_striker!);

    _isInitialized = true;
  }

  // --- 2. GAME LOOP & PHYSICS ---
  void _updatePhysics() {
    if (!_isInitialized) return;

    final frameThickness = _boardSize * 0.06;
    final minBound = frameThickness;
    final maxBound = _boardSize - frameThickness;
    final pocketRadius = _boardSize * 0.055;
    
    // Pocket Centers
    final pockets = [
      Offset(minBound, minBound),
      Offset(maxBound, minBound),
      Offset(minBound, maxBound),
      Offset(maxBound, maxBound),
    ];

    setState(() {
      for (int i = 0; i < pieces.length; i++) {
        var p = pieces[i];
        if (p.isPocketed) continue;

        // Apply Velocity
        p.position += p.velocity;
        
        // Apply Friction (Slows down over time)
        p.velocity *= 0.98; 
        if (p.velocity.distance < 0.1) p.velocity = Offset.zero;

        // Wall Bouncing
        if (p.position.dx - p.radius < minBound) {
          p.position = Offset(minBound + p.radius, p.position.dy);
          p.velocity = Offset(-p.velocity.dx, p.velocity.dy);
        } else if (p.position.dx + p.radius > maxBound) {
          p.position = Offset(maxBound - p.radius, p.position.dy);
          p.velocity = Offset(-p.velocity.dx, p.velocity.dy);
        }
        
        if (p.position.dy - p.radius < minBound) {
          p.position = Offset(p.position.dx, minBound + p.radius);
          p.velocity = Offset(p.velocity.dx, -p.velocity.dy);
        } else if (p.position.dy + p.radius > maxBound) {
          p.position = Offset(p.position.dx, maxBound - p.radius);
          p.velocity = Offset(p.velocity.dx, -p.velocity.dy);
        }

        // Check if fallen into a pocket
        for (var pocket in pockets) {
          if ((p.position - pocket).distance < pocketRadius) {
            if (p.isStriker) {
              // Foul! Reset striker
              p.position = Offset(_boardSize / 2, _boardSize * 0.8);
              p.velocity = Offset.zero;
            } else {
              p.isPocketed = true;
            }
          }
        }

        // Piece-to-Piece Collisions
        for (int j = i + 1; j < pieces.length; j++) {
          var p2 = pieces[j];
          if (p2.isPocketed) continue;

          Offset delta = p.position - p2.position;
          double dist = delta.distance;
          double minFocalDist = p.radius + p2.radius;

          if (dist < minFocalDist && dist > 0) {
            // Push pieces apart so they don't get stuck inside each other
            double overlap = minFocalDist - dist;
            Offset push = (delta / dist) * (overlap / 2);
            p.position += push;
            p2.position -= push;

            // Transfer Momentum (Elastic Collision)
            Offset normal = delta / dist;
            double p1VelAlongNormal = p.velocity.dx * normal.dx + p.velocity.dy * normal.dy;
            double p2VelAlongNormal = p2.velocity.dx * normal.dx + p2.velocity.dy * normal.dy;

            double restitution = 0.9; // Bounciness
            double impulse = (p1VelAlongNormal - p2VelAlongNormal) * restitution;

            p.velocity -= normal * impulse;
            p2.velocity += normal * impulse;
          }
        }
      }
    });
  }

  // --- 3. CONTROLS (SLINGSHOT) ---
  void _onPanStart(DragStartDetails details) {
    if (_striker == null) return;
    // Check if touching the striker
    if ((details.localPosition - _striker!.position).distance < _striker!.radius * 2) {
      _isAiming = true;
      _dragPosition = details.localPosition;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isAiming) {
      setState(() {
        _dragPosition = details.localPosition;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isAiming && _striker != null) {
      // Calculate slingshot velocity (opposite of drag direction)
      Offset pullVector = _striker!.position - _dragPosition;
      
      // Cap the maximum power
      if (pullVector.distance > 100) {
        pullVector = (pullVector / pullVector.distance) * 100;
      }
      
      _striker!.velocity = pullVector * 0.3; // 0.3 is the power multiplier
      _isAiming = false;
    }
  }

  @override
  void dispose() {
    _gameLoop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Carrom Play', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.brown[900],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!_isInitialized) {
                  // Initialize board pieces only once we know the exact screen pixel width
                  _initBoard(constraints.maxWidth);
                }

                return GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxWidth),
                    painter: CarromBoardPainter(
                      pieces: pieces,
                      aimingStart: _isAiming ? _striker?.position : null,
                      aimingEnd: _isAiming ? _dragPosition : null,
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

// --- 4. DRAWING THE BOARD AND PIECES ---
class CarromBoardPainter extends CustomPainter {
  final List<CarromPiece> pieces;
  final Offset? aimingStart;
  final Offset? aimingEnd;

  CarromBoardPainter({required this.pieces, this.aimingStart, this.aimingEnd});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final paint = Paint();

    // 1. Board Wood Frame
    paint.color = const Color(0xFF4A2F1D);
    paint.style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, width), paint);

    // 2. Play Surface
    final frameThickness = width * 0.06;
    paint.color = const Color(0xFFF3E5AB);
    canvas.drawRect(
      Rect.fromLTWH(frameThickness, frameThickness, width - (frameThickness * 2), width - (frameThickness * 2)),
      paint,
    );

    // 3. Pockets
    paint.color = Colors.black;
    final pocketRadius = width * 0.045;
    final pocketOffset = frameThickness + pocketRadius + (width * 0.01);
    final offsets = [
      Offset(pocketOffset, pocketOffset),
      Offset(width - pocketOffset, pocketOffset),
      Offset(pocketOffset, width - pocketOffset),
      Offset(width - pocketOffset, width - pocketOffset),
    ];
    for (var offset in offsets) canvas.drawCircle(offset, pocketRadius, paint);

    // Center Circles
    final center = Offset(width / 2, width / 2);
    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.0;
    canvas.drawCircle(center, width * 0.12, paint);
    canvas.drawCircle(center, width * 0.03, paint);

    // 4. Draw Aiming Line (Slingshot)
    if (aimingStart != null && aimingEnd != null) {
      paint.color = Colors.blueAccent.withOpacity(0.5);
      paint.strokeWidth = 4.0;
      // Draw line from striker in the OPPOSITE direction of the drag
      Offset pullVector = aimingStart! - aimingEnd!;
      canvas.drawLine(aimingStart!, aimingStart! + pullVector, paint);
    }

    // 5. Draw the Carrom Pieces
    paint.style = PaintingStyle.fill;
    for (var piece in pieces) {
      if (piece.isPocketed) continue; // Don't draw if it fell in a hole!
      
      paint.color = piece.color;
      canvas.drawCircle(piece.position, piece.radius, paint);
      
      // Draw an inner ring on the pieces to make them look 3D/realistic
      paint.color = Colors.white.withOpacity(0.3);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2.0;
      canvas.drawCircle(piece.position, piece.radius * 0.7, paint);
      paint.style = PaintingStyle.fill; // Reset for next piece
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true; // Always repaint for 60fps
}