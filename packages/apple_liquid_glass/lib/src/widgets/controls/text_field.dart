import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The look of a [GlassTextField], like Flutter's `ButtonStyle`.
///
/// Every property but [errorColor] and [builder] resolves against the
/// field's states (focused, hovered, disabled, error) and falls through,
/// state by state, from this style to the theme's to the field's defaults:
/// a null for a state leaves that state to the next one.
@immutable
class GlassTextFieldStyle extends GlassStyle<GlassTextFieldStyle> {
  /// Creates a style.
  const GlassTextFieldStyle({
    this.backgroundColor,
    this.borderColor,
    this.foregroundColor,
    this.placeholderColor,
    this.cursorColor,
    this.textStyle,
    this.errorColor,
    this.builder,
  });

  /// The theme's [GlassTextFieldStyle] at [context], or null without one:
  /// the look between a widget's own style and its defaults.
  static GlassTextFieldStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassTextFieldStyle>(context);

  /// The fill of the field; [GlassColors.systemBackground] by default and
  /// [GlassTextField.disabledFill] when disabled.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The hairline around the field; [GlassTextField.hairline] by default
  /// and [errorColor] with an error.
  final WidgetStateProperty<Color?>? borderColor;

  /// The color of the text; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The color of the placeholder; [GlassTextField.placeholderColor] by
  /// default.
  final WidgetStateProperty<Color?>? placeholderColor;

  /// The color of the text cursor, and at a fifth of its alpha of the
  /// selection; by default bluer than the accent, as UIKit's.
  final WidgetStateProperty<Color?>? cursorColor;

  /// The text style of the text and the placeholder: 17 points, regular,
  /// by default.
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The color of the error text; [GlassColors.systemRed] by default.
  final Color? errorColor;

  /// Builds the field in place of its default look, which then ignores the
  /// other fields. Null leaves it to the theme's builder, then the default
  /// look.
  final GlassTextFieldBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassTextFieldStyle merge(GlassTextFieldStyle? other) {
    if (other == null) return this;
    return GlassTextFieldStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      borderColor: GlassStyle.mergeStates(borderColor, other.borderColor),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      placeholderColor: GlassStyle.mergeStates(
        placeholderColor,
        other.placeholderColor,
      ),
      cursorColor: GlassStyle.mergeStates(cursorColor, other.cursorColor),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      errorColor: errorColor ?? other.errorColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the half.
  @override
  GlassTextFieldStyle lerp(GlassTextFieldStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassTextFieldStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      borderColor: color(borderColor, other.borderColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      placeholderColor: color(placeholderColor, other.placeholderColor),
      cursorColor: color(cursorColor, other.cursorColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        GlassStyle.lerpNullable(TextStyle.lerp),
      ),
      errorColor: GlassDynamicColor.lerp(errorColor, other.errorColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassTextFieldStyle &&
      other.backgroundColor == backgroundColor &&
      other.borderColor == borderColor &&
      other.foregroundColor == foregroundColor &&
      other.placeholderColor == placeholderColor &&
      other.cursorColor == cursorColor &&
      other.textStyle == textStyle &&
      other.errorColor == errorColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    borderColor,
    foregroundColor,
    placeholderColor,
    cursorColor,
    textStyle,
    errorColor,
    builder,
  );
}

/// An iOS text field: the text on a plain rounded fill with a hairline
/// rim, a placeholder while it is empty, and an error under it.
///
/// UIKit: `UITextField` with the rounded rect border, and `UITextView` for
/// more than one line. Flutter: `CupertinoTextField`.
///
/// ```dart
/// GlassTextField(
///   placeholder: 'Email',
///   keyboardType: TextInputType.emailAddress,
///   textCapitalization: TextCapitalization.none,
///   autofillHints: const [AutofillHints.email],
///   errorText: emailError,
///   onChanged: (email) => setState(() => this.email = email),
/// )
/// ```
///
/// The field is 34 points tall at the default text size and grows with the
/// text size, and with [minLines] and [maxLines] past one line. Its text
/// stands 7 points inside its edges, or 7 points after a [prefix];
/// [prefix] and [suffix] stand flush on the field's edges, centered, and
/// the text runs up to [suffix]: a glyph button there, such as one that
/// shows a password or pastes, brings its own padding. [obscureText] shows
/// the text as dots, as a password field does. With [errorText] the rim
/// turns red and the error stands under the field in red footnote text,
/// where screen readers read it after the field. [labelText] stands above
/// the field in the secondary label color at the body size, and is what
/// screen readers name the field by; [helperText] stands under it in
/// secondary footnote text, the error in its place while there is one
/// (both this package's own, as the error is). Focus from a hardware
/// keyboard rings the field as it rings every control; a mouse over it
/// draws nothing, as over a `UITextField`, and turns to the text cursor.
/// Input, focus and the keyboard are [RawGlassTextField]'s.
///
/// It is not glass: iOS draws its text fields on a plain fill, and so does
/// this one on every renderer.
///
/// Fidelity. The height, insets, radius, fill, rim and placeholder color
/// are measured on the iOS 27.2 simulator (`UITextField`, rounded rect),
/// as are the side views' places; the disabled fill too. The error, a
/// look UIKit does not have, the multiline insets and the focus ring's
/// fit to the field are this package's.
class GlassTextField extends StatelessWidget {
  /// Creates a text field.
  const GlassTextField({
    this.controller,
    this.focusNode,
    this.labelText,
    this.placeholder,
    this.helperText,
    this.errorText,
    this.prefix,
    this.suffix,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.scrollPhysics,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onTapOutside,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.style,
    this.semanticLabel,
    this.statesController,
    super.key,
  }) : assert(
         !obscureText || maxLines == 1,
         'Obscured text shows one line.',
       );

  /// The text, or null for the field's own.
  final TextEditingController? controller;

  /// The field's focus node, or null for its own.
  final FocusNode? focusNode;

  /// What stands above the field, naming it, and what accessibility reads
  /// for it unless [semanticLabel] says otherwise; null for nothing.
  final String? labelText;

  /// What the empty field shows, and what accessibility reads after its
  /// value; null for nothing.
  final String? placeholder;

  /// What stands under the field, saying what it takes, unless
  /// [errorText] stands there; null for nothing.
  final String? helperText;

  /// What is wrong with the text, shown under the field in place of
  /// [helperText]; null for nothing.
  final String? errorText;

  /// What stands at the field's leading edge, or null for nothing.
  final Widget? prefix;

  /// What stands at the field's trailing edge, such as a button that shows
  /// a password, or null for nothing.
  final Widget? suffix;

  /// Whether the text shows as dots, as a password does.
  final bool obscureText;

  /// The most lines the text shows before it scrolls, or null for as many
  /// as it holds.
  final int? maxLines;

  /// The fewest lines the field is tall, or null for one.
  final int? minLines;

  /// The most characters the user can type, or null for any number.
  final int? maxLength;

  /// How the text and the placeholder align in the field.
  final TextAlign textAlign;

  /// How the text scrolls past [maxLines], or null for the platform's.
  final ScrollPhysics? scrollPhysics;

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
  /// `AutofillHints.password`, or null for nothing.
  final Iterable<String>? autofillHints;

  /// What the field passes its text through as the user edits it.
  final List<TextInputFormatter>? inputFormatters;

  /// Called with the text as the user edits it.
  final ValueChanged<String>? onChanged;

  /// Called when the user finishes editing with the keyboard's action
  /// key, before [onSubmitted]; null lets the field submit and give up
  /// the focus.
  final VoidCallback? onEditingComplete;

  /// Called with the text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Called for a pointer down outside the field while it has the focus;
  /// null gives up the focus where the platform does.
  final TapRegionCallback? onTapOutside;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the text shows unchanged by the user: it still takes the
  /// focus and a selection to copy, and the keyboard does not show.
  final bool readOnly;

  /// Whether the field takes focus when it first appears.
  final bool autofocus;

  /// The look, over the theme's and the field's defaults.
  final GlassTextFieldStyle? style;

  /// What accessibility reads for the field, or null for nothing.
  final String? semanticLabel;

  /// The field's states, or null for its own: the field writes focused,
  /// hovered, disabled and error to it.
  final WidgetStatesController? statesController;

  /// The height of a field of one line at the default text size, in points
  /// (UIKit's rounded rect field).
  static const double height = 34;

  /// The space between the field's edges, or a side view, and its text.
  static const double textInset = 7;

  /// The radius of the field's corners.
  static const double radius = 5;

  /// The space between the field and its label, its helper or its error.
  static const double errorGap = 6;

  /// The rim, one pixel wide: black at a fifth in light and white at a
  /// fifth in dark.
  static const hairline = GlassDynamicColor.withBrightness(
    color: Color(0x33000000),
    darkColor: Color(0x33FFFFFF),
  );

  /// The fill of a disabled field: 250 in light and 5 in dark.
  static const disabledFill = GlassDynamicColor.withBrightness(
    color: Color(0xFFFAFAFA),
    darkColor: Color(0xFF050505),
  );

  /// The placeholder: 60, 60, 67 at 0.298 in light (UIKit's
  /// placeholderText), whatever the contrast.
  static const placeholderColor = GlassDynamicColor.withBrightness(
    color: Color(0x4C3C3C43),
    darkColor: Color(0x4CEBEBF5),
  );

  static const _cursor = GlassDynamicColor.withBrightness(
    color: Color(0xFF426BF2),
    darkColor: Color(0xFF406BF8),
  );

  // The selection handles with the default tint: 20, 111, 225 (text
  // field passport), not the caret's color; a tint the app sets colors
  // both.
  static const _handle = Color(0xFF146FE1);

  static const _text = TextStyle(fontSize: 17);

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassTextFieldStyle()).merge(
      GlassTextFieldStyle.maybeOf(context),
    );
    return RawGlassTextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      textAlign: textAlign,
      scrollPhysics: scrollPhysics,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      semanticLabel: semanticLabel ?? labelText,
      semanticHint: placeholder,
      states: {if (errorText != null) WidgetState.error},
      statesController: statesController,
      builder:
          look.builder ??
          (context, details) => _TextFieldLook(
            details: details,
            style: look.merge(_defaults(context, look.errorColor)),
            handleColor: look.cursorColor == null ? _handle : null,
            labelText: labelText,
            placeholder: placeholder,
            helperText: helperText,
            errorText: errorText,
            prefix: prefix,
            suffix: suffix,
          ),
    );
  }

  static GlassTextFieldStyle _defaults(BuildContext context, Color? error) {
    final red = error ?? GlassColors.systemRed;
    return GlassTextFieldStyle(
      backgroundColor: const WidgetStateMapper<Color?>({
        WidgetState.disabled: GlassTextField.disabledFill,
        WidgetState.any: GlassColors.systemBackground,
      }),
      borderColor: WidgetStateMapper<Color?>({
        WidgetState.error: red,
        WidgetState.any: GlassTextField.hairline,
      }),
      foregroundColor: WidgetStatePropertyAll(GlassTheme.labelColorOf(context)),
      placeholderColor: const WidgetStatePropertyAll(
        GlassTextField.placeholderColor,
      ),
      cursorColor: const WidgetStatePropertyAll(GlassTextField._cursor),
      textStyle: const WidgetStatePropertyAll(GlassTextField._text),
      errorColor: red,
    );
  }
}

class _TextFieldLook extends StatelessWidget {
  const _TextFieldLook({
    required this.details,
    required this.style,
    required this.handleColor,
    required this.labelText,
    required this.placeholder,
    required this.helperText,
    required this.errorText,
    required this.prefix,
    required this.suffix,
  });

  final GlassTextFieldDetails details;
  final GlassTextFieldStyle style;
  final Color? handleColor;
  final String? labelText;
  final String? placeholder;
  final String? helperText;
  final String? errorText;
  final Widget? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    final scale = GlassTextScale.of(context);
    final foreground = resolve(
      style.foregroundColor,
      const Color(0xFF000000),
    );
    final text = scale.resolve(
      (style.textStyle?.resolve(states) ?? GlassTextField._text).copyWith(
        color: foreground,
      ),
    );
    final cursor = resolve(style.cursorColor, GlassTextField._cursor);
    final one = details.maxLines == 1;
    final placeholder = this.placeholder;
    final shown = Stack(
      children: [
        if (placeholder != null)
          Positioned.fill(
            child: ExcludeSemantics(
              child: ListenableBuilder(
                listenable: details.controller,
                builder: (context, _) => Visibility(
                  visible: details.controller.text.isEmpty,
                  child: Text(
                    placeholder,
                    style: text.copyWith(
                      color: resolve(
                        style.placeholderColor,
                        GlassTextField.placeholderColor,
                      ),
                    ),
                    textScaler: scale.scaler,
                    textAlign: details.textAlign,
                    maxLines: details.maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        details.text(
          style: text,
          cursorColor: cursor,
          selectionColor: cursor.withValues(alpha: cursor.a * 0.2),
          scale: scale,
          handleColor: handleColor,
        ),
      ],
    );
    final dpr = GlassTraits.of(context).viewPixelRatio;
    final field = DecoratedBox(
      decoration: ShapeDecoration(
        color: resolve(style.backgroundColor, const Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassTextField.radius),
          side: BorderSide(
            color: resolve(style.borderColor, GlassTextField.hairline),
            width: 1 / dpr,
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              GlassTextField.height *
              scale.scaler.scale(GlassTextField._text.fontSize!) /
              GlassTextField._text.fontSize!,
        ),
        child: Row(
          children: [
            ?prefix,
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: GlassTextField.textInset,
                  end: suffix == null ? GlassTextField.textInset : 0,
                  top: one ? 0 : _lineInset,
                  bottom: one ? 0 : _lineInset,
                ),
                child: shown,
              ),
            ),
            ?suffix,
          ],
        ),
      ),
    );
    final ringed = GlassHighlightPaint.of(
      context,
      states: details.statesListenable,
      hoverColor: const Color(0x00000000),
      shape: const LiquidRoundedRectangle(radius: GlassTextField.radius),
      child: field,
    );
    final label = labelText;
    final error = errorText;
    final note = error ?? helperText;
    if (label == null && note == null) return ringed;
    final secondary = GlassDynamicColor.resolve(
      GlassColors.secondaryLabel,
      context,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: GlassTextField.textInset,
              end: GlassTextField.textInset,
              bottom: GlassTextField.errorGap,
            ),
            child: ExcludeSemantics(
              child: GlassDefaultTextStyle(
                role: GlassTextRole.body,
                child: Text(label, style: TextStyle(color: secondary)),
              ),
            ),
          ),
        ringed,
        if (note != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: GlassTextField.textInset,
              end: GlassTextField.textInset,
              top: GlassTextField.errorGap,
            ),
            child: GlassDefaultTextStyle(
              role: GlassTextRole.footnote,
              child: Text(
                note,
                style: TextStyle(
                  color: error == null
                      ? secondary
                      : GlassDynamicColor.resolve(
                          style.errorColor ?? GlassColors.systemRed,
                          context,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // The text's space over and under its lines past one: what a 34 point
  // field leaves around a 22 point line.
  static const double _lineInset = 6;
}
