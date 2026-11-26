import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The editable text of a field, shared by its states: the controller and
/// focus node the widget gives or the state's own, the text's selection
/// gestures, and the [EditableText] with its semantics and system edit
/// menu.
mixin GlassEditable<T extends StatefulWidget> on State<T>
    implements TextSelectionGestureDetectorBuilderDelegate {
  /// The text the widget gives, or null for the state's own.
  TextEditingController? get givenController;

  /// The focus node the widget gives, or null for the state's own.
  FocusNode? get givenFocusNode;

  /// Whether the field takes input.
  bool get editable;

  /// Called when the field gains or loses the focus.
  void focusChanged();

  final _editableKey = GlobalKey<EditableTextState>();
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  FocusNode? _listened;

  /// The field's text.
  TextEditingController get controller =>
      givenController ?? (_ownController ??= TextEditingController());

  /// The field's focus node.
  FocusNode get focusNode =>
      givenFocusNode ?? (_ownFocus ??= FocusNode(debugLabel: '$T'));

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editableKey;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => editable && focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    if (!editable && focusNode.hasFocus) focusNode.unfocus();
  }

  void _listen() {
    final focus = focusNode;
    if (identical(focus, _listened)) return;
    _listened?.removeListener(focusChanged);
    _listened = focus..addListener(focusChanged);
  }

  @override
  void dispose() {
    _listened?.removeListener(focusChanged);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  /// The editable text in [style], with its selection gestures while the
  /// field takes input, read by accessibility as [semanticLabel] with
  /// [semanticHint]; on iOS a long press shows the system edit menu, and
  /// other platforms show none.
  Widget editableText({
    required TextStyle style,
    required GlassTextScale textScale,
    required Color cursorColor,
    required Color backgroundCursorColor,
    required Color selectionColor,
    required String? semanticLabel,
    String? semanticHint,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
    bool enableSuggestions = true,
    bool obscureText = false,
    int? maxLines = 1,
    int? minLines,
    bool autofocus = false,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    VoidCallback? onEditingComplete,
    ValueChanged<String>? onSubmitted,
    TapRegionCallback? onTapOutside,
    bool readOnly = false,
    TextAlign textAlign = TextAlign.start,
    ScrollPhysics? scrollPhysics,
  }) {
    final editable = EditableText(
      key: _editableKey,
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly || !this.editable,
      textAlign: textAlign,
      scrollPhysics: scrollPhysics,
      autofocus: autofocus,
      style: style,
      textScaler: textScale.scaler,
      cursorColor: cursorColor,
      backgroundCursorColor: backgroundCursorColor,
      selectionColor: selectionColor,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      keyboardAppearance: GlassTraits.of(context).brightness,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      rendererIgnoresPointer: true,
      contextMenuBuilder: SystemContextMenu.isSupported(context)
          ? (context, state) =>
                SystemContextMenu.editableText(editableTextState: state)
          : null,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
    );
    return Semantics(
      label: semanticLabel,
      hint: semanticHint,
      child: this.editable
          ? _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: editable,
            )
          : IgnorePointer(child: ExcludeFocus(child: editable)),
    );
  }
}
