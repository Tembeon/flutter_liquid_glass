import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Shows a page over the whole screen, sliding up from the bottom, and
/// completes with the result it is closed with.
///
/// UIKit: `present(_:animated:)` with `.fullScreen` and `coverVertical`.
/// SwiftUI: `fullScreenCover`. Flutter: a `fullscreenDialog` page route.
///
/// [builder] builds the page, on [GlassColors.systemBackground] unless it
/// paints its own; `Navigator.pop(context, result)` inside it closes the
/// page with a result. The page slides up over the one below on UIKit's
/// critically damped spring of response 0.344 and back down on the same
/// spring when it closes. No swipe closes it: Back and `Navigator.pop`
/// do, and Android's predictive back slides it down with the gesture. Once
/// it covers the screen the page below stops building and painting, as
/// UIKit takes the presenter's view out of the window, and comes back as
/// the page leaves. Screen readers hear it as a route named
/// [semanticLabel]. The [context] needs a [Navigator] above it; with
/// `level` at its default the page covers the whole app, bars and tabs
/// included.
///
/// ```dart
/// Future<void> showPlayer(BuildContext context) =>
///     showGlassFullScreen<void>(
///       context,
///       builder: (context) => GlassPageScaffold(
///         navigationBar: const GlassNavigationBar(title: Text('Now Playing')),
///         child: const Center(child: Text('Song')),
///       ),
///     );
/// ```
///
/// Fidelity. The slide is UIKit 27.2's on the simulator, presentation and
/// dismissal (presentation passport); UIKit cuts it at 0.5 s, about a
/// point short of its end, which this one rests through instead.
Future<T?> showGlassFullScreen<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? semanticLabel,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  _FullScreenRoute<T>(builder: builder, semanticLabel: semanticLabel),
  level: level,
);

class _FullScreenRoute<T> extends PresentationPageRoute<T> {
  _FullScreenRoute({required this.builder, this.semanticLabel});

  final WidgetBuilder builder;
  final String? semanticLabel;

  @override
  late final Presentation<T, FullScreenMotion> presentation = Presentation(
    motion: (environment) => FullScreenMotion(
      height: environment.bounds.height,
      clock: environment.clock,
    ),
    builder: (context, motion) =>
        _FullScreenPage(motion: motion, builder: builder),
    dismiss: const DismissPolicy({DismissTrigger.back}),
    modal: (motion) => true,
    semanticsLabel: semanticLabel,
    semanticsRole: SemanticsRole.dialog,
  );
}

class _FullScreenPage extends StatefulWidget {
  const _FullScreenPage({required this.motion, required this.builder});

  final FullScreenMotion motion;
  final WidgetBuilder builder;

  @override
  State<_FullScreenPage> createState() => _FullScreenPageState();
}

class _FullScreenPageState extends State<_FullScreenPage> {
  double _height = 0;
  late MotionSelection<double> _drop = _dropOf();

  MotionSelection<double> _dropOf() {
    final height = _height;
    return widget.motion.select((m) => (1 - m.progress) * height);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final height = MediaQuery.sizeOf(context).height;
    if (height == _height) return;
    _height = height;
    _drop = _dropOf();
  }

  @override
  Widget build(BuildContext context) => MotionTransition(
    translateY: _drop,
    child: ColoredBox(
      color: GlassDynamicColor.resolve(GlassColors.systemBackground, context),
      child: Builder(builder: widget.builder),
    ),
  );
}
