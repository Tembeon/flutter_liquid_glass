import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'sheet_detents.dart';
part 'sheet_render.dart';
part 'sheet_view.dart';

/// The look of sheets, and of popovers that adapt to one; a null field
/// leaves it to the theme's style, then the default.
@immutable
class GlassSheetStyle extends GlassStyle<GlassSheetStyle> {
  /// Creates a style.
  const GlassSheetStyle({
    this.backgroundColor,
    this.dragHandleColor,
    this.textStyle,
  });

  /// The theme's [GlassSheetStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassSheetStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassSheetStyle>(context);

  /// The opaque fill of a sheet that fills the screen or sits under
  /// another; white in light and 0x1C1C1E in dark by default (simulator).
  final Color? backgroundColor;

  /// The drag handle; 0x3C3C43 at 30 percent in light and 0xEBEBF5 at 30
  /// percent in dark (tertiaryLabel's color, simulator) by default.
  final Color? dragHandleColor;

  /// The default text of the content, over 17 points in label.
  final TextStyle? textStyle;

  /// This style over [other].
  @override
  GlassSheetStyle merge(GlassSheetStyle? other) {
    if (other == null) return this;
    return GlassSheetStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      dragHandleColor: dragHandleColor ?? other.dragHandleColor,
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassSheetStyle lerp(GlassSheetStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    return GlassSheetStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor, t),
      dragHandleColor: color(dragHandleColor, other.dragHandleColor, t),
      textStyle: GlassStyle.lerpNullable(TextStyle.lerp)(
        textStyle,
        other.textStyle,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSheetStyle &&
      other.backgroundColor == backgroundColor &&
      other.dragHandleColor == dragHandleColor &&
      other.textStyle == textStyle;

  @override
  int get hashCode => Object.hash(backgroundColor, dragHandleColor, textStyle);
}

/// Shows an iOS 27 sheet over the page and completes with the result it
/// is closed with.
///
/// UIKit: `UISheetPresentationController`. SwiftUI: `sheet` with
/// `presentationDetents`. Flutter: `showModalBottomSheet`,
/// `showCupertinoSheet`.
///
/// The sheet rests at one of its `detents`, the first or `initialDetent`
/// to begin with. Below [GlassSheetDetent.large] it floats on glass 8
/// points from the screen's sides and bottom with the display's corners;
/// at the large detent it docks, opaque and square at the bottom. It moves
/// between them on UIKit's critically damped spring of response 0.344
/// (read from UIKit, replayed against the iPhone 16 Pro): a drag carries
/// it and rubber-bands past its largest and smallest detents, a release
/// picks the detent its speed projects to, a drag down past the smallest
/// dismisses it, and a tap at its top cycles to the next detent.
///
/// Detents at or below `largestUndimmedDetent` leave the page undimmed
/// and touchable; the others dim it 20 percent. A keyboard raises every
/// detent by its height. A drag on the content's main scrollable, driven
/// by [GlassSheet.scrollControllerOf], moves the sheet first while the
/// content is at its top, and expands it toward its largest detent when
/// `scrollingExpandsSheet`. Back and `Navigator.pop` close it; a drag
/// down, a tap on the dimming, Escape and a screen reader's dismiss close
/// it when `isDismissible` and no `PopScope` in it vetoes, and otherwise
/// call `onDismissAttempt`. Android's predictive back drags the sheet
/// down with the gesture and dismisses it on commit.
///
/// The band at the sheet's top, where a tap cycles the detents, is also
/// the sheet's detent control for the keyboard and screen readers: a
/// target of 44 points named [GlassLocalizations.sheetGrabberLabel] around
/// the drag handle (or where it would be), a focus stop whose arrows, Page
/// Up and Page Down, Home and End step between the detents, read as its
/// value with increase and decrease actions. Screen readers hear the sheet
/// as a dialog named by [semanticLabel], and find the dimming as
/// [GlassLocalizations.sheetDismissLabel] when a tap on it dismisses.
///
/// The liquid renderer draws the floating glass with the top corners'
/// radius all round, clipped at the bottom to the display's corners: its
/// rim light at the bottom corners follows a 38 point curve under a 54
/// point clip (NEAR).
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  List<GlassSheetDetent> detents = const [GlassSheetDetent.large],
  GlassSheetDetent? initialDetent,
  GlassSheetDetent? largestUndimmedDetent,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool scrollingExpandsSheet = true,
  GlassSheetStyle? style,
  String? semanticLabel,
  ValueChanged<GlassSheetDetent>? onDetentChanged,
  VoidCallback? onDismissAttempt,
  PresentationLevel level = PresentationLevel.window,
}) {
  assert(detents.isNotEmpty, 'a sheet rests at a detent');
  final spec = _SheetSpec(
    builder: builder,
    detents: detents,
    initialDetent: initialDetent,
    largestUndimmedDetent: largestUndimmedDetent,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    scrollingExpandsSheet: scrollingExpandsSheet,
    style: style,
    onDetentChanged: onDetentChanged,
  );
  return showPresentation(
    context,
    PresentationRoute(
      presentation: Presentation<T, _SheetPresented>(
        motion: (_) => _SheetPresented(),
        builder: (context, motion) => _SheetView(motion: motion, spec: spec),
        // Back and Navigator.pop close it either way.
        dismiss: isDismissible
            ? const DismissPolicy()
            : const DismissPolicy({DismissTrigger.back}),
        dim: (motion) =>
            _SheetLook.dimmingOpacity * (motion.sheet?.dimming ?? 0),
        modal: (motion) => (motion.sheet?.dimming ?? 1) > 0,
        onVeto: onDismissAttempt == null ? null : (_) => onDismissAttempt(),
        semanticsLabel: semanticLabel,
        semanticsRole: SemanticsRole.dialog,
        barrierLabel: isDismissible
            ? GlassLocalizations.of(context).sheetDismissLabel
            : null,
      ),
    ),
    level: level,
  );
}

/// What [showGlassSheet] was asked for.
@immutable
class _SheetSpec {
  const _SheetSpec({
    required this.builder,
    required this.detents,
    required this.initialDetent,
    required this.largestUndimmedDetent,
    required this.showDragHandle,
    required this.isDismissible,
    required this.scrollingExpandsSheet,
    required this.style,
    required this.onDetentChanged,
  });

  final WidgetBuilder builder;
  final List<GlassSheetDetent> detents;
  final GlassSheetDetent? initialDetent;
  final GlassSheetDetent? largestUndimmedDetent;
  final bool showDragHandle;
  final bool isDismissible;
  final bool scrollingExpandsSheet;
  final GlassSheetStyle? style;
  final ValueChanged<GlassSheetDetent>? onDetentChanged;

  GlassSheetStyle lookOf(BuildContext context) =>
      (style ?? const GlassSheetStyle()).merge(
        GlassSheetStyle.maybeOf(context),
      );
}

/// A sheet's presentation: its [SheetMotion] comes with the first layout,
/// whose detents it needs, and presents then.
final class _SheetPresented extends Motion with Presented, PredictiveBack {
  SheetMotion? _sheet;
  bool _opened = false;
  bool _left = false;
  // The velocity, down in pixels per second, of a back gesture that
  // committed: the leave that follows continues from it.
  double? _backVelocity;

  // UIKit asks at least 80 Hz of this (read from UIKit, notes private).
  @override
  double get minFrameRate => 80;

  SheetMotion? get sheet => _sheet;

  /// Whether the presentation was dismissed.
  bool get left => _left;

  void attach(double t, SheetMotion sheet) {
    _sheet = own(sheet);
    if (_opened && !_left) sheet.present(t);
  }

  @override
  PresenceStatus get presence {
    final sheet = _sheet;
    if (sheet == null) return _opened && !_left ? .opening : .hidden;
    if (sheet.isDismissing) return sheet.isDismissed ? .hidden : .leaving;
    return isSettled ? .shown : .opening;
  }

  @override
  void open(double t) => _opened = true;

  @override
  bool leave(double t, DismissTrigger trigger) {
    _left = true;
    final sheet = _sheet;
    if (sheet == null) return false;
    final back = _backVelocity;
    _backVelocity = null;
    if (back != null) {
      sheet.dismiss(t, velocity: back);
      return true;
    }
    if (sheet.isDragging) sheet.dragCancel(t);
    if (!sheet.isDismissing) sheet.dismiss(t);
    return true;
  }

  @override
  void backStarted(double t) => _sheet?.backStart(t);

  @override
  void backMoved(double t, double progress) => _sheet?.backMove(t, progress);

  @override
  void backEnded(double t, {required bool commits, required double velocity}) {
    final sheet = _sheet;
    if (sheet == null) return;
    if (commits) {
      _backVelocity = sheet.backVelocity(velocity);
    } else {
      sheet.backCancel(t);
    }
  }
}

/// What a sheet's content can do with its sheet.
abstract interface class GlassSheet {
  /// The detent the sheet rests at or heads to.
  GlassSheetDetent get detent;

  /// The sheet's detents.
  List<GlassSheetDetent> get detents;

  /// Moves the sheet to [detent] on the sheet's spring.
  void animateTo(GlassSheetDetent detent);

  /// The sheet around [context]; [context] rebuilds when its detent
  /// changes.
  static GlassSheet of(BuildContext context) {
    final sheet = maybeOf(context);
    if (sheet == null) {
      throw FlutterError('GlassSheet.of called outside a glass sheet.');
    }
    return sheet;
  }

  /// The sheet around [context], or null outside one.
  static GlassSheet? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DetentScope>()?.state;

  /// A scroll controller for the sheet's main scrollable that hands its
  /// drags to the sheet as UIKit does; [context] does not rebuild when the
  /// detent changes.
  static ScrollController scrollControllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_SheetScope>();
    if (scope == null) {
      throw FlutterError(
        'GlassSheet.scrollControllerOf called outside a glass sheet.',
      );
    }
    return scope.state._scroll;
  }
}

class _SheetScope extends InheritedWidget {
  const _SheetScope({required this.state, required super.child});

  final _SheetViewState state;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) => false;
}

/// Rebuilds what read the sheet with [GlassSheet.of] when its detent
/// changes, and nothing else.
class _DetentScope extends InheritedNotifier<ValueNotifier<int>> {
  const _DetentScope({
    required this.state,
    required ValueNotifier<int> detent,
    required super.child,
  }) : super(notifier: detent);

  final _SheetViewState state;
}

/// The sheet's geometry in one frame.
@immutable
class _Frame {
  const _Frame({
    required this.height,
    required this.transform,
    required this.body,
  });

  final double height;
  final Matrix4 transform;
  final RSuperellipse body;
}

/// The colors of a sheet, light and dark (simulator).
abstract final class _Colors {
  static const docked = GlassDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1C1E),
  );
  static const grabber = GlassDynamicColor.withBrightness(
    color: Color(0x4D3C3C43),
    darkColor: Color(0x4DEBEBF5),
  );
}
