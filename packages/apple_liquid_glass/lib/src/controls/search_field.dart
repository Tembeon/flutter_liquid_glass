import 'dart:math' as math;

import 'package:apple_liquid_glass/src/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/motion/glass_press.dart';
import 'package:apple_liquid_glass/src/motion/search_motion.dart';
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
/// Every property but [builder] resolves against the field's states
/// (focused, pressed, hovered, disabled) and falls through, state by state,
/// from this style to the theme's to the field's defaults: a null for a
/// state leaves that state to the next one.
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
    this.builder,
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

  /// Builds the field in place of its default look, which then ignores the
  /// other fields. Null leaves it to the theme's builder, then the default
  /// look.
  final GlassSearchFieldBuilder? builder;

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
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// half.
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
      builder: t < 0.5 ? a.builder : b.builder,
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
      other.textStyle == textStyle &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    placeholderColor,
    iconColor,
    cursorColor,
    textStyle,
    builder,
  );
}

/// Builds a search field from [details]; it runs when the field builds,
/// such as when its states change, never on a frame of its motion.
typedef GlassSearchFieldBuilder = Widget Function(
  BuildContext context,
  GlassSearchFieldDetails details,
);

/// What a [GlassSearchFieldBuilder] builds a search field from.
final class GlassSearchFieldDetails {
  const GlassSearchFieldDetails._(
    this._text, {
    required this.frame,
    required this.states,
    required this.controller,
    required this.clear,
  });

  /// The frame of the field's glass as a touch lifts it; under a
  /// navigation bar's large title its opacity follows the glass's presence,
  /// and the field's text and glyphs stay.
  final MotionSelection<GlassFrame> frame;

  /// The states the field is in: focused, pressed, hovered, disabled.
  final Set<WidgetState> states;

  /// The field's text; a look listens to it to show a placeholder or a
  /// clear button.
  final TextEditingController controller;

  /// Clears the text and reports it, or null while the field is disabled.
  final VoidCallback? clear;

  final Widget Function(TextStyle style, Color cursor, Color placeholder) _text;

  /// The editable text with its gestures and semantics, drawn in [style]
  /// with a [cursorColor] cursor; [backgroundCursorColor] colors the
  /// cursor's resting ghost while a force press moves it
  /// (`EditableText.backgroundCursorColor`). The default look passes the
  /// placeholder color.
  Widget text({
    required TextStyle style,
    required Color cursorColor,
    required Color backgroundCursorColor,
  }) => _text(style, cursorColor, backgroundCursorColor);
}

/// A search field with the measured lift of iOS 27's `UISearchTextField`
/// and no look of its own: [builder] decides how it looks and places the
/// editable text it gets from [GlassSearchFieldDetails.text].
///
/// UIKit: `UISearchTextField`. SwiftUI: the field of `searchable`. Flutter:
/// `CupertinoSearchTextField`.
///
/// It is 48 points tall. A touch lifts it 0.05 s later on the glass
/// button's lift, without stretching (fitted, search passport), and a tap
/// focuses it. Text follows the text scale up to
/// [GlassSearchField.maxTextScale]. The keyboard offers no suggestions, as
/// UIKit's search field does not. On iOS a long press shows the system
/// edit menu; other platforms show none.
class RawGlassSearchField extends StatefulWidget {
  /// Creates a search field.
  const RawGlassSearchField({
    required this.builder,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Builds the field's look.
  final GlassSearchFieldBuilder builder;

  /// The text, or null for the field's own.
  final TextEditingController? controller;

  /// The field's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Called with the text as the user edits it or clears it.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the field; `Search` when null.
  final String? semanticLabel;

  @override
  State<RawGlassSearchField> createState() => _RawGlassSearchFieldState();
}

class _RawGlassSearchFieldState extends State<RawGlassSearchField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final GlassPress _press = GlassPress(
    size: const Size(346, SearchTuning.height),
    law: SearchTuning.pressLaw,
  );
  late final _lift = _press.select(
    (p) => p.isAtRest
        ? const GlassFrame()
        : GlassFrame(scaleX: p.scaleX, scaleY: p.scaleY),
  );
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
  }

  @override
  void didUpdateWidget(RawGlassSearchField oldWidget) {
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
    super.dispose();
  }

  Listenable? _ends;
  MotionValue<double>? _fadedGlass;
  late MotionSelection<GlassFrame> _faded;

  MotionSelection<GlassFrame> _fadedBy(MotionValue<double> glass) {
    if (identical(glass, _fadedGlass)) return _faded;
    _fadedGlass = glass;
    return _faded = MotionSelection(() {
      final frame = _lift.value;
      return frame.copyWith(
        opacity: frame.opacity * glass.value.clamp(0.0, 1.0),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ends = SearchEnds.maybeOf(context);
    if (identical(ends, _ends)) return;
    _ends?.removeListener(_ended);
    _ends = ends;
    ends?.addListener(_ended);
  }

  void _ended() {
    if (_controller.text.isNotEmpty) _clear();
    _focus.unfocus();
  }

  void _statesChanged() => setState(() {});

  void _focusChanged() {
    _states.update(WidgetState.focused, _focus.hasFocus);
    if (_focus.hasFocus) _press.pointerCancel(MotionClock.instance.now);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  Widget _text(TextStyle style, Color cursor, Color placeholder) {
    final editable = EditableText(
      key: _editable,
      controller: _controller,
      focusNode: _focus,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      style: style,
      textScaler: MediaQuery.textScalerOf(
        context,
      ).clamp(maxScaleFactor: GlassSearchField.maxTextScale),
      cursorColor: cursor,
      backgroundCursorColor: placeholder,
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
    return Semantics(
      label: widget.semanticLabel ?? 'Search',
      child: widget.enabled
          ? _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: editable,
            )
          : IgnorePointer(child: ExcludeFocus(child: editable)),
    );
  }

  @override
  Widget build(BuildContext context) {
    _press.reducedMotion = GlassTraits.of(context).reduceMotion;
    final stacking = SearchFieldStacking.maybeOf(context);
    return InputRegion(
      interactions: _interactions,
      enabled: widget.enabled,
      statesController: _states,
      focusNode: _regionFocus,
      child: SizedBox(
        height: stacking?.height ?? SearchTuning.height,
        child: widget.builder(
          context,
          GlassSearchFieldDetails._(
            _text,
            frame: stacking == null ? _lift : _fadedBy(stacking.glass),
            states: {..._states.value},
            controller: _controller,
            clear: widget.enabled ? _clear : null,
          ),
        ),
      ),
    );
  }
}

/// An iOS 27 search field.
///
/// UIKit: `UISearchTextField`. SwiftUI: the field of `searchable`. Flutter:
/// `CupertinoSearchTextField`.
///
/// A glass capsule 48 points tall with a magnifier, the text, and a clear
/// button while it holds text; its lift and input are
/// [RawGlassSearchField]'s. Disabled, the field drops its glass for a plain
/// fill and keeps its magnifier and placeholder, as UIKit's does (iPhone 16
/// Pro, iOS 27.0.1).
class GlassSearchField extends StatelessWidget {
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
  static const double height = SearchTuning.height;

  /// The largest text scale the text follows, not measured.
  static const double maxTextScale = 1.5;

  /// The time from a touch to the start of the lift.
  static const double pressDelay = SearchTuning.pressDelay;

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
  Widget build(BuildContext context) {
    final look = (style ?? const GlassSearchFieldStyle()).merge(
      GlassTheme.of(context).searchFieldStyle,
    );
    return RawGlassSearchField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      builder:
          look.builder ??
          (context, details) => _SearchFieldLook(
            details: details,
            style: look.merge(_defaults(context)),
            placeholder: placeholder,
            clearSemanticLabel: clearSemanticLabel,
          ),
    );
  }

  static GlassSearchFieldStyle _defaults(BuildContext context) {
    final label = GlassTheme.of(context).labelColor;
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

class _SearchFieldLook extends StatefulWidget {
  const _SearchFieldLook({
    required this.details,
    required this.style,
    required this.placeholder,
    required this.clearSemanticLabel,
  });

  final GlassSearchFieldDetails details;
  final GlassSearchFieldStyle style;
  final Widget? placeholder;
  final String? clearSemanticLabel;

  @override
  State<_SearchFieldLook> createState() => _SearchFieldLookState();
}

class _SearchFieldLookState extends State<_SearchFieldLook> {
  MotionSelection<GlassFrame>? _scaledBy;
  late MotionSelection<double> _scaleX;
  late MotionSelection<double> _scaleY;

  void _scaleOf(MotionSelection<GlassFrame> frame) {
    if (identical(frame, _scaledBy)) return;
    _scaledBy = frame;
    _scaleX = MotionSelection(() => frame.value.scaleX);
    _scaleY = MotionSelection(() => frame.value.scaleY);
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final look = widget.style;
    final states = details.states;
    final controller = details.controller;
    Color resolve(WidgetStateProperty<Color?>? property) =>
        GlassDynamicColor.resolve(property!.resolve(states)!, context);
    final background = look.backgroundColor?.resolve(states);
    final icon = resolve(look.iconColor);
    final placeholderColor = resolve(look.placeholderColor);
    final text = resolveGlassText(
      look.textStyle!
          .resolve(states)!
          .copyWith(
            color: resolve(look.foregroundColor),
          ),
      context,
    );
    final placeholder = ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.text.isEmpty
          ? ExcludeSemantics(
              child: DefaultTextStyle(
                style: text.copyWith(color: placeholderColor),
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
        end: SearchTuning.clearInset,
      ),
      child: Semantics(
        container: true,
        button: true,
        label: widget.clearSemanticLabel ?? 'Clear text',
        onTap: details.clear,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: details.clear,
          child: SizedBox.square(
            dimension: SearchTuning.clearSize,
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
      padding: const EdgeInsetsDirectional.only(start: SearchTuning.glyphInset),
      child: Row(
        children: [
          SizedBox.fromSize(
            size: SearchTuning.glyphSize,
            child: CustomPaint(painter: SearchMagnifierPainter(icon)),
          ),
          SizedBox(
            width:
                SearchTuning.textInset -
                SearchTuning.glyphInset -
                SearchTuning.glyphSize.width,
          ),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                placeholder,
                details.text(
                  style: text,
                  cursorColor: resolve(look.cursorColor),
                  backgroundCursorColor: placeholderColor,
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, child) => controller.text.isEmpty
                ? const SizedBox(width: SearchTuning.clearInset)
                : child!,
            child: clear,
          ),
        ],
      ),
    );
    final glass = Glass.regular(tint: background);
    if (states.contains(WidgetState.disabled)) {
      return GlassSurface(role: GlassRole.track, glass: glass, child: content);
    }
    if (SearchFieldStacking.maybeOf(context) == null) {
      return GlassSurface.live(
        frame: details.frame,
        glass: glass,
        child: content,
      );
    }
    _scaleOf(details.frame);
    // A surface fades its content with its glass, and a stacked field's
    // glyph and text stay while its glass comes and goes.
    return Stack(
      fit: StackFit.expand,
      children: [
        GlassSurface.live(
          frame: details.frame,
          glass: glass,
          child: const SizedBox.expand(),
        ),
        MotionTransition(scaleX: _scaleX, scaleY: _scaleY, child: content),
      ],
    );
  }
}

/// How a search field stacked under a navigation bar's large title draws:
/// [height] points tall, its glass only as present as [glass], over the
/// plain fill its bar draws under it.
@internal
class SearchFieldStacking extends InheritedWidget {
  /// Stacks the search fields below.
  const SearchFieldStacking({
    required this.height,
    required this.glass,
    required super.child,
    super.key,
  });

  /// The height of the field.
  final double height;

  /// How present the field's glass is, 0 to 1.
  final MotionValue<double> glass;

  /// The stacking around [context], or null.
  static SearchFieldStacking? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchFieldStacking>();

  @override
  bool updateShouldNotify(SearchFieldStacking oldWidget) =>
      height != oldWidget.height || glass != oldWidget.glass;
}

/// The signal a host's close button fires through [end] when a search ends.
@internal
class SearchEndSignal extends ChangeNotifier {
  /// Tells the listeners that a search ended.
  void end() => notifyListeners();
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

/// Follows a touch on the field to lift it, and focuses the field on a
/// tap; it never holds the touch, so the text's own gestures and a scroll
/// still take it.
final class _LiftInput extends Interaction {
  _LiftInput(this._owner) : super(role: InteractionRole.content);

  final _RawGlassSearchFieldState _owner;
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
        _owner._press.down(input);
      case PointerMoveInput() when input.pointer == _pointer:
        _owner._press.move(input);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._press.up(input);
        if ((input.position - _down).distance < kTouchSlop) {
          _owner._focus.requestFocus();
        }
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._press.cancel(input);
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
        SearchTuning.clearInk /
        SearchTuning.clearSize;
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
