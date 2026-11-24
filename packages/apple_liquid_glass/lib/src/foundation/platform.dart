import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:apple_liquid_glass/src/foundation/environment.dart';
import 'package:apple_liquid_glass/src/foundation/platform_silent.dart'
    if (dart.library.ffi) 'package:apple_liquid_glass/src/foundation/platform_native.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Whether the iPhone Duo shows its side column: the vertical bar UIKit puts
/// along one edge of the screen, with the status bar in it.
///
/// One choice per app: a Flutter app is one view controller, and UIKit asks
/// it which it prefers.
enum GlassBarColumnBehavior {
  /// The system decides; on the Duo the column shows.
  automatic,

  /// No column: the status bar goes back to the top, and the safe area with
  /// it.
  disabled,
}

/// Reads what the operating system decides about the window and gives it to
/// [GlassEnvironment.of] below it, and the accessibility settings Flutter
/// does not report, which it gives to [GlassTraits.of].
///
/// On iOS it asks UIKit, synchronously, when it is first built and again on
/// every change of the window's metrics and every turn of the iPhone Duo's
/// hinge: the device class, the size classes, the side column, the regions
/// the hardware covers. While the Duo is half open it adds the crease to
/// [MediaQueryData.displayFeatures] as a fold, which Flutter does not report,
/// so dialogs and popups keep to one part of the screen. Elsewhere it reports
/// no window and [GlassEnvironment.of] derives its values from the window's
/// size.
///
/// On iOS and macOS it reads the settings when it is first built and again
/// whenever the system posts a change: Reduce Transparency, Show Borders
/// (Button Shapes on iOS before 26.1), and on iOS Prefer Cross-Fade
/// Transitions, the Liquid Glass slider of iOS 27 and the system's
/// preference for reduced resource usage. A `GlassTraitsOverride` overrides
/// them. In `flutter test` it reads nothing, so a test does not depend on
/// the settings of the machine it runs on.
///
/// `GlassScope` puts one at the root. The outermost one reads the platform;
/// any below it hand it their [barColumnBehavior] and lay its fold into the
/// [MediaQuery] they find, so an app can put one above its `WidgetsApp` or
/// below `GlassScope` alike.
class GlassPlatformScope extends StatefulWidget {
  /// Reads the platform for [child].
  const GlassPlatformScope({
    required this.child,
    this.barColumnBehavior,
    super.key,
  });

  /// Whether the iPhone Duo shows its side column; null leaves it to the
  /// other scopes. The deepest scope that names one decides, and with none
  /// the column is [GlassBarColumnBehavior.disabled]: these widgets lay the
  /// Duo out as an iPhone, with the status bar at the top. Set once a frame
  /// is drawn, since UIKit changes the safe area at once.
  ///
  /// UIKit asks the root view controller, so once a window shows a column
  /// the scope adds `preferredVerticalBarBehavior` to the Flutter view
  /// controller's class at run time. A runner whose own controller subclass
  /// answers it keeps that answer, and this choice is then ignored.
  final GlassBarColumnBehavior? barColumnBehavior;

  /// The subtree.
  final Widget child;

  @override
  State<GlassPlatformScope> createState() => _GlassPlatformScopeState();
}

class _GlassPlatformScopeState extends State<GlassPlatformScope>
    with WidgetsBindingObserver {
  GlassPlatformReader? _reader;
  _GlassPlatformScopeState? _reading;
  final _below = <_GlassPlatformScopeState>[];
  bool _applying = false;
  bool _started = false;
  GlassPlatformReport _report = GlassPlatformReport.none;
  GlassPlatformSettings _settings = GlassPlatformSettings.none;
  ({List<DisplayFeature> ambient, Rect fold, List<DisplayFeature> features})?
  _withFold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final above = context
        .getInheritedWidgetOfExactType<_GlassPlatformInherited>()
        ?.scope;
    if (above != null) {
      _reading = above.._below.add(this);
      return;
    }
    final reader = (debugGlassPlatformReader ?? createGlassPlatformReader)();
    if (reader is GlassSilentPlatformReader) return;
    _reader = reader;
    _report = reader.read();
    _settings = reader.readSettings();
    reader.addListener(_read);
    WidgetsBinding.instance.addObserver(this);
    _applyBarColumnBehavior();
  }

  @override
  void didUpdateWidget(GlassPlatformScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barColumnBehavior != widget.barColumnBehavior) {
      (_reading ?? this)._applyBarColumnBehavior();
    }
  }

  GlassBarColumnBehavior get _barColumnBehavior {
    for (final scope in _below.reversed) {
      if (scope.widget.barColumnBehavior case final behavior?) return behavior;
    }
    return widget.barColumnBehavior ?? GlassBarColumnBehavior.disabled;
  }

  void _applyBarColumnBehavior() {
    final reader = _reader;
    if (reader == null || _applying) return;
    _applying = true;
    // After the frame: UIKit changes the safe area inside the call and
    // Flutter reports it before the call returns, which no build can take.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _applying = false;
      if (!mounted) return;
      reader.setBarColumnBehavior(_barColumnBehavior);
    });
  }

  @override
  void didChangeMetrics() => _read();

  void _read() {
    final reader = _reader!;
    final report = reader.read();
    final settings = reader.readSettings();
    if (report == _report && settings == _settings) return;
    if (report.barColumn != _report.barColumn) _applyBarColumnBehavior();
    setState(() {
      _report = report;
      _settings = settings;
    });
  }

  @override
  void dispose() {
    final reading = _reading;
    if (reading != null && reading._below.remove(this)) {
      reading._applyBarColumnBehavior();
    }
    final reader = _reader;
    if (reader != null) {
      reader.removeListener(_read);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  // MediaQuery tells its dependents about display features by the list's
  // identity, so the list is made again only when the fold or the ambient
  // features change.
  List<DisplayFeature> _featuresWith(List<DisplayFeature> ambient, Rect fold) {
    final kept = _withFold;
    if (kept != null && identical(kept.ambient, ambient) && kept.fold == fold) {
      return kept.features;
    }
    final features = List<DisplayFeature>.unmodifiable([
      ...ambient,
      DisplayFeature(
        bounds: fold,
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ]);
    _withFold = (ambient: ambient, fold: fold, features: features);
    return features;
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final GlassPlatformReport report;
    if (_reader != null) {
      report = _report;
      child = _GlassPlatformInherited(
        scope: this,
        report: report,
        child: _GlassPlatformSettingsInherited(
          settings: _settings,
          child: widget.child,
        ),
      );
    } else if (_reading != null) {
      report = GlassPlatformReport.maybeOf(context)!;
      child = widget.child;
    } else {
      return widget.child;
    }
    final media = MediaQuery.maybeOf(context);
    if (media == null) return child;
    final fold = report.fold;
    final ambient = media.displayFeatures;
    return MediaQuery(
      data:
          fold == null ||
              ambient.any(
                (feature) =>
                    feature.type == DisplayFeatureType.fold ||
                    feature.type == DisplayFeatureType.hinge,
              )
          ? media
          : media.copyWith(displayFeatures: _featuresWith(ambient, fold)),
      child: child,
    );
  }
}

class _GlassPlatformInherited extends InheritedWidget {
  const _GlassPlatformInherited({
    required this.scope,
    required this.report,
    required super.child,
  });

  final _GlassPlatformScopeState scope;
  final GlassPlatformReport report;

  @override
  bool updateShouldNotify(_GlassPlatformInherited oldWidget) =>
      report != oldWidget.report;
}

/// What the operating system reported about the window; null where it said
/// nothing.
@immutable
final class GlassPlatformReport {
  /// A report of the given values.
  const GlassPlatformReport({
    this.formFactor,
    this.horizontalSizeClass,
    this.verticalSizeClass,
    this.barColumn,
    this.occlusions,
    this.fold,
  });

  /// The report of a window UIKit describes, in the view's points.
  ///
  /// [activeDivisions] are UIKit's active division regions, the crease's band
  /// among them. The band is the fold unless the hinge is known to be closed
  /// or fully open, or it does not lie inside the view: for a moment after
  /// the Duo closes, the cover display still reports the inner display's
  /// band, turned and active. The hinge's first report comes after the first
  /// frame, so an unknown hinge decides nothing.
  factory GlassPlatformReport.fromUIKit({
    required GlassFormFactor? formFactor,
    required GlassSizeClass? horizontalSizeClass,
    required GlassSizeClass? verticalSizeClass,
    required GlassBarColumnSide? barColumnSide,
    required Size size,
    required EdgeInsets safeArea,
    required List<Rect> occlusions,
    required List<Rect> activeDivisions,
    required bool hingeFlat,
  }) {
    final window = (Offset.zero & size).inflate(_edgeTolerance);
    Rect? fold;
    if (!hingeFlat) {
      for (final band in activeDivisions) {
        if (window.contains(band.topLeft) &&
            window.contains(band.bottomRight)) {
          fold = band;
          break;
        }
      }
    }
    return GlassPlatformReport(
      formFactor: formFactor,
      horizontalSizeClass: horizontalSizeClass,
      verticalSizeClass: verticalSizeClass,
      barColumn: switch (barColumnSide) {
        null => GlassBarColumn.none,
        GlassBarColumnSide.left => GlassBarColumn(
          side: GlassBarColumnSide.left,
          reservedWidth: safeArea.left,
        ),
        GlassBarColumnSide.right => GlassBarColumn(
          side: GlassBarColumnSide.right,
          reservedWidth: safeArea.right,
        ),
      },
      occlusions: List.unmodifiable(occlusions),
      fold: fold,
    );
  }

  /// Nothing reported.
  static const none = GlassPlatformReport();

  static const _edgeTolerance = 0.5;

  /// The device class.
  final GlassFormFactor? formFactor;

  /// The horizontal size class.
  final GlassSizeClass? horizontalSizeClass;

  /// The vertical size class.
  final GlassSizeClass? verticalSizeClass;

  /// The side column.
  final GlassBarColumn? barColumn;

  /// The regions the hardware covers, in the view's coordinates.
  final List<Rect>? occlusions;

  /// The crease's band while the iPhone Duo is half open.
  final Rect? fold;

  /// The report of the nearest [GlassPlatformScope], if any.
  static GlassPlatformReport? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlassPlatformInherited>()
      ?.report;

  @override
  bool operator ==(Object other) =>
      other is GlassPlatformReport &&
      other.formFactor == formFactor &&
      other.horizontalSizeClass == horizontalSizeClass &&
      other.verticalSizeClass == verticalSizeClass &&
      other.barColumn == barColumn &&
      listEquals(other.occlusions, occlusions) &&
      other.fold == fold;

  @override
  int get hashCode => Object.hash(
    formFactor,
    horizontalSizeClass,
    verticalSizeClass,
    barColumn,
    occlusions == null ? null : Object.hashAll(occlusions!),
    fold,
  );

  @override
  String toString() =>
      'GlassPlatformReport(formFactor: $formFactor, '
      'horizontalSizeClass: $horizontalSizeClass, '
      'verticalSizeClass: $verticalSizeClass, barColumn: $barColumn, '
      'occlusions: $occlusions, fold: $fold)';
}

class _GlassPlatformSettingsInherited extends InheritedWidget {
  const _GlassPlatformSettingsInherited({
    required this.settings,
    required super.child,
  });

  final GlassPlatformSettings settings;

  @override
  bool updateShouldNotify(_GlassPlatformSettingsInherited oldWidget) =>
      settings != oldWidget.settings;
}

/// The accessibility settings the operating system reported that Flutter
/// does not; null where it said nothing.
@immutable
final class GlassPlatformSettings {
  /// Settings of the given values.
  const GlassPlatformSettings({
    this.reduceTransparency,
    this.showBorders,
    this.prefersCrossFade,
    this.glassTintAmount,
    this.prefersReducedResourceUsage,
  });

  /// Nothing reported.
  static const none = GlassPlatformSettings();

  /// See [GlassTraits.reduceTransparency].
  final bool? reduceTransparency;

  /// See [GlassTraits.showBorders].
  final bool? showBorders;

  /// See [GlassTraits.prefersCrossFade].
  final bool? prefersCrossFade;

  /// See [GlassTraits.glassTintAmount].
  final double? glassTintAmount;

  /// See [GlassTraits.prefersReducedResourceUsage].
  final bool? prefersReducedResourceUsage;

  /// The settings the nearest reading [GlassPlatformScope] reported, if any.
  static GlassPlatformSettings? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlassPlatformSettingsInherited>()
      ?.settings;

  @override
  bool operator ==(Object other) =>
      other is GlassPlatformSettings &&
      other.reduceTransparency == reduceTransparency &&
      other.showBorders == showBorders &&
      other.prefersCrossFade == prefersCrossFade &&
      other.glassTintAmount == glassTintAmount &&
      other.prefersReducedResourceUsage == prefersReducedResourceUsage;

  @override
  int get hashCode => Object.hash(
    reduceTransparency,
    showBorders,
    prefersCrossFade,
    glassTintAmount,
    prefersReducedResourceUsage,
  );

  @override
  String toString() =>
      'GlassPlatformSettings(reduceTransparency: $reduceTransparency, '
      'showBorders: $showBorders, prefersCrossFade: $prefersCrossFade, '
      'glassTintAmount: $glassTintAmount, '
      'prefersReducedResourceUsage: $prefersReducedResourceUsage)';
}

/// Reads the platform for a [GlassPlatformScope]. It notifies when something
/// changed that no change of the window's metrics reports: the hinge, a
/// setting.
abstract interface class GlassPlatformReader implements Listenable {
  /// What the platform reports about the window now.
  GlassPlatformReport read();

  /// The settings now.
  GlassPlatformSettings readSettings();

  /// Asks the platform to show or hide the iPhone Duo's side column.
  void setBarColumnBehavior(GlassBarColumnBehavior behavior);
}

/// A reader that reports nothing, for platforms that have nothing to read.
final class GlassSilentPlatformReader implements GlassPlatformReader {
  /// The reader.
  const GlassSilentPlatformReader();

  @override
  GlassPlatformReport read() => GlassPlatformReport.none;

  @override
  GlassPlatformSettings readSettings() => GlassPlatformSettings.none;

  @override
  void setBarColumnBehavior(GlassBarColumnBehavior behavior) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Replaces the platform's reader in tests.
@visibleForTesting
GlassPlatformReader Function()? debugGlassPlatformReader;
