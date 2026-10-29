import 'dart:math' as math;

import 'package:apple_liquid_glass/src/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of a [GlassSearchField], like Flutter's `ButtonStyle`.
///
/// Every field is resolved against the field's states: focused, pressed,
/// hovered and disabled. A field looks a field up in its own style, then in
/// the theme's, then in its defaults, state by state: a property that gives
/// null for a state leaves that state to the next one.
@immutable
class GlassSearchFieldStyle {
  /// Creates a style.
  const GlassSearchFieldStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.placeholderColor,
    this.iconColor,
    this.cursorColor,
    this.textStyle,
  });

  /// A tint over the field's glass, or, disabled, the plain fill that
  /// replaces it; [GlassSearchField.disabledFill] when disabled and no tint
  /// otherwise, by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The color of the text; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The color of the placeholder; [GlassSearchField.placeholderColors]
  /// by default.
  final WidgetStateProperty<Color?>? placeholderColor;

  /// The color of the magnifier and of the clear button's disc;
  /// [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? iconColor;

  /// The color of the text cursor; [GlassSearchField.cursor] by default.
  final WidgetStateProperty<Color?>? cursorColor;

  /// The text style of the text and the placeholder: 17 points, medium,
  /// by default.
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// This style over [other], state by state.
  GlassSearchFieldStyle merge(GlassSearchFieldStyle? other) {
    if (other == null) return this;
    return GlassSearchFieldStyle(
      backgroundColor: fallThrough(backgroundColor, other.backgroundColor),
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      placeholderColor: fallThrough(placeholderColor, other.placeholderColor),
      iconColor: fallThrough(iconColor, other.iconColor),
      cursorColor: fallThrough(cursorColor, other.cursorColor),
      textStyle: fallThrough(textStyle, other.textStyle),
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassSearchFieldStyle? lerp(
    GlassSearchFieldStyle? a,
    GlassSearchFieldStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassSearchFieldStyle(
      backgroundColor: color(a.backgroundColor, b.backgroundColor),
      foregroundColor: color(a.foregroundColor, b.foregroundColor),
      placeholderColor: color(a.placeholderColor, b.placeholderColor),
      iconColor: color(a.iconColor, b.iconColor),
      cursorColor: color(a.cursorColor, b.cursorColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        a.textStyle,
        b.textStyle,
        t,
        snapNull(TextStyle.lerp),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSearchFieldStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.placeholderColor == placeholderColor &&
      other.iconColor == iconColor &&
      other.cursorColor == cursorColor &&
      other.textStyle == textStyle;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    placeholderColor,
    iconColor,
    cursorColor,
    textStyle,
  );
}

/// An iOS 27 search field.
///
/// UIKit: `UISearchTextField`. SwiftUI: the field of `searchable`. Flutter:
/// `CupertinoSearchTextField`.
///
/// A glass capsule 48 points tall with a magnifier, the text, and a clear
/// button while it holds text. A touch lifts the capsule 0.05 s later on
/// the glass button's lift, without stretching (fitted, search passport),
/// and a tap focuses the field. Disabled, the field drops its glass for a
/// plain fill and keeps its magnifier and placeholder, as UIKit's does
/// (iPhone 16 Pro, iOS 27.0.1). Text follows the text scale up to
/// [maxTextScale]. The keyboard offers no suggestions, as UIKit's search
/// field does not. On iOS a long press shows the system edit menu; other
/// platforms show none yet.
class GlassSearchField extends StatefulWidget {
  /// Creates a search field.
  const GlassSearchField({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.style,
    this.semanticLabel,
    this.clearSemanticLabel,
    super.key,
  });

  /// The text, or null for the field's own.
  final TextEditingController? controller;

  /// The field's focus node, or null for its own.
  final FocusNode? focusNode;

  /// What the empty field shows; `Search` when null.
  final Widget? placeholder;

  /// Called with the text as the user edits it or clears it.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when it first appears.
  final bool autofocus;

  /// The look, over the theme's and the field's defaults.
  final GlassSearchFieldStyle? style;

  /// What accessibility reads for the field; `Search` when null.
  final String? semanticLabel;

  /// What accessibility reads for the clear button; `Clear text` when
  /// null.
  final String? clearSemanticLabel;

  /// The height of the field (search passport).
  static const double height = 48;

  /// The largest text scale the text follows, not measured.
  static const double maxTextScale = 1.5;

  /// The time from a touch to the start of the lift (search passport,
  /// fitted 0.051 s).
  static const double pressDelay = 0.05;

  /// The plain fill of a disabled field: 0x767680 at 6 percent in light
  /// and 12 percent in dark (iPhone 16 Pro, iOS 27.0.1).
  static const disabledFill = GlassDynamicColor.withBrightness(
    color: Color(0x0F767680),
    darkColor: Color(0x1F767680),
  );

  /// The placeholder: secondaryLabel while the field has the focus, and
  /// lighter on the glass without it (an iPhone 16 Pro's screen: 149 on
  /// 252 light, 110 on 32 dark, where the focused placeholder reads 133 and
  /// 142).
  static final WidgetStateProperty<Color?> placeholderColors =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const GlassDynamicColor.withBrightness(
                color: Color(0x993C3C43),
                darkColor: Color(0x8AEBEBF5),
              )
            : const GlassDynamicColor.withBrightness(
                color: Color(0x69000000),
                darkColor: Color(0x59FFFFFF),
              ),
      );

  /// The text cursor, bluer than the accent (an iPhone 16 Pro's screen:
  /// 66, 106, 243 light and 64, 107, 248 dark).
  static const cursor = GlassDynamicColor.withBrightness(
    color: Color(0xFF426AF3),
    darkColor: Color(0xFF406BF8),
  );

  static const _text = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  @override
  State<GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<GlassSearchField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  late final _FieldBody _body = _FieldBody();
  late final _LiftInput _input = _LiftInput(this);
  late final List<Interaction> _interactions = [_input];
  final _regionFocus = FocusNode(skipTraversal: true);
  final _states = WidgetStatesController();
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);
  final _editable = GlobalKey<EditableTextState>();
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'GlassSearchField'));

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editable;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => widget.enabled && _focus.hasFocus;

  @override
  void initState() {
    super.initState();
    _states.update(WidgetState.disabled, !widget.enabled);
    _states.addListener(_statesChanged);
    _focus.addListener(_focusChanged);
    MotionClock.instance.addDriver(_body);
  }

  @override
  void didUpdateWidget(GlassSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focus = oldWidget.focusNode ?? _ownFocus;
    if (!identical(focus, _focus)) {
      focus?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    _states.update(WidgetState.disabled, !widget.enabled);
    if (!widget.enabled) {
      _states.update(WidgetState.pressed, false);
      if (_focus.hasFocus) _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _ends?.removeListener(_ended);
    _focus.removeListener(_focusChanged);
    _states.dispose();
    _regionFocus.dispose();
    _ownController?.dispose();
    _ownFocus?.dispose();
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    super.dispose();
  }

  Listenable? _ends;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ends = SearchEnds.maybeOf(context);
    if (identical(ends, _ends)) return;
    _ends?.removeListener(_ended);
    _ends = ends;
    ends?.addListener(_ended);
  }

  // A search ended from outside the field, by a toolbar's close button,
  // clears the field and lets the keyboard go.
  void _ended() {
    if (_controller.text.isNotEmpty) _clear();
    _focus.unfocus();
  }

  void _statesChanged() => setState(() {});

  void _focusChanged() {
    _states.update(WidgetState.focused, _focus.hasFocus);
    if (_focus.hasFocus) _body.cancel(MotionClock.instance.now);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    _body.reducedMotion = GlassTraits.of(context).reduceMotion;
    final look = (widget.style ?? const GlassSearchFieldStyle())
        .merge(GlassTheme.of(context).searchFieldStyle)
        .merge(_defaults(context));
    final states = _states.value;
    Color resolve(WidgetStateProperty<Color?>? property) =>
        GlassDynamicColor.resolve(property!.resolve(states)!, context);
    final background = look.backgroundColor?.resolve(states);
    final icon = resolve(look.iconColor);
    final cursor = resolve(look.cursorColor);
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: GlassSearchField.maxTextScale);
    final text = resolveGlassText(
      look.textStyle!
          .resolve(states)!
          .copyWith(
            color: resolve(look.foregroundColor),
          ),
      context,
    );
    final editable = EditableText(
      key: _editable,
      controller: _controller,
      focusNode: _focus,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      style: text,
      textScaler: scaler,
      cursorColor: cursor,
      backgroundCursorColor: resolve(look.placeholderColor),
      selectionColor: cursor.withValues(alpha: 0.25),
      textInputAction: TextInputAction.search,
      keyboardAppearance: GlassTraits.of(context).brightness,
      textCapitalization: TextCapitalization.sentences,
      // UIKit's search field offers no suggestions. iOS's engine ties
      // spell checking, and with it the prediction bar, to this flag.
      autocorrect: false,
      enableSuggestions: false,
      rendererIgnoresPointer: true,
      contextMenuBuilder: SystemContextMenu.isSupported(context)
          ? (context, state) =>
                SystemContextMenu.editableText(editableTextState: state)
          : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
    final placeholder = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _controller.text.isEmpty
          ? ExcludeSemantics(
              child: DefaultTextStyle(
                style: text.copyWith(color: resolve(look.placeholderColor)),
                maxLines: 1,
                softWrap: false,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: GlassSearchField.maxTextScale,
                  child: widget.placeholder ?? const Text('Search'),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
    final clear = Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 8,
        end: _Metrics.clearInset,
      ),
      child: Semantics(
        container: true,
        button: true,
        label: widget.clearSemanticLabel ?? 'Clear text',
        onTap: widget.enabled ? _clear : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _clear : null,
          child: SizedBox.square(
            dimension: _Metrics.clearSize,
            child: CustomPaint(
              painter: _ClearPainter(
                fill: icon,
                cross: GlassDynamicColor.resolve(
                  const GlassDynamicColor.withBrightness(
                    color: Color(0xFFFFFFFF),
                    darkColor: Color(0xFF000000),
                  ),
                  context,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final content = Padding(
      padding: const EdgeInsetsDirectional.only(start: _Metrics.glyphInset),
      child: Row(
        children: [
          SizedBox.fromSize(
            size: _Metrics.glyphSize,
            child: CustomPaint(painter: SearchMagnifierPainter(icon)),
          ),
          const SizedBox(
            width:
                _Metrics.textInset - _Metrics.glyphInset - _Metrics.glyphWidth,
          ),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                placeholder,
                Semantics(
                  label: widget.semanticLabel ?? 'Search',
                  child: widget.enabled
                      ? _gestures.buildGestureDetector(
                          behavior: HitTestBehavior.translucent,
                          child: editable,
                        )
                      : IgnorePointer(child: ExcludeFocus(child: editable)),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, child) => _controller.text.isEmpty
                ? const SizedBox(width: _Metrics.clearInset)
                : child!,
            child: clear,
          ),
        ],
      ),
    );
    return InputRegion(
      interactions: _interactions,
      enabled: widget.enabled,
      statesController: _states,
      focusNode: _regionFocus,
      child: SizedBox(
        height: GlassSearchField.height,
        child: widget.enabled
            ? GlassSurface.live(
                frame: _body,
                glass: Glass.regular(tint: background),
                child: content,
              )
            : GlassSurface(
                role: GlassRole.track,
                glass: Glass.regular(tint: background),
                child: content,
              ),
      ),
    );
  }

  GlassSearchFieldStyle _defaults(BuildContext context) {
    final label =
        GlassTheme.of(context).colorScheme?.label ?? GlassColors.label;
    return GlassSearchFieldStyle(
      backgroundColor: const ByState(null, GlassSearchField.disabledFill),
      foregroundColor: WidgetStatePropertyAll(label),
      placeholderColor: GlassSearchField.placeholderColors,
      iconColor: WidgetStatePropertyAll(label),
      cursorColor: const WidgetStatePropertyAll(GlassSearchField.cursor),
      textStyle: const WidgetStatePropertyAll(GlassSearchField._text),
    );
  }
}

/// Where a search field hears that its search ended outside it: the close
/// button of a toolbar that hosts it.
@internal
class SearchEnds extends InheritedWidget {
  /// Tells the search fields below that [ends] notifies when a search
  /// ends.
  const SearchEnds({required this.ends, required super.child, super.key});

  /// Notifies when a search ends.
  final Listenable ends;

  /// The ends around [context], or null.
  static Listenable? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchEnds>()?.ends;

  @override
  bool updateShouldNotify(SearchEnds oldWidget) => ends != oldWidget.ends;
}

/// The search field's glyph and inset metrics, read from an iPhone 16
/// Pro's screen (search passport).
abstract final class _Metrics {
  /// The space between the field's leading edge and the magnifier.
  static const double glyphInset = 12;

  /// The width of the magnifier glyph.
  static const double glyphWidth = 20.67;

  /// The size of the magnifier glyph.
  static const Size glyphSize = Size(glyphWidth, 19.33);

  /// The space between the field's leading edge and its text.
  static const double textInset = 40.67;

  /// The size of the clear button.
  static const double clearSize = 20;

  /// The diameter of the clear button's disc inside its [clearSize] box.
  static const double clearInk = 16.67;

  /// The space between the clear button and the field's trailing edge.
  static const double clearInset = 13.33;
}

/// The field's lift, stepped on the motion clock and published as the
/// frames of its glass.
final class _FieldBody extends ChangeNotifier
    implements ValueListenable<GlassFrame>, MotionDriver {
  final FlexInteraction _flex = FlexInteraction(
    size: const Size(346, GlassSearchField.height),
    stretches: false,
    activationDelay: GlassSearchField.pressDelay,
  );
  GlassFrame _value = const GlassFrame();

  set reducedMotion(bool value) => _flex.reducedMotion = value;
  bool get reducedMotion => _flex.reducedMotion;

  @override
  GlassFrame get value => _value;

  // A lift can come to rest between frames; one more step lands it there.
  @override
  bool get isActive =>
      !_flex.isSettled(MotionClock.instance.now) ||
      (!_flex.isPressed && _value != const GlassFrame());

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _flex.advance(time);
    // A released lift that rests lands exactly on rest, invisibly.
    final next = !_flex.isPressed && _flex.isSettled(time)
        ? const GlassFrame()
        : GlassFrame(scaleX: _flex.scaleX(time), scaleY: _flex.scaleY(time));
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  void down(double t, Offset position, Size size) {
    _flex.size = size;
    _flex.pointerDown(t, position);
    MotionClock.instance.wake(this);
  }

  void move(double t, Offset position) {
    _flex.pointerMove(t, position);
    MotionClock.instance.wake(this);
  }

  void up(double t) {
    _flex.pointerUp(t);
    MotionClock.instance.wake(this);
  }

  void cancel(double t) {
    _flex.pointerCancel(t);
    MotionClock.instance.wake(this);
  }
}

/// Follows a touch on the field to lift it, and focuses the field on a
/// tap; it never holds the touch, so the text's own gestures and a scroll
/// still take it.
final class _LiftInput extends Interaction {
  _LiftInput(this._owner) : super(role: InteractionRole.content);

  final _GlassSearchFieldState _owner;
  int? _pointer;
  Offset _down = Offset.zero;

  @override
  bool get pressed => _pointer != null;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && !_owner._focus.hasFocus;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _down = input.position;
        _owner._body.down(input.time, input.position, input.regionSize);
      case PointerMoveInput() when input.pointer == _pointer:
        _owner._body.move(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._body.up(input.time);
        if ((input.position - _down).distance < kTouchSlop) {
          _owner._focus.requestFocus();
        }
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._body.cancel(input.time);
      default:
    }
    return InteractionUpdate.none;
  }
}

class _ClearPainter extends CustomPainter {
  const _ClearPainter({required this.fill, required this.cross});

  final Color fill;
  final Color cross;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r =
        math.min(size.width, size.height) /
        2 *
        _Metrics.clearInk /
        _Metrics.clearSize;
    final disc = Paint();
    disc.color = fill;
    canvas.drawCircle(c, r, disc);
    final x = Paint();
    x.color = cross;
    x.style = PaintingStyle.stroke;
    x.strokeWidth = r * 0.2;
    x.strokeCap = StrokeCap.round;
    final d = r * 0.36;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), x);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), x);
  }

  @override
  bool shouldRepaint(_ClearPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.cross != cross;
}
