import 'dart:ui';

class ConfettiParticle {
  Offset position;
  Offset velocity;
  Color color;
  double alpha;
  double size;
  double life;
  double maxLife;
  double rotation;
  double rotationSpeed;

  static final Paint _sharedPaint = Paint()..style = PaintingStyle.fill;

  ConfettiParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.maxLife,
    this.size = 6.0,
    this.rotation = 0.0,
    this.rotationSpeed = 0.0,
  })  : alpha = 1.0,
        life = 0.0;

  void update(double dt) {
    life += dt;

    // Gravity pulls particles downward
    velocity = Offset(velocity.dx, velocity.dy + 200 * dt);

    // Air resistance - slow horizontal velocity over time
    velocity = Offset(velocity.dx * (1.0 - 3 * dt), velocity.dy);

    // Update position
    position = Offset(
      position.dx + velocity.dx * dt,
      position.dy + velocity.dy * dt,
    );

    // Update rotation
    rotation += rotationSpeed * dt;

    // Fade out as life decreases
    alpha = (1.0 - (life / maxLife)).clamp(0.0, 1.0);
  }

  bool get isAlive => life < maxLife;

  void draw(Canvas canvas) {
    if (alpha <= 0) return;

    _sharedPaint.color = color.withAlpha((255 * alpha).toInt());

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);

    // Draw a small rectangle confetti piece
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: size,
        height: size * 1.5,
      ),
      _sharedPaint,
    );

    canvas.restore();
  }
}

class ConfettiEmitter {
  final List<ConfettiParticle> particles = [];

  /// Emits a burst of confetti particles from a given position
  void emit({
    required Offset origin,
    required Color baseColor,
    int count = 25,
    double spread = 300,
    double upwardVelocity = -350,
  }) {
    particles.clear();

    final colors = [
      baseColor,
      const Color(0xFFFFD700), // Gold
      baseColor.withAlpha(179),
      const Color(0xFFFFA500), // Orange
    ];

    for (int i = 0; i < count; i++) {
      particles.add(ConfettiParticle(
        position: origin,
        velocity: Offset(
          (i % 11 - 5) * 80.0,
          upwardVelocity - (i % 5) * 40.0,
        ),
        color: colors[i % colors.length],
        maxLife: 1.0 + (i % 10) * 0.1,
        size: 4.0 + (i % 4) * 2.0,
        rotationSpeed: (i % 7 - 3) * 5.0,
      ));
    }
  }

  void update(double dt) {
    int writeIndex = 0;
    for (int i = 0; i < particles.length; i++) {
      final particle = particles[i];
      particle.update(dt);
      if (particle.isAlive) {
        particles[writeIndex++] = particle;
      }
    }
    if (writeIndex < particles.length) {
      particles.length = writeIndex;
    }
  }

  void draw(Canvas canvas) {
    for (final p in particles) {
      p.draw(canvas);
    }
  }

  bool get isActive => particles.isNotEmpty;
}