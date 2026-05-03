import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/game.dart';
import 'package:sandfall/theme/theme.dart';

class TutorialOverlay extends StatefulWidget {
  final SandGame game;

  const TutorialOverlay({super.key, required this.game});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late final List<_TutorialPageData> _pages = [
    const _TutorialPageData(
      title: 'PLACE PIECES',
      description: 'Tap where you want the NEXT piece to land.',
      bullets: [
        'Preview shows your upcoming shape and color.',
        'Place pieces to build paths and supports.',
      ],
      demo: _TutorialDemoType.placement,
    ),
    const _TutorialPageData(
      title: 'GRAVITY',
      description: 'Sand falls and settles as clusters under gravity.',
      bullets: [
        'Unsupported grains drop down.',
        'Stacks can fragment and settle into new shapes.',
      ],
      demo: _TutorialDemoType.gravity,
    ),
    const _TutorialPageData(
      title: 'BRIDGE RULE',
      description: 'Only one color must connect left edge to right edge.',
      bullets: [
        'Mixed colors touching both sides do not clear.',
        'A continuous same-color bridge is required.',
      ],
      demo: _TutorialDemoType.bridgeRule,
    ),
    const _TutorialPageData(
      title: 'CLEARING',
      description: 'When a same-color bridge spans both edges, it clears.',
      bullets: [
        'Only that color bridge disappears.',
        'After clearing, gravity reshapes the pile.',
      ],
      demo: _TutorialDemoType.bridgeClear,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeTutorial() {
    widget.game.overlays.remove(GameConfig.tutorialOverlay);
  }

  void _goToPage(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isFirst = _currentPage == 0;
    final isLast = _currentPage == _pages.length - 1;

    return Material(
      color: Colors.black.withAlpha(190),
      child: SafeArea(
        child: Center(
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxWidth: 430),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: SandColors.darkBg.withAlpha(245),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SandColors.deepSand, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        page.title,
                        style: const TextStyle(
                          color: SandColors.primaryGold,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    _RoundActionButton(
                      icon: Icons.close,
                      tooltip: 'Close tutorial',
                      onPressed: _closeTutorial,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  page.description,
                  style: const TextStyle(
                    color: SandColors.lightSand,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 178,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return _TutorialDemoCard(type: _pages[index].demo);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x33231B12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SandColors.deepSand.withAlpha(120)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < page.bullets.length; i++) ...[
                        _TutorialBullet(text: page.bullets[i]),
                        if (i != page.bullets.length - 1) const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: isFirst ? null : () => _goToPage(_currentPage - 1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SandColors.lightSand,
                        side: BorderSide(color: SandColors.deepSand.withAlpha(180)),
                      ),
                      child: const Text('BACK'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < _pages.length; i++)
                            _PageDot(active: i == _currentPage),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: SandColors.primaryGold,
                        foregroundColor: SandColors.darkBg,
                      ),
                      onPressed: isLast ? _closeTutorial : () => _goToPage(_currentPage + 1),
                      child: Text(isLast ? 'DONE' : 'NEXT'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  final bool active;

  const _PageDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 16 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? SandColors.primaryGold : SandColors.deepSand.withAlpha(150),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

enum _TutorialDemoType { placement, gravity, bridgeRule, bridgeClear }

class _TutorialPageData {
  final String title;
  final String description;
  final List<String> bullets;
  final _TutorialDemoType demo;

  const _TutorialPageData({
    required this.title,
    required this.description,
    required this.bullets,
    required this.demo,
  });
}

class _TutorialDemoCard extends StatefulWidget {
  final _TutorialDemoType type;

  const _TutorialDemoCard({required this.type});

  @override
  State<_TutorialDemoCard> createState() => _TutorialDemoCardState();
}

class _TutorialDemoCardState extends State<_TutorialDemoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0D0A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SandColors.deepSand.withAlpha(120)),
          ),
          padding: const EdgeInsets.all(10),
          child: CustomPaint(
            painter: _TutorialDemoPainter(
              progress: _controller.value,
              type: widget.type,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _TutorialDemoPainter extends CustomPainter {
  static const int cols = 14;
  static const int rows = 8;

  final double progress;
  final _TutorialDemoType type;

  _TutorialDemoPainter({required this.progress, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    _paintGrid(canvas, size);

    switch (type) {
      case _TutorialDemoType.placement:
        _paintPlacement(canvas, size, cellW, cellH);
        break;
      case _TutorialDemoType.gravity:
        _paintGravity(canvas, size, cellW, cellH);
        break;
      case _TutorialDemoType.bridgeRule:
        _paintBridgeRule(canvas, size, cellW, cellH);
        break;
      case _TutorialDemoType.bridgeClear:
        _paintBridgeClear(canvas, size, cellW, cellH);
        break;
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF15110C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      bgPaint,
    );

    final gridLine = Paint()
      ..color = SandColors.deepSand.withAlpha(42)
      ..strokeWidth = 1;

    for (int x = 0; x <= cols; x++) {
      final dx = x * (size.width / cols);
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridLine);
    }
    for (int y = 0; y <= rows; y++) {
      final dy = y * (size.height / rows);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridLine);
    }
  }

  void _paintPlacement(Canvas canvas, Size size, double cellW, double cellH) {
    final color = Colors.orangeAccent;

    final targetX = 7.0;
    final dropStartY = 1.0;
    final dropEndY = 5.0;

    final t = Curves.easeInOut.transform(progress);
    final currentY = dropStartY + (dropEndY - dropStartY) * t;

    final guidePaint = Paint()
      ..color = SandColors.primaryGold.withAlpha(120)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset((targetX + 0.5) * cellW, 0),
      Offset((targetX + 0.5) * cellW, size.height),
      guidePaint,
    );

    _drawCell(canvas, const Offset(6, 6), cellW, cellH, color.withAlpha(180));
    _drawCell(canvas, const Offset(7, 6), cellW, cellH, color.withAlpha(180));
    _drawCell(canvas, const Offset(8, 6), cellW, cellH, color.withAlpha(180));

    _drawCell(canvas, Offset(targetX, currentY), cellW, cellH, color.withAlpha(230));

    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    _paintCaption(
      canvas,
      size,
      'Tap column to place NEXT piece',
      alpha: (170 + pulse * 70).round(),
    );
  }

  void _paintGravity(Canvas canvas, Size size, double cellW, double cellH) {
    final sand = const Color(0xFFD99C4E);

    final base = [
      const Offset(4, 7),
      const Offset(5, 7),
      const Offset(6, 7),
      const Offset(7, 7),
      const Offset(8, 7),
      const Offset(9, 7),
      const Offset(5, 6),
      const Offset(6, 6),
      const Offset(8, 6),
    ];

    for (final c in base) {
      _drawCell(canvas, c, cellW, cellH, sand.withAlpha(195));
    }

    final dropT = Curves.easeIn.transform(progress);
    final fallingY = 1.0 + (6.0 - 1.0) * dropT;

    _drawCell(canvas, Offset(7, fallingY), cellW, cellH, sand.withAlpha(230));

    if (progress > 0.62) {
      final slideT = ((progress - 0.62) / 0.38).clamp(0.0, 1.0);
      final slideX = 7.0 + slideT;
      _drawCell(canvas, Offset(slideX, 6), cellW, cellH, sand.withAlpha(220));
    }

    _paintCaption(canvas, size, 'Unsupported sand falls and settles');
  }

  void _paintBridgeRule(Canvas canvas, Size size, double cellW, double cellH) {
    final a = Colors.orangeAccent;
    final b = Colors.lightBlueAccent;

    for (int x = 0; x < cols; x++) {
      final useA = x.isEven;
      _drawCell(
        canvas,
        Offset(x.toDouble(), 5),
        cellW,
        cellH,
        (useA ? a : b).withAlpha(205),
      );
    }

    final markerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.redAccent.withAlpha(220);
    final center = Offset(size.width * 0.5, 5.5 * cellH);
    canvas.drawCircle(center, math.min(cellW, cellH) * 0.58, markerPaint);
    canvas.drawLine(
      center + Offset(-cellW * 0.34, -cellH * 0.34),
      center + Offset(cellW * 0.34, cellH * 0.34),
      markerPaint,
    );

    _paintLegend(canvas, size, a, b);
    _paintCaption(canvas, size, 'Mixed colors do not clear');
  }

  void _paintBridgeClear(Canvas canvas, Size size, double cellW, double cellH) {
    final clearColor = Colors.orangeAccent;
    final otherColor = Colors.lightBlueAccent;

    final baseCells = <Offset>[];
    for (int x = 0; x < cols; x++) {
      if (x == cols ~/ 2) continue;
      baseCells.add(Offset(x.toDouble(), 6));
    }

    for (final c in baseCells) {
      _drawCell(canvas, c, cellW, cellH, clearColor.withAlpha(220));
    }

    for (int x = 3; x < 11; x += 2) {
      _drawCell(canvas, Offset(x.toDouble(), 4), cellW, cellH, otherColor.withAlpha(190));
    }

    final dropT = ((progress - 0.12) / 0.36).clamp(0.0, 1.0);
    final fallingY = 1.0 + (6.0 - 1.0) * Curves.easeIn.transform(dropT);
    final landed = progress >= 0.48;

    if (dropT > 0) {
      _drawCell(
        canvas,
        Offset((cols ~/ 2).toDouble(), landed ? 6.0 : fallingY),
        cellW,
        cellH,
        clearColor.withAlpha(230),
      );
    }

    double alpha = 1.0;
    if (progress > 0.64) {
      alpha = (1.0 - ((progress - 0.64) / 0.22)).clamp(0.0, 1.0);
    }

    if (progress > 0.60 && progress < 0.78) {
      final flashT = ((progress - 0.60) / 0.18).clamp(0.0, 1.0);
      final flash = Paint()..color = Colors.white.withAlpha((90 * (1 - flashT)).round());
      canvas.drawRect(Offset.zero & size, flash);
    }

    if (alpha < 1.0) {
      for (final c in baseCells) {
        _drawCell(canvas, c, cellW, cellH, clearColor.withAlpha((220 * alpha).round()));
      }
      if (landed) {
        _drawCell(
          canvas,
          Offset((cols ~/ 2).toDouble(), 6),
          cellW,
          cellH,
          clearColor.withAlpha((230 * alpha).round()),
        );
      }
    }

    _paintLegend(canvas, size, clearColor, otherColor);
    _paintCaption(canvas, size, 'Same-color bridge spans both edges -> clears');
  }

  void _drawCell(Canvas canvas, Offset cell, double cellW, double cellH, Color color) {
    if (color.alpha == 0) return;
    final rect = Rect.fromLTWH(cell.dx * cellW, cell.dy * cellH, cellW, cellH).deflate(0.8);
    final paint = Paint()..color = color;
    canvas.drawRect(rect, paint);
  }

  void _paintCaption(Canvas canvas, Size size, String text, {int alpha = 210}) {
    final style = TextStyle(
      color: SandColors.lightSand.withAlpha(alpha),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
    );

    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width - 8);

    tp.paint(canvas, Offset((size.width - tp.width) / 2, 4));
  }

  void _paintLegend(Canvas canvas, Size size, Color clearColor, Color otherColor) {
    final y = size.height - 14;
    final clearPaint = Paint()..color = clearColor.withAlpha(220);
    final otherPaint = Paint()..color = otherColor.withAlpha(220);

    canvas.drawCircle(Offset(16, y), 4, clearPaint);
    canvas.drawCircle(Offset(132, y), 4, otherPaint);

    final style = TextStyle(
      color: SandColors.lightSand.withAlpha(190),
      fontSize: 9,
      fontWeight: FontWeight.w600,
      fontFamily: 'monospace',
    );

    final t1 = TextPainter(
      text: TextSpan(text: 'target color', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    t1.paint(canvas, Offset(24, y - 6));

    final t2 = TextPainter(
      text: TextSpan(text: 'other colors', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    t2.paint(canvas, Offset(140, y - 6));
  }

  @override
  bool shouldRepaint(covariant _TutorialDemoPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.type != type;
  }
}

class _TutorialBullet extends StatelessWidget {
  final String text;

  const _TutorialBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.circle, size: 8, color: SandColors.primaryGold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: SandColors.lightSand,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SandColors.deepSand.withAlpha(100),
              shape: BoxShape.circle,
              border: Border.all(color: SandColors.primaryGold.withAlpha(180)),
            ),
            child: Icon(icon, color: SandColors.lightSand, size: 18),
          ),
        ),
      ),
    );
  }
}
