import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/demos/interactions.dart';
import 'package:kinesis_example/demos/layout.dart';
import 'package:kinesis_example/demos/presentations.dart';
import 'package:kinesis_example/demos/release.dart';
import 'package:kinesis_example/demos/scroll.dart';
import 'package:kinesis_example/demos/springs.dart';
import 'package:kinesis_example/demos/symbols.dart';
import 'package:kinesis_example/demos/text.dart';
import 'package:kinesis_example/demos/timelines.dart';
import 'package:kinesis_example/demos/visibility.dart';
import 'package:kinesis_example/demos/zones.dart';
import 'package:kinesis_example/kit.dart';

@immutable
final class Demo {
  const Demo(this.title, this.summary, this.builder);

  final String title;
  final String summary;
  final WidgetBuilder builder;
}

@immutable
final class DemoGroup {
  const DemoGroup(this.title, this.demos);

  final String title;
  final List<Demo> demos;
}

final List<DemoGroup> demoGroups = [
  DemoGroup('Motion', [
    Demo(
      'Springs',
      'withSpring, timing curves, values of any type, Reduce Motion',
      (_) => const SpringsDemo(),
    ),
    Demo(
      'Keyframes and animators',
      'MotionKeyframes, KeyframeValue, MotionAnimator',
      (_) => const TimelinesDemo(),
    ),
    Demo(
      'Release',
      'Projection, RubberBand, PagingPhysics, ScrollDeceleration',
      (_) => const ReleaseDemo(),
    ),
  ]),
  DemoGroup('Text and symbols', [
    Demo(
      'Text',
      'MotionNumericText, MotionText, MotionContentTransition',
      (_) => const TextDemo(),
    ),
    Demo(
      'Symbol effects',
      'MotionSymbol with bounce, pulse, wiggle and the rest',
      (_) => const SymbolsDemo(),
    ),
  ]),
  DemoGroup('Layout', [
    Demo(
      'Layout changes',
      'MotionLayout and SliverMotionList',
      (_) => const LayoutDemo(),
    ),
    Demo('Scroll', 'MotionScroll, ScrollToTopCurve', (_) => const ScrollDemo()),
    Demo(
      'Visibility and caret',
      'MotionVisibility, CaretBlinkMotion',
      (_) => const VisibilityDemo(),
    ),
  ]),
  DemoGroup('Input', [
    Demo(
      'Interactions',
      'InputRegion with press, tap, long press, drag and more',
      (_) => const InteractionsDemo(),
    ),
    Demo(
      'Input zones',
      'InputZones: many targets under one finger',
      (_) => const ZonesDemo(),
    ),
  ]),
  DemoGroup('Overlays', [
    Demo(
      'Presentations',
      'PresentationRoute, PresentationPortal, a sheet the finger dismisses',
      (_) => const PresentationsDemo(),
    ),
  ]),
];

class KinesisGallery extends StatelessWidget {
  const KinesisGallery({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'kinesis',
    color: Palette.light.accent,
    debugShowCheckedModeBanner: false,
    onGenerateRoute: (settings) => PageRouteBuilder<void>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const CatalogPage(),
    ),
    builder: (context, child) =>
        FrameCadenceScope(child: _Ambient(child: child!)),
  );
}

class _Ambient extends StatelessWidget {
  const _Ambient({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyles.body.copyWith(color: Palette.of(context).label),
    child: child,
  );
}

class DemoRoute extends PresentationPageRoute<void> {
  DemoRoute(this.demo) : super(settings: RouteSettings(name: demo.title));

  final Demo demo;

  @override
  late final Presentation<void, Presented> presentation =
      Presentation<void, PageSlide>(
        motion: (environment) => PageSlide(clock: environment.clock),
        dismiss: DismissPolicy.modal,
        dim: (motion) => 0.15 * motion.opacity,
        semanticsLabel: demo.title,
        builder: (context, motion) => MotionTransition(
          pose: motion.pose,
          child: DemoTitle(title: demo.title, child: demo.builder(context)),
        ),
      );
}

final class PageSlide extends PresentedProgress {
  PageSlide({super.clock})
    : super(
        openSpring: const Spring(duration: 0.45),
        restDistance: 1e-3,
      );

  late final MotionSelection<MotionPose> pose = select(
    (m) => MotionPose(offsetFraction: Offset(1 - m.progress, 0)),
  );
}

class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: pageInsets(context, top: 28),
          children: [
            const Text('kinesis', style: TextStyles.title),
            const SizedBox(height: 8),
            Text(
              'Springs that keep their speed, gestures as plain logic, '
              'presentations, and time a test can replay. Each page shows '
              'one part of the library with the least code that uses it.',
              style: TextStyles.body.copyWith(color: palette.secondaryLabel),
            ),
            for (final group in demoGroups) ...[
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Text(
                  group.title,
                  style: TextStyles.label.copyWith(
                    color: palette.secondaryLabel,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (index, demo) in group.demos.indexed) ...[
                      if (index > 0)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16),
                          child: SizedBox(
                            height: 1,
                            child: ColoredBox(color: palette.separator),
                          ),
                        ),
                      _DemoRow(demo),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DemoRow extends StatelessWidget {
  const _DemoRow(this.demo);

  final Demo demo;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Tappable(
      onTap: () => Navigator.of(context).push(DemoRoute(demo)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(demo.title, style: TextStyles.label),
                  const SizedBox(height: 2),
                  Text(
                    demo.summary,
                    style: TextStyles.caption.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Chevron(color: palette.secondaryLabel),
          ],
        ),
      ),
    );
  }
}
