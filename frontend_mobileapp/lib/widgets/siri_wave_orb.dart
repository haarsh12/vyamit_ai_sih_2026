import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Siri-style animated orb with flowing blobs
/// Animates based on audio level (0.0 to 1.0)
class SiriWaveOrb extends StatefulWidget {
  final bool isActive;
  final double audioLevel;
  final VoidCallback onTap;
  final double size;

  const SiriWaveOrb({
    super.key,
    required this.isActive,
    required this.audioLevel,
    required this.onTap,
    this.size = 200.0,
  });

  @override
  State<SiriWaveOrb> createState() => _SiriWaveOrbState();
}

class _SiriWaveOrbState extends State<SiriWaveOrb>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _breathingController;

  @override
  void initState() {
    super.initState();
    
    // Rotation animation (continuous)
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    // Pulse animation (for active state)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Breathing animation (for idle state)
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(SiriWaveOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _rotationController,
          _pulseController,
          _breathingController,
        ]),
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: SiriWavePainter(
              isActive: widget.isActive,
              audioLevel: widget.audioLevel,
              rotation: _rotationController.value,
              pulse: _pulseController.value,
              breathing: _breathingController.value,
            ),
          );
        },
      ),
    );
  }
}

class SiriWavePainter extends CustomPainter {
  final bool isActive;
  final double audioLevel;
  final double rotation;
  final double pulse;
  final double breathing;

  SiriWavePainter({
    required this.isActive,
    required this.audioLevel,
    required this.rotation,
    required this.pulse,
    required this.breathing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    if (isActive) {
      _drawActiveOrb(canvas, center, baseRadius);
    } else {
      _drawIdleOrb(canvas, center, baseRadius);
    }
  }

  void _drawIdleOrb(Canvas canvas, Offset center, double baseRadius) {
    // Simple breathing circle when idle
    final breathScale = 0.95 + (breathing * 0.1);
    final radius = baseRadius * 0.6 * breathScale;

    // Gradient circle
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF4A5568).withOpacity(0.8),
          const Color(0xFF2D3748).withOpacity(0.6),
          const Color(0xFF1A202C).withOpacity(0.3),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);

    // Outer glow
    final glowPaint = Paint()
      ..color = const Color(0xFF4A5568).withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    
    canvas.drawCircle(center, radius, glowPaint);

    // Mic icon
    _drawMicIcon(canvas, center, radius * 0.4, Colors.white70);
  }

  void _drawActiveOrb(Canvas canvas, Offset center, double baseRadius) {
    // Multiple flowing blobs with different colors
    final blobs = [
      _BlobConfig(
        color: const Color(0xFF06B6D4), // Cyan
        angle: rotation * 2 * math.pi,
        distance: 0.3,
        size: 0.4 + (audioLevel * 0.3),
      ),
      _BlobConfig(
        color: const Color(0xFF8B5CF6), // Purple
        angle: (rotation * 2 * math.pi) + (2 * math.pi / 3),
        distance: 0.25,
        size: 0.35 + (audioLevel * 0.25),
      ),
      _BlobConfig(
        color: const Color(0xFFEC4899), // Pink
        angle: (rotation * 2 * math.pi) + (4 * math.pi / 3),
        distance: 0.28,
        size: 0.38 + (audioLevel * 0.28),
      ),
      _BlobConfig(
        color: const Color(0xFFF59E0B), // Orange
        angle: (rotation * 2 * math.pi) + math.pi,
        distance: 0.22,
        size: 0.32 + (audioLevel * 0.22),
      ),
    ];

    // Draw each blob
    for (final blob in blobs) {
      _drawBlob(canvas, center, baseRadius, blob);
    }

    // Central glow
    final glowRadius = baseRadius * 0.5 * (1.0 + audioLevel * 0.3);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.3),
          Colors.white.withOpacity(0.1),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    
    canvas.drawCircle(center, glowRadius, glowPaint);

    // Outer ring glow
    final outerGlowPaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.3 + audioLevel * 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    
    canvas.drawCircle(
      center,
      baseRadius * 0.7 * (1.0 + pulse * 0.1),
      outerGlowPaint,
    );
  }

  void _drawBlob(Canvas canvas, Offset center, double baseRadius, _BlobConfig config) {
    // Calculate blob position
    final distance = baseRadius * config.distance;
    final x = center.dx + math.cos(config.angle) * distance;
    final y = center.dy + math.sin(config.angle) * distance;
    final blobCenter = Offset(x, y);
    
    // Blob size
    final blobRadius = baseRadius * config.size;

    // Blob gradient
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          config.color.withOpacity(0.8),
          config.color.withOpacity(0.4),
          config.color.withOpacity(0.0),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: blobCenter, radius: blobRadius));

    // Draw blob with blur
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);
    canvas.drawCircle(blobCenter, blobRadius, paint);
  }

  void _drawMicIcon(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Mic body (rounded rectangle)
    final micRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - size * 0.15),
        width: size * 0.5,
        height: size * 0.7,
      ),
      Radius.circular(size * 0.25),
    );
    canvas.drawRRect(micRect, paint);

    // Mic stand
    final standPath = Path()
      ..moveTo(center.dx, center.dy + size * 0.35)
      ..lineTo(center.dx, center.dy + size * 0.6)
      ..moveTo(center.dx - size * 0.25, center.dy + size * 0.6)
      ..lineTo(center.dx + size * 0.25, center.dy + size * 0.6);
    
    canvas.drawPath(standPath, paint);

    // Mic arc (sound waves)
    final arcRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - size * 0.15),
      width: size * 0.9,
      height: size * 0.9,
    );
    
    canvas.drawArc(
      arcRect,
      math.pi * 0.2,
      math.pi * 0.6,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(SiriWavePainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.audioLevel != audioLevel ||
        oldDelegate.rotation != rotation ||
        oldDelegate.pulse != pulse ||
        oldDelegate.breathing != breathing;
  }
}

class _BlobConfig {
  final Color color;
  final double angle;
  final double distance;
  final double size;

  _BlobConfig({
    required this.color,
    required this.angle,
    required this.distance,
    required this.size,
  });
}
