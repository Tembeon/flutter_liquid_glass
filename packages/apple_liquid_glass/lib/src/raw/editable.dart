import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/foundation.dart';
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
  bool _handles = false;

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

  // As a text field shows them: after a touch that would show the menu,
  // on text or after a long press, never from the keys or a pointer.
  bool _showsHandles(SelectionChangedCause? cause, {required bool readOnly}) {
    if (!_gestures.shouldShowSelectionToolbar ||
        !_gestures.shouldShowSelectionHandles) {
      return false;
    }
    if (!editable || cause == SelectionChangedCause.keyboard) return false;
    if (readOnly && controller.selection.isCollapsed) return false;
    if (cause == SelectionChangedCause.longPress ||
        cause == SelectionChangedCause.stylusHandwriting) {
      return true;
    }
    return controller.text.isNotEmpty;
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
  /// [semanticHint]; its edit menu is [contextMenuBuilder]'s, or the
  /// system's on iOS and none elsewhere when that is null.
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
    Color? handleColor,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  }) {
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.fuchsia => true,
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };
    // The handles and the menu stand in an overlay: a field without one
    // shows neither.
    final overlay = Overlay.maybeOf(context) != null;
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
      contextMenuBuilder: !overlay
          ? null
          : contextMenuBuilder ??
                (SystemContextMenu.isSupported(context)
                    ? (context, state) => SystemContextMenu.editableText(
                        editableTextState: state,
                      )
                    : null),
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      selectionControls: touch && this.editable && overlay
          ? _LollipopControls(handleColor ?? cursorColor)
          : null,
      showSelectionHandles: _handles,
      onSelectionChanged: (selection, cause) {
        final shows = _showsHandles(cause, readOnly: readOnly);
        if (shows != _handles) setState(() => _handles = shows);
      },
      onSelectionHandleTapped: () {
        if (controller.selection.isCollapsed) {
          _editableKey.currentState?.toggleToolbar();
        }
      },
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

/// UIKit's selection handles, `_UITextSelectionLollipopView`s (text field
/// passport, iOS 27.2 simulator): a stem 2 wide and as tall as the line,
/// rounded by 1, with a dot 16.5 across centered on it, above the stem at
/// the start and below it at the end, overlapping it by 3. A caret has
/// none, but its box still takes a drag.
class _LollipopControls extends TextSelectionControls
    with TextSelectionHandleControls {
  _LollipopControls(this.color);

  final Color color;

  static const double _dot = 16.5;
  static const double _stem = 2;
  static const double _overlap = 3;

  @override
  Size getHandleSize(double textLineHeight) =>
      Size(_dot, textLineHeight + _dot - _overlap);

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final size = getHandleSize(textLineHeight);
    return switch (type) {
      TextSelectionHandleType.collapsed => SizedBox.fromSize(size: size),
      TextSelectionHandleType.left ||
      TextSelectionHandleType.right => CustomPaint(
        size: size,
        painter: _Lollipop(
          color: color,
          line: textLineHeight,
          dotFirst: type == TextSelectionHandleType.left,
        ),
      ),
    };
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final size = getHandleSize(textLineHeight);
    return switch (type) {
      TextSelectionHandleType.left => Offset(size.width / 2, size.height),
      TextSelectionHandleType.right => Offset(size.width / 2, textLineHeight),
      TextSelectionHandleType.collapsed => Offset(
        size.width / 2,
        textLineHeight + (size.height - textLineHeight) / 2,
      ),
    };
  }
}

class _Lollipop extends CustomPainter {
  const _Lollipop({
    required this.color,
    required this.line,
    required this.dotFirst,
  });

  final Color color;
  final double line;
  final bool dotFirst;

  @override
  void paint(Canvas canvas, Size size) {
    const dot = _LollipopControls._dot;
    const stem = _LollipopControls._stem;
    final paint = Paint()..color = color;
    final stemTop = dotFirst ? dot - _LollipopControls._overlap : 0.0;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH((dot - stem) / 2, stemTop, stem, line),
          const Radius.circular(stem / 2),
        ),
        paint,
      )
      ..drawCircle(
        Offset(dot / 2, dotFirst ? dot / 2 : size.height - dot / 2),
        dot / 2,
        paint,
      );
  }

  @override
  bool shouldRepaint(_Lollipop oldDelegate) =>
      color != oldDelegate.color ||
      line != oldDelegate.line ||
      dotFirst != oldDelegate.dotFirst;
}
