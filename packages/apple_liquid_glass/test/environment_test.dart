import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/poses.dart';

const _right84 = GlassBarColumn(
  side: GlassBarColumnSide.right,
  reservedWidth: 84,
);

Future<GlassEnvironment> _read(
  WidgetTester tester, [
  Widget Function(Widget probe)? wrap,
]) async {
  GlassEnvironment? seen;
  final probe = Builder(
    builder: (context) {
      seen = GlassEnvironment.of(context);
      return const SizedBox();
    },
  );
  await tester.pumpWidget(
    MediaQuery.fromView(view: tester.view, child: wrap?.call(probe) ?? probe),
  );
  return seen!;
}

GlassEnvironment _expected(
  GlassFormFactor formFactor,
  GlassSizeClass horizontal,
  GlassSizeClass vertical, {
  GlassBarColumn barColumn = GlassBarColumn.none,
}) => GlassEnvironment(
  formFactor: formFactor,
  horizontalSizeClass: horizontal,
  verticalSizeClass: vertical,
  barColumn: barColumn,
);

void main() {
  const phone = GlassFormFactor.phone;
  const tablet = GlassFormFactor.tablet;
  const desktop = GlassFormFactor.desktop;
  const compact = GlassSizeClass.compact;
  const regular = GlassSizeClass.regular;

  final rows = <(Pose, GlassEnvironment)>[
    (Poses.iPhone, _expected(phone, compact, regular)),
    (Poses.iPhoneLandscape, _expected(phone, compact, compact)),
    (Poses.iPhoneProMaxLandscape, _expected(phone, regular, compact)),
    (Poses.duoCover, _expected(phone, compact, regular, barColumn: _right84)),
    (Poses.duoCoverClassic, _expected(phone, compact, regular)),
    (
      Poses.duoCoverLandscapeCameraLeft,
      _expected(
        phone,
        compact,
        compact,
        barColumn: const GlassBarColumn(
          side: GlassBarColumnSide.left,
          reservedWidth: 84,
        ),
      ),
    ),
    (Poses.duoInner, _expected(phone, regular, regular, barColumn: _right84)),
    (Poses.duoInnerClassic, _expected(phone, regular, regular)),
    (Poses.duoInnerPortrait, _expected(phone, regular, regular)),
    (Poses.duoInnerSplitViewLeft, _expected(phone, compact, regular)),
    (Poses.iPadWindowSmallest, _expected(tablet, compact, regular)),
    (Poses.iPadWindowCompactWidest, _expected(tablet, compact, regular)),
    (Poses.iPadWindowShortRegular, _expected(tablet, regular, regular)),
    (Poses.iPadFull, _expected(tablet, regular, regular)),
  ];

  for (final (pose, expected) in rows) {
    testWidgets(
      '$pose is derived as UIKit lays it out',
      (tester) async {
        pose.apply(tester);
        expect(await _read(tester), expected);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'a window on a desktop operating system is a desktop, whatever its size; '
    'it is compact below 668 points wide and regular in height',
    (tester) async {
      for (final (size, horizontal) in [
        (const Size(800, 300), regular),
        (const Size(667, 900), compact),
        (const Size(668, 400), regular),
      ]) {
        Pose('$size', size, EdgeInsets.zero).apply(tester);
        expect(
          await _read(tester),
          _expected(desktop, horizontal, regular),
          reason: '$size',
        );
      }
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'padding on one side alone is never a column off iOS, where a camera '
    'cutout gives the same padding',
    (tester) async {
      Poses.duoInner.apply(tester);
      expect((await _read(tester)).barColumn, GlassBarColumn.none);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('the display decides between a phone and a tablet, not the '
      'window; a display that reports no size leaves it to the window', (
    tester,
  ) async {
    const Pose(
      'a phone-sized window on a tablet',
      Size(402, 600),
      EdgeInsets.only(top: 24),
      display: Size(834, 1194),
    ).apply(tester);
    expect((await _read(tester)).formFactor, tablet);

    const Pose(
      'an unreported display',
      Size(1194, 834),
      EdgeInsets.only(top: 24),
      display: Size.zero,
    ).apply(tester);
    expect((await _read(tester)).formFactor, tablet);
  });

  testWidgets(
    'an override replaces what it names and keeps the rest; none takes a '
    'derived value away; an inner override keeps the outer one',
    (tester) async {
      Poses.duoInner.apply(tester);
      const controls = GlassWindowControls(
        left: 62,
        lineCenter: 46,
      );
      expect((await _read(tester)).barColumn, _right84);
      expect(
        await _read(
          tester,
          (probe) => GlassEnvironmentOverride(
            formFactor: tablet,
            windowControls: controls,
            child: GlassEnvironmentOverride(
              barColumn: GlassBarColumn.none,
              occlusions: const [Rect.fromLTWH(867, 0, 84, 124)],
              child: probe,
            ),
          ),
        ),
        const GlassEnvironment(
          formFactor: tablet,
          horizontalSizeClass: regular,
          windowControls: controls,
          occlusions: [Rect.fromLTWH(867, 0, 84, 124)],
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets("the window's corners are the display's where Flutter reports "
      'them, unknown elsewhere, and what an override gives', (tester) async {
    Poses.iPadFull.apply(tester);
    expect((await _read(tester)).windowCornerRadius, isNull);
    expect(
      (await _read(
        tester,
        (probe) => MediaQuery(
          data: MediaQueryData(
            size: const Size(1194, 834),
            displayCornerRadii: BorderRadius.circular(40),
          ),
          child: probe,
        ),
      )).windowCornerRadius,
      40,
    );
    expect(
      (await _read(
        tester,
        (probe) => GlassEnvironmentOverride(
          windowCornerRadius: 26,
          child: GlassEnvironmentOverride(child: probe),
        ),
      )).windowCornerRadius,
      26,
    );
  });

  testWidgets(
    'the left of the Split View takes the column the system wants with no '
    'room from an override, as a platform plugin reports it',
    (tester) async {
      Poses.duoInnerSplitViewLeft.apply(tester);
      const wanted = GlassBarColumn(
        side: GlassBarColumnSide.left,
        reservedWidth: 0,
      );
      expect((await _read(tester)).barColumn, GlassBarColumn.none);
      expect(
        (await _read(
          tester,
          (probe) => GlassEnvironmentOverride(barColumn: wanted, child: probe),
        )).barColumn,
        wanted,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a reader rebuilds when the window or an override changes, and '
      'only then', (tester) async {
    Poses.iPadFull.apply(tester);
    var builds = 0;
    final probe = Builder(
      builder: (context) {
        GlassEnvironment.of(context);
        builds++;
        return const SizedBox();
      },
    );
    Future<void> pump(GlassWindowControls controls) => tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: GlassEnvironmentOverride(
          windowControls: controls,
          child: probe,
        ),
      ),
    );
    await pump(
      const GlassWindowControls(
        left: 62,
      ),
    );
    await pump(
      const GlassWindowControls(
        left: 62,
      ),
    );
    expect(builds, 1);
    await pump(GlassWindowControls.none);
    expect(builds, 2);
    Poses.iPadWindowShortRegular.apply(tester);
    await tester.pump();
    expect(builds, 3);
  });

  test('a window has no buttons until an edge holds them', () {
    expect(GlassWindowControls.none.isEmpty, isTrue);
    expect(
      const GlassWindowControls(
        right: 138,
      ).isEmpty,
      isFalse,
    );
    expect(GlassBarColumn.none.side, isNull);
  });
}
