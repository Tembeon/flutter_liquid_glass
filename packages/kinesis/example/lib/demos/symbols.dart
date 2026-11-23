import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class SymbolsDemo extends StatefulWidget {
  const SymbolsDemo({super.key});

  @override
  State<SymbolsDemo> createState() => _SymbolsDemoState();
}

class _SymbolsDemoState extends State<SymbolsDemo> {
  final _symbol = SymbolEffectMotion();
  bool _pulsing = false;
  bool _breathing = false;
  bool _scaled = false;
  bool _hidden = false;

  double get _now => _symbol.clock.now;

  void _play(MotionSymbolEffect effect) => _symbol.add(_now, effect);

  void _togglePulse() {
    _pulsing = !_pulsing;
    if (_pulsing) {
      _symbol.add(_now, const PulseSymbolEffect());
    } else {
      _symbol.remove<PulseSymbolEffect>(_now);
    }
    setState(() {});
  }

  void _toggleBreathe() {
    _breathing = !_breathing;
    if (_breathing) {
      _symbol.add(_now, const BreatheSymbolEffect());
    } else {
      _symbol.remove<BreatheSymbolEffect>(_now);
    }
    setState(() {});
  }

  void _toggleScale() {
    _scaled = !_scaled;
    if (_scaled) {
      _symbol.add(_now, const ScaleSymbolEffect());
    } else {
      _symbol.remove<ScaleSymbolEffect>(_now);
    }
    setState(() {});
  }

  void _toggleHidden() {
    _hidden = !_hidden;
    _symbol.add(
      _now,
      _hidden ? const DisappearSymbolEffect() : const AppearSymbolEffect(),
    );
    setState(() {});
  }

  void _stopAll() {
    _symbol.removeAll(_now);
    setState(() => _pulsing = _breathing = _scaled = _hidden = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          "SF Symbols' effects as a Motion: SymbolEffectMotion plays them "
          'with UIKit timing, and MotionSymbol wears the pose on any '
          'widget, here a star we draw ourselves.',
      children: [
        Section(
          title: 'Effects',
          caption:
              'Bounce, wiggle and rotate play one cycle: tap one again and '
              'it queues behind the cycle that plays. Pulse and breathe '
              'repeat until turned off, scale holds while on, disappear '
              'holds the star hidden. Different effects stack.',
          stage: SizedBox(
            height: 150,
            child: Center(
              child: MotionSymbol(
                motion: _symbol,
                child: _Star(color: palette.swatches[1], size: 88),
              ),
            ),
          ),
          controls: [
            PushButton(
              'Bounce',
              onPressed: () => _play(const BounceSymbolEffect()),
            ),
            PushButton(
              'Bounce down',
              onPressed: () => _play(
                const BounceSymbolEffect(
                  direction: SymbolEffectDirection.down,
                ),
              ),
            ),
            PushButton(
              'Wiggle',
              onPressed: () => _play(const WiggleSymbolEffect()),
            ),
            PushButton(
              'Rotate',
              onPressed: () => _play(const RotateSymbolEffect()),
            ),
            PushButton('Pulse', selected: _pulsing, onPressed: _togglePulse),
            PushButton(
              'Breathe',
              selected: _breathing,
              onPressed: _toggleBreathe,
            ),
            PushButton('Scale', selected: _scaled, onPressed: _toggleScale),
            PushButton(
              'Disappear',
              selected: _hidden,
              onPressed: _toggleHidden,
            ),
            PushButton('Remove all', onPressed: _stopAll),
          ],
        ),
      ],
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _StarPainter(color),
  );
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / 5;
      final point = center + Offset(cos(angle), sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}
