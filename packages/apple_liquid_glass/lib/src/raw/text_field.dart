import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/raw/editable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/widgets.dart';

/// Builds a text field from [details]; it runs when the field builds, such
/// as when its states change.
typedef GlassTextFieldBuilder = Widget Function(
  BuildContext context,
  GlassTextFieldDetails details,
);

/// What a [GlassTextFieldBuilder] builds a text field from.
final class GlassTextFieldDetails {
  const GlassTextFieldDetails._(
    this._text, {
    required this.states,
    required this.statesListenable,
    required this.controller,
    required this.maxLines,
  });

  /// The states the field is in: focused, hovered, disabled, and those the
  /// field says of itself, such as error.
  final Set<WidgetState> states;

  /// The field's states as they change.
  final ValueListenable<Set<WidgetState>> statesListenable;

  /// The field's text; a look listens to it to show a placeholder.
  final TextEditingController controller;

  /// The most lines the text shows, or null for as many as it holds.
  final int? maxLines;

  final Widget Function(
    TextStyle style,
    Color cursor,
    Color selection,
    GlassTextScale scale,
  )
  _text;

  /// The editable text with its gestures and semantics, drawn in [style]
  /// at [scale] with a [cursorColor] cursor and [selectionColor] behind the
  /// selected text.
  Widget text({
    required TextStyle style,
    required Color cursorColor,
    required Color selectionColor,
    required GlassTextScale scale,
  }) => _text(style, cursorColor, selectionColor, scale);
}

/// A text field with no look of its own: [builder] decides how it looks
/// and places the editable text it gets from [GlassTextFieldDetails.text].
///
/// UIKit: `UITextField`, and `UITextView` for more than one line. Flutter:
/// `EditableText` with a `TextField`'s gestures.
///
/// A tap anywhere on the field focuses it; on the text it also places the
/// caret. The field is one Tab stop, shows the text cursor to a mouse, and
/// says focused while its text has the focus. The keyboard capitalizes
/// sentences by default, as UIKit's does. On iOS a long press shows the
/// system edit menu; other platforms show none.
class RawGlassTextField extends StatefulWidget {
  /// Creates a text field.
  const RawGlassTextField({
    required this.builder,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofillHints,
    this.inputFormatters,
    this.semanticLabel,
    this.semanticHint,
    this.states = const {},
    this.statesController,
    super.key,
  }) : assert(
         !obscureText || maxLines == 1,
         'Obscured text shows one line.',
       ),
       assert(maxLines == null || maxLines > 0, 'A field shows a line.'),
       assert(
         minLines == null || maxLines == null || minLines <= maxLines,
         'minLines is at most maxLines.',
       );

  /// Builds the field's look.
  final GlassTextFieldBuilder builder;

  /// The text, or null for the field's own.
  final TextEditingController? controller;

  /// The field's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Called with the text as the user edits it.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when it first appears.
  final bool autofocus;

  /// Whether the text shows as dots, as a password does.
  final bool obscureText;

  /// The most lines the text shows before it scrolls, or null for as many
  /// as it holds.
  final int? maxLines;

  /// The fewest lines the field is tall, or null for one.
  final int? minLines;

  /// The keyboard, or null for text on one line and multiline text on more.
  final TextInputType? keyboardType;

  /// The keyboard's action key, or null for the platform's default.
  final TextInputAction? textInputAction;

  /// How the keyboard capitalizes what the user types.
  final TextCapitalization textCapitalization;

  /// Whether the keyboard corrects what the user types.
  final bool autocorrect;

  /// Whether the keyboard suggests words.
  final bool enableSuggestions;

  /// What the platform's autofill may fill the field with, such as
  /// `AutofillHints.email`, or null for nothing.
  final Iterable<String>? autofillHints;

  /// What the field passes its text through as the user edits it.
  final List<TextInputFormatter>? inputFormatters;

  /// What accessibility reads for the field, or null for nothing.
  final String? semanticLabel;

  /// What accessibility reads after the field's value, such as its
  /// placeholder, or null for nothing.
  final String? semanticHint;

  /// What the field says of itself, such as error: never disabled, which
  /// is [enabled], nor a state its input keeps.
  final Set<WidgetState> states;

  /// Where the field publishes its states, or null for its own. The field
  /// is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  @override
  State<RawGlassTextField> createState() => _RawGlassTextFieldState();
}

class _RawGlassTextFieldState extends State<RawGlassTextField>
    with ControlStates<RawGlassTextField>, GlassEditable<RawGlassTextField> {
  final _regionFocus = FocusNode(skipTraversal: true);
  late final _tap = _FocusOnTap(this);
  late final List<Interaction> _interactions = [_tap];

  @override
  TextEditingController? get givenController => widget.controller;

  @override
  FocusNode? get givenFocusNode => widget.focusNode;

  @override
  bool get editable => widget.enabled;

  @override
  WidgetStatesController? get statesController => widget.statesController;

  @override
  void focusChanged() => setState(() {});

  @override
  void dispose() {
    _regionFocus.dispose();
    super.dispose();
  }

  Widget _text(
    TextStyle style,
    Color cursor,
    Color selection,
    GlassTextScale scale,
  ) {
    final multiline = widget.maxLines != 1;
    return editableText(
      style: style,
      textScale: scale,
      cursorColor: cursor,
      backgroundCursorColor: cursor,
      selectionColor: selection,
      semanticLabel: widget.semanticLabel,
      semanticHint: widget.semanticHint,
      keyboardType:
          widget.keyboardType ??
          (multiline ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      autofocus: widget.autofocus,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _interactions,
    enabled: widget.enabled,
    states: widget.states,
    isFocused: focusNode.hasFocus,
    statesController: widgetStates,
    focusNode: _regionFocus,
    mouseCursor: widget.enabled
        ? SystemMouseCursors.text
        : SystemMouseCursors.basic,
    child: withStates(
      (context, states) => widget.builder(
        context,
        GlassTextFieldDetails._(
          _text,
          states: states,
          statesListenable: widgetStates,
          controller: controller,
          maxLines: widget.maxLines,
        ),
      ),
    ),
  );
}

/// Focuses the field on a tap; it never holds the touch, so the text's own
/// gestures and a scroll still take it.
final class _FocusOnTap extends Interaction {
  _FocusOnTap(this._owner) : super(role: InteractionRole.content);

  final _RawGlassTextFieldState _owner;
  late final _tap = TapInteraction(
    onTap: (t) => _owner.focusNode.requestFocus(),
  );

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && !_owner.focusNode.hasFocus;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when !accepts(input):
        break;
      default:
        _tap.handle(input);
    }
    return InteractionUpdate.none;
  }
}
