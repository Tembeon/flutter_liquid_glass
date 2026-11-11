import 'package:apple_liquid_glass/src/controls/glass_search_field.dart';
import 'package:apple_liquid_glass/src/controls/search_stacking.dart';
import 'package:apple_liquid_glass/src/motion/glass_press.dart';
import 'package:apple_liquid_glass/src/motion/search_motion.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
