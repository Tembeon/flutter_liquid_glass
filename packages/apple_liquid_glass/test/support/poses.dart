import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A window as the device reports it: the window's size and padding, and
/// the display it lies on, from the lab's measurements
/// (tool/audit/2026-11-24-duo/report.md, glass-lab spec/fold.md and
/// spec/ipad-window.md).
@immutable
final class Pose {
  const Pose(this.name, this.window, this.padding, {Size? display})
    : display = display ?? window;

  final String name;
  final Size window;
  final EdgeInsets padding;
  final Size display;

  /// Lays the test view and its display out as this pose, at a pixel ratio
  /// of 3.
  void apply(WidgetTester tester) {
    const ratio = 3.0;
    tester.view
      ..devicePixelRatio = ratio
      ..physicalSize = window * ratio
      ..padding = FakeViewPadding(
        left: padding.left * ratio,
        top: padding.top * ratio,
        right: padding.right * ratio,
        bottom: padding.bottom * ratio,
      )
      ..viewPadding = FakeViewPadding(
        left: padding.left * ratio,
        top: padding.top * ratio,
        right: padding.right * ratio,
        bottom: padding.bottom * ratio,
      );
    tester.view.display
      ..devicePixelRatio = ratio
      ..size = display * ratio;
    addTearDown(() {
      tester.view.reset();
      tester.view.display.reset();
    });
  }

  @override
  String toString() => name;
}

abstract final class Poses {
  static const iPhone = Pose(
    'iPhone portrait',
    Size(402, 874),
    EdgeInsets.only(top: 62, bottom: 34),
  );
  static const iPhoneLandscape = Pose(
    'iPhone landscape',
    Size(874, 402),
    EdgeInsets.only(left: 62, right: 62, bottom: 21),
  );
  static const iPhoneProMaxLandscape = Pose(
    'iPhone Pro Max landscape',
    Size(956, 440),
    EdgeInsets.only(left: 62, right: 62, bottom: 21),
  );

  static const duoCover = Pose(
    'Duo cover',
    Size(466, 678),
    EdgeInsets.only(right: 84, bottom: 34),
  );
  static const duoCoverClassic = Pose(
    'Duo cover, classic',
    Size(466, 678),
    EdgeInsets.only(top: 82, bottom: 34),
  );
  static const duoCoverLandscapeCameraLeft = Pose(
    'Duo cover landscape, camera on the left',
    Size(678, 466),
    EdgeInsets.only(left: 84, bottom: 34),
  );
  static const duoInner = Pose(
    'Duo inner',
    Size(951, 669),
    EdgeInsets.only(right: 84, bottom: 34),
  );
  static const duoInnerClassic = Pose(
    'Duo inner, classic',
    Size(951, 669),
    EdgeInsets.only(top: 82, bottom: 34),
  );
  static const duoInnerPortrait = Pose(
    'Duo inner portrait',
    Size(669, 951),
    EdgeInsets.only(top: 82, bottom: 34),
  );

  /// duo_kit's measurement on iOS 27.1, not the lab's: the app on the left
  /// of the system Split View gets no room for the column it is meant to
  /// have.
  static const duoInnerSplitViewLeft = Pose(
    'Duo inner, left of Split View',
    Size(469, 669),
    EdgeInsets.only(bottom: 34),
    display: Size(951, 669),
  );

  static const _iPadPro13 = Size(1032, 1376);

  static const iPadWindowSmallest = Pose(
    'iPad window 375 x 486',
    Size(375, 486),
    EdgeInsets.only(top: 24, bottom: 20),
    display: _iPadPro13,
  );
  static const iPadWindowCompactWidest = Pose(
    'iPad window 667 wide',
    Size(667, 700),
    EdgeInsets.only(top: 24, bottom: 20),
    display: _iPadPro13,
  );
  static const iPadWindowShortRegular = Pose(
    'iPad window 915 x 486',
    Size(915, 486),
    EdgeInsets.only(top: 24, bottom: 20),
    display: _iPadPro13,
  );
  static const iPadFull = Pose(
    'iPad Pro 13 landscape',
    Size(1376, 1032),
    EdgeInsets.only(top: 24, bottom: 20),
    display: _iPadPro13,
  );
}
