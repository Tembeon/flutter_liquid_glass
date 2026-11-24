import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/foundation/platform.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

import 'support/poses.dart';

// What UIKit reported on the iPhone Duo simulator, iOS 27.2: the inner
// display, its crease's band and the status cluster of the side column.
const _inner = Size(951, 669);
const _innerSafeArea = EdgeInsets.only(right: 84, bottom: 34);
const _band = Rect.fromLTWH(455.5, 0, 40, 669);
const _statusCluster = Rect.fromLTWH(867, 0, 84, 124);

GlassPlatformReport _innerReport({
  List<Rect> activeDivisions = const [],
  bool hingeFlat = false,
  GlassBarColumnSide? barColumnSide = GlassBarColumnSide.right,
  Size size = _inner,
}) => GlassPlatformReport.fromUIKit(
  formFactor: GlassFormFactor.phone,
  horizontalSizeClass: GlassSizeClass.regular,
  verticalSizeClass: GlassSizeClass.regular,
  barColumnSide: barColumnSide,
  size: size,
  safeArea: _innerSafeArea,
  occlusions: const [_statusCluster],
  activeDivisions: activeDivisions,
  hingeFlat: hingeFlat,
);

final class _FakeReader extends ChangeNotifier implements GlassPlatformReader {
  _FakeReader(this.report);

  GlassPlatformReport report;
  GlassPlatformSettings settings = GlassPlatformSettings.none;
  int reads = 0;
  final behaviors = <GlassBarColumnBehavior>[];

  @override
  GlassPlatformReport read() {
    reads++;
    return report;
  }

  @override
  GlassPlatformSettings readSettings() => settings;

  @override
  void setBarColumnBehavior(GlassBarColumnBehavior behavior) =>
      behaviors.add(behavior);

  bool get listened => hasListeners;

  void change(GlassPlatformReport next) {
    report = next;
    notifyListeners();
  }

  void changeSettings(GlassPlatformSettings next) {
    settings = next;
    notifyListeners();
  }
}

_FakeReader _install(GlassPlatformReport report) {
  final reader = _FakeReader(report);
  var made = 0;
  debugGlassPlatformReader = () {
    made++;
    expect(made, 1, reason: 'one reader for the outermost scope');
    return reader;
  };
  addTearDown(() => debugGlassPlatformReader = null);
  return reader;
}

final class _Probe {
  GlassEnvironment? environment;
  GlassPlatformReport? report;
  int builds = 0;

  Widget widget() => Builder(
    builder: (context) {
      builds++;
      environment = GlassEnvironment.of(context);
      report = GlassPlatformReport.maybeOf(context);
      return const SizedBox();
    },
  );
}

final class _Traits {
  GlassTraits? seen;
  int builds = 0;

  Widget widget() => Builder(
    builder: (context) {
      builds++;
      seen = GlassTraits.of(context);
      return const SizedBox();
    },
  );
}

const _allOn = GlassPlatformSettings(
  reduceTransparency: true,
  showBorders: true,
  prefersCrossFade: true,
  glassTintAmount: 0.4,
  prefersReducedResourceUsage: true,
);

final class _Features {
  List<DisplayFeature>? seen;

  Widget widget() => Builder(
    builder: (context) {
      seen = MediaQuery.of(context).displayFeatures;
      return const SizedBox();
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  GlassBarColumnBehavior? behavior,
}) => tester.pumpWidget(
  MediaQuery.fromView(
    view: tester.view,
    child: GlassPlatformScope(barColumnBehavior: behavior, child: child),
  ),
);

void main() {
  group('a report of what UIKit says', () {
    test(
      'folds on the active band while the hinge is half open or unknown',
      () {
        expect(_innerReport(activeDivisions: [_band]).fold, _band);
        expect(_innerReport().fold, isNull);
      },
    );

    test('a closed or fully open hinge folds nothing', () {
      expect(
        _innerReport(activeDivisions: [_band], hingeFlat: true).fold,
        isNull,
      );
    });

    test('a band that does not lie in the view folds nothing', () {
      // The cover display, a moment after closing: the inner display's band,
      // turned and still active.
      expect(
        _innerReport(
          activeDivisions: [const Rect.fromLTWH(0, 455.5, 669, 40)],
          size: const Size(466, 678),
        ).fold,
        isNull,
      );
    });

    test('the column takes the safe area of its side', () {
      expect(
        _innerReport().barColumn,
        const GlassBarColumn(
          side: GlassBarColumnSide.right,
          reservedWidth: 84,
        ),
      );
      expect(
        _innerReport(barColumnSide: GlassBarColumnSide.left).barColumn,
        const GlassBarColumn(side: GlassBarColumnSide.left, reservedWidth: 0),
      );
      expect(
        _innerReport(barColumnSide: null).barColumn,
        GlassBarColumn.none,
      );
    });
  });

  group('GlassPlatformScope', () {
    testWidgets('gives the first frame what the platform reports', (
      tester,
    ) async {
      Poses.iPhoneLandscape.apply(tester);
      _install(_innerReport());
      final probe = _Probe();
      await _pump(tester, probe.widget());

      expect(
        probe.environment,
        const GlassEnvironment(
          horizontalSizeClass: GlassSizeClass.regular,
          barColumn: GlassBarColumn(
            side: GlassBarColumnSide.right,
            reservedWidth: 84,
          ),
          occlusions: [_statusCluster],
        ),
      );
    });

    testWidgets("an app's override wins, above the scope too", (
      tester,
    ) async {
      _install(_innerReport());
      final probe = _Probe();
      await tester.pumpWidget(
        MediaQuery.fromView(
          view: tester.view,
          child: GlassEnvironmentOverride(
            formFactor: GlassFormFactor.tablet,
            barColumn: GlassBarColumn.none,
            child: GlassPlatformScope(child: probe.widget()),
          ),
        ),
      );

      expect(probe.environment!.formFactor, GlassFormFactor.tablet);
      expect(probe.environment!.barColumn, GlassBarColumn.none);
      expect(
        probe.environment!.horizontalSizeClass,
        GlassSizeClass.regular,
      );
    });

    testWidgets('reads again when the metrics change, and rebuilds only '
        'when the report does', (tester) async {
      final reader = _install(_innerReport());
      final probe = _Probe();
      await _pump(tester, probe.widget());
      final reads = reader.reads;
      final builds = probe.builds;

      tester.platformDispatcher.onMetricsChanged!();
      await tester.pump();
      expect(reader.reads, reads + 1);
      expect(probe.builds, builds, reason: 'the report is the same');

      reader.report = _innerReport(barColumnSide: GlassBarColumnSide.left);
      tester.platformDispatcher.onMetricsChanged!();
      await tester.pump();
      expect(probe.builds, builds + 1);
      expect(probe.environment!.barColumn.side, GlassBarColumnSide.left);
    });

    testWidgets('reads again when the reader says the hinge moved', (
      tester,
    ) async {
      final reader = _install(_innerReport(activeDivisions: [_band]));
      final features = _Features();
      await _pump(tester, features.widget());
      expect(features.seen, hasLength(1));

      reader.change(_innerReport(activeDivisions: [_band], hingeFlat: true));
      await tester.pump();
      expect(features.seen, isEmpty);
    });

    testWidgets('adds the fold half open, as one list while it holds', (
      tester,
    ) async {
      final reader = _install(_innerReport(activeDivisions: [_band]));
      final features = _Features();
      await _pump(tester, features.widget());

      final folded = features.seen!;
      expect(folded, const [
        DisplayFeature(
          bounds: _band,
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ]);

      tester.view.padding = FakeViewPadding.zero;
      addTearDown(tester.view.resetPadding);
      await tester.pump();
      expect(identical(features.seen, folded), isTrue);

      reader.change(_innerReport());
      await tester.pump();
      expect(features.seen, isEmpty);
    });

    testWidgets('a scope above the MediaQuery folds it through the scope '
        'below', (tester) async {
      _install(_innerReport(activeDivisions: [_band]));
      final features = _Features();
      await tester.pumpWidget(
        GlassPlatformScope(
          child: MediaQuery.fromView(
            view: tester.view,
            child: GlassPlatformScope(child: features.widget()),
          ),
        ),
      );

      expect(features.seen, hasLength(1));
      expect(features.seen!.single.bounds, _band);
    });

    testWidgets('adds no fold where the view already reports one', (
      tester,
    ) async {
      _install(_innerReport(activeDivisions: [_band]));
      const hinge = DisplayFeature(
        bounds: Rect.fromLTWH(400, 0, 0, 669),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      );
      tester.view.displayFeatures = const [hinge];
      addTearDown(tester.view.resetDisplayFeatures);
      final features = _Features();
      await _pump(tester, features.widget());

      expect(features.seen, const [hinge]);
    });

    testWidgets('one reads; a scope below hands it its column', (
      tester,
    ) async {
      final reader = _install(_innerReport());
      final probe = _Probe();
      await _pump(
        tester,
        GlassPlatformScope(
          barColumnBehavior: GlassBarColumnBehavior.automatic,
          child: probe.widget(),
        ),
        behavior: GlassBarColumnBehavior.disabled,
      );

      expect(probe.environment!.horizontalSizeClass, GlassSizeClass.regular);
      expect(reader.behaviors, [GlassBarColumnBehavior.automatic]);
    });

    testWidgets('with no scope asking, the column is off', (tester) async {
      final reader = _install(_innerReport());
      await _pump(tester, const GlassPlatformScope(child: SizedBox()));
      expect(reader.behaviors, [GlassBarColumnBehavior.disabled]);
    });

    testWidgets('asks for the column after the frame, and again when it '
        'changes', (tester) async {
      final reader = _install(_innerReport());
      await _pump(tester, const SizedBox());
      expect(reader.behaviors, [GlassBarColumnBehavior.disabled]);

      await _pump(
        tester,
        const SizedBox(),
        behavior: GlassBarColumnBehavior.automatic,
      );
      expect(reader.behaviors, [
        GlassBarColumnBehavior.disabled,
        GlassBarColumnBehavior.automatic,
      ]);
    });

    testWidgets('asks again when a column shows', (tester) async {
      final reader = _install(_innerReport(barColumnSide: null));
      await _pump(tester, const SizedBox());
      reader.change(_innerReport());
      await tester.pump();

      expect(reader.behaviors, [
        GlassBarColumnBehavior.disabled,
        GlassBarColumnBehavior.disabled,
      ]);
    });

    testWidgets('asks again when a scope below changes its column or goes', (
      tester,
    ) async {
      final reader = _install(_innerReport());
      Widget below(GlassBarColumnBehavior? behavior) => GlassPlatformScope(
        barColumnBehavior: behavior,
        child: const SizedBox(),
      );
      await _pump(tester, below(GlassBarColumnBehavior.automatic));
      await _pump(tester, below(null));
      await _pump(tester, below(GlassBarColumnBehavior.automatic));
      await _pump(tester, const SizedBox());

      expect(reader.behaviors, [
        GlassBarColumnBehavior.automatic,
        GlassBarColumnBehavior.disabled,
        GlassBarColumnBehavior.automatic,
        GlassBarColumnBehavior.disabled,
      ]);
    });

    testWidgets('stops listening when it goes', (tester) async {
      final reader = _install(_innerReport());
      await _pump(tester, const SizedBox());
      expect(reader.listened, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(reader.listened, isFalse);
    });

    testWidgets('on a host with nothing to read it passes its child through', (
      tester,
    ) async {
      final probe = _Probe();
      await _pump(tester, probe.widget());

      expect(probe.report, isNull);
      expect(probe.environment!.occlusions, isEmpty);
    });
  });

  group('the settings', () {
    testWidgets('reach GlassTraits', (tester) async {
      _install(_innerReport()).settings = _allOn;
      final traits = _Traits();
      await _pump(
        tester,
        MotionTraitsOverride(
          traits: const MotionTraits(reduceMotion: true),
          child: traits.widget(),
        ),
      );

      final seen = traits.seen!;
      expect(seen.reduceTransparency, isTrue);
      expect(seen.showBorders, isTrue);
      expect(seen.prefersCrossFade, isTrue);
      expect(seen.glassTintAmount, 0.4);
      expect(seen.prefersReducedResourceUsage, isTrue);
    });

    testWidgets('give way to a GlassTraitsOverride', (tester) async {
      _install(_innerReport()).settings = _allOn;
      final traits = _Traits();
      await _pump(
        tester,
        GlassTraitsOverride(
          reduceTransparency: false,
          glassTintAmount: 1,
          child: traits.widget(),
        ),
      );

      final seen = traits.seen!;
      expect(seen.reduceTransparency, isFalse);
      expect(seen.glassTintAmount, 1);
      expect(seen.showBorders, isTrue);
    });

    testWidgets('an unreported cross-fade follows Reduce Motion, a reported '
        'one does not', (tester) async {
      final reader = _install(_innerReport());
      final traits = _Traits();
      await _pump(
        tester,
        MotionTraitsOverride(
          traits: const MotionTraits(reduceMotion: true),
          child: traits.widget(),
        ),
      );
      expect(traits.seen!.prefersCrossFade, isTrue);

      reader.changeSettings(
        const GlassPlatformSettings(prefersCrossFade: false),
      );
      await tester.pump();
      expect(traits.seen!.prefersCrossFade, isFalse);
    });

    testWidgets('a change rebuilds the traits, a read of the same does not', (
      tester,
    ) async {
      final reader = _install(_innerReport());
      final traits = _Traits();
      await _pump(tester, traits.widget());
      expect(traits.seen!.reduceTransparency, isFalse);

      reader.changeSettings(_allOn);
      await tester.pump();
      expect(traits.seen!.reduceTransparency, isTrue);
      final builds = traits.builds;

      reader.changeSettings(_allOn);
      await tester.pump();
      expect(traits.builds, builds);
    });
  });
}
