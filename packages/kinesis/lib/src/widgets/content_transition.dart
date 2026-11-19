import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// Visual style of a [MotionContentTransition] when its child's identity
/// changes (matching SwiftUI's `ContentTransition` / UIKit's
/// `UIView.transition`).
@immutable
sealed class ContentTransition {
  /// Creates a content transition.
  const ContentTransition();

  /// Cross-dissolve fade between outgoing and incoming children.
  const factory ContentTransition.fade() = _FadeContentTransition;

  /// SwiftUI `.blurReplace`: outgoing content fades, blurs up to [maxBlur]
  /// sigma, and gently scales to [minScale] while incoming content sharpens
  /// and scales in (`[approx]` default parameters).
  const factory ContentTransition.blurReplace({
    double maxBlur,
    double minScale,
  }) = _BlurReplaceContentTransition;

  /// Scale and cross-fade about [alignment].
  const factory ContentTransition.scale({
    double scale,
    AlignmentGeometry alignment,
  }) = _ScaleContentTransition;

  /// Directional slide and cross-fade by [offset].
  const factory ContentTransition.slide({Offset offset}) =
      _SlideContentTransition;
}

final class _FadeContentTransition extends ContentTransition {
  const _FadeContentTransition();

  @override
  bool operator ==(Object other) => other is _FadeContentTransition;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ContentTransition.fade()';
}

final class _BlurReplaceContentTransition extends ContentTransition {
  const _BlurReplaceContentTransition({
    this.maxBlur = 6,
    this.minScale = 0.92,
  });

  final double maxBlur;
  final double minScale;

  @override
  bool operator ==(Object other) =>
      other is _BlurReplaceContentTransition &&
      other.maxBlur == maxBlur &&
      other.minScale == minScale;

  @override
  int get hashCode => Object.hash(maxBlur, minScale);

  @override
  String toString() =>
      'ContentTransition.blurReplace(maxBlur: $maxBlur, minScale: $minScale)';
}

final class _ScaleContentTransition extends ContentTransition {
  const _ScaleContentTransition({
    this.scale = 0.85,
    this.alignment = Alignment.center,
  });

  final double scale;
  final AlignmentGeometry alignment;

  @override
  bool operator ==(Object other) =>
      other is _ScaleContentTransition &&
      other.scale == scale &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(scale, alignment);

  @override
  String toString() =>
      'ContentTransition.scale(scale: $scale, alignment: $alignment)';
}

final class _SlideContentTransition extends ContentTransition {
  const _SlideContentTransition({this.offset = const Offset(0, 12)});

  final Offset offset;

  @override
  bool operator ==(Object other) =>
      other is _SlideContentTransition && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;

  @override
  String toString() => 'ContentTransition.slide(offset: $offset)';
}

/// Transitions smoothly whenever [child] changes identity (`Widget.canUpdate`
/// returns false, e.g. different `ValueKey`s), driving composited
/// `MotionTransition` layers on `MotionClock` with zero per-frame widget
/// rebuilds.
///
/// Under Reduce Motion (`MotionTraits.reduceMotion`), falls back to
/// [ContentTransition.fade] automatically.
class MotionContentTransition extends StatefulWidget {
  /// Creates a content transition host.
  const MotionContentTransition({
    required this.child,
    this.transition = const ContentTransition.blurReplace(),
    this.animation = defaultAnimation,
    this.alignment = Alignment.center,
    super.key,
  });

  /// `[approx]` Default spring for content transitions.
  static const MotionAnimation defaultAnimation = Spring.response(
    0.32,
    dampingRatio: 0.92,
  );

  /// The active child widget. Give distinct keys to trigger transitions.
  final Widget child;

  /// The visual style of the transition.
  final ContentTransition transition;

  /// The [Spring] or [TimingCurve] driving the transition.
  final MotionAnimation animation;

  /// Alignment of outgoing and incoming children inside the stack.
  final AlignmentGeometry alignment;

  @override
  State<MotionContentTransition> createState() =>
      _MotionContentTransitionState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<ContentTransition>('transition', transition))
      ..add(DiagnosticsProperty<MotionAnimation>('animation', animation))
      ..add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
  }
}

class _MotionContentTransitionState extends State<MotionContentTransition> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _progress = MotionValue<double>(
    1,
    restDistance: MotionRest.opacity,
    clock: _clock,
  );
  Widget? _outgoing;
  late Widget _current = widget.child;

  late final MotionSelection<double> _inOpacity = MotionSelection<double>(
    () => _progress.value.clamp(0.0, 1.0),
    clock: _clock,
  );
  late final MotionSelection<double> _outOpacity = MotionSelection<double>(
    () => (1 - _progress.value).clamp(0.0, 1.0),
    clock: _clock,
  );
  double get _minScale => switch (_effectiveTransition) {
    final _BlurReplaceContentTransition b => b.minScale,
    final _ScaleContentTransition s => s.scale,
    _ => 1.0,
  };

  late final MotionSelection<double> _inScale = MotionSelection<double>(
    () => _minScale + (1 - _minScale) * _progress.value,
    clock: _clock,
  );
  late final MotionSelection<double> _outScale = MotionSelection<double>(
    () => 1 - (1 - _minScale) * _progress.value,
    clock: _clock,
  );
  late final MotionSelection<double> _inBlur = MotionSelection<double>(() {
    final t = _effectiveTransition;
    if (t is! _BlurReplaceContentTransition) return 0;
    return (1 - _progress.value.clamp(0.0, 1.0)) * t.maxBlur;
  }, clock: _clock);
  late final MotionSelection<double> _outBlur = MotionSelection<double>(() {
    final t = _effectiveTransition;
    if (t is! _BlurReplaceContentTransition) return 0;
    return _progress.value.clamp(0.0, 1.0) * t.maxBlur;
  }, clock: _clock);
  late final MotionSelection<Offset> _inOffset = MotionSelection<Offset>(() {
    final t = _effectiveTransition;
    if (t is! _SlideContentTransition) return Offset.zero;
    return t.offset * (1 - _progress.value);
  }, clock: _clock);
  late final MotionSelection<Offset> _outOffset = MotionSelection<Offset>(() {
    final t = _effectiveTransition;
    if (t is! _SlideContentTransition) return Offset.zero;
    return -t.offset * _progress.value;
  }, clock: _clock);

  bool _reduceMotion = false;

  ContentTransition get _effectiveTransition =>
      _reduceMotion ? const ContentTransition.fade() : widget.transition;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgress);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MotionTraitsOverride.of(context).reduceMotion;
  }

  @override
  void didUpdateWidget(MotionContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!Widget.canUpdate(_current, widget.child)) {
      _outgoing = _current;
      _current = widget.child;
      final t = _clock.now;
      _progress.snap(t, 0);
      _progress.animate(
        t,
        1,
        animation: widget.animation.resolve(reduceMotion: _reduceMotion),
      );
    } else {
      _current = widget.child;
    }
  }

  void _onProgress() {
    if (_outgoing != null && _progress.restsAt(_clock.now)) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void dispose() {
    _progress.removeListener(_onProgress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _effectiveTransition;
    final scaleAlignment = t is _ScaleContentTransition
        ? t.alignment
        : Alignment.center;
    final useScale =
        t is _BlurReplaceContentTransition || t is _ScaleContentTransition;
    final useBlur = t is _BlurReplaceContentTransition;
    final useSlide = t is _SlideContentTransition;

    if (_outgoing == null) return _current;

    return Stack(
      alignment: widget.alignment,
      children: [
        IgnorePointer(
          child: MotionTransition(
            alignment: scaleAlignment,
            opacity: _outOpacity,
            scale: useScale ? _outScale : null,
            blur: useBlur ? _outBlur : null,
            offset: useSlide ? _outOffset : null,
            child: _outgoing,
          ),
        ),
        MotionTransition(
          alignment: scaleAlignment,
          opacity: _inOpacity,
          scale: useScale ? _inScale : null,
          blur: useBlur ? _inBlur : null,
          offset: useSlide ? _inOffset : null,
          child: _current,
        ),
      ],
    );
  }
}
