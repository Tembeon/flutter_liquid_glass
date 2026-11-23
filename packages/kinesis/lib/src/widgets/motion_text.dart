import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// Displays [data] with a live [ValueListenable<TextStyle>] (such as a
/// `MotionValue<TextStyle>` using `TextStyleMotionConverter`) by updating the
/// underlying `RenderParagraph` directly, without rebuilding any widgets per
/// frame.
///
/// Supports smooth animation of `fontSize`, `fontWeight`, `letterSpacing`,
/// `wordSpacing`, `height`, `color`, and OpenType variable-font axes
/// (`FontVariation` such as `wght`, `opsz`, `GRAD`). Under a muted
/// `TickerMode` it stops listening until re-enabled.
class MotionText extends LeafRenderObjectWidget {
  /// Creates an animated text widget driven by [style].
  const MotionText(
    this.data, {
    required this.style,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    this.textScaler,
    this.semanticsLabel,
    super.key,
  });

  /// The text string to display.
  final String data;

  /// The live text style listenable; merged over the ambient
  /// [DefaultTextStyle].
  final ValueListenable<TextStyle> style;

  /// How the text should be aligned horizontally.
  final TextAlign textAlign;

  /// The directionality of the text; defaults to [Directionality.of].
  final TextDirection? textDirection;

  /// Whether the text should break at soft line breaks.
  final bool softWrap;

  /// How visual overflow should be handled.
  final TextOverflow overflow;

  /// Optional maximum number of lines for the text to span.
  final int? maxLines;

  /// Optional text scaling strategy; defaults to [MediaQuery.textScalerOf].
  final TextScaler? textScaler;

  /// Optional alternative semantics label for screen readers.
  final String? semanticsLabel;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final ambient = _ambient(context);
    return _RenderMotionText(
      data: data,
      styleListenable: style,
      defaultStyle: ambient.style,
      textAlign: textAlign,
      textDirection: ambient.direction,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      textScaler: ambient.scaler,
      semanticsLabel: semanticsLabel,
      following: ambient.following,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final ambient = _ambient(context);
    (renderObject as _RenderMotionText)
      ..textAlign = textAlign
      ..textDirection = ambient.direction
      ..softWrap = softWrap
      ..overflow = overflow
      ..maxLines = maxLines
      ..textScaler = ambient.scaler
      ..update(
        data: data,
        styleListenable: style,
        defaultStyle: ambient.style,
        semanticsLabel: semanticsLabel,
        following: ambient.following,
      );
  }

  _Ambient _ambient(BuildContext context) => (
    style: DefaultTextStyle.of(context).style,
    direction: textDirection ?? Directionality.of(context),
    scaler: textScaler ?? MediaQuery.textScalerOf(context),
    following: TickerMode.valuesOf(context).enabled,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('data', data))
      ..add(DiagnosticsProperty<ValueListenable<TextStyle>>('style', style))
      ..add(EnumProperty<TextAlign>('textAlign', textAlign))
      ..add(EnumProperty<TextDirection>('textDirection', textDirection))
      ..add(FlagProperty('softWrap', value: softWrap, ifFalse: 'no wrapping'))
      ..add(EnumProperty<TextOverflow>('overflow', overflow))
      ..add(IntProperty('maxLines', maxLines, defaultValue: null));
  }
}

typedef _Ambient = ({
  TextStyle style,
  TextDirection direction,
  TextScaler scaler,
  bool following,
});

final class _RenderMotionText extends RenderParagraph {
  _RenderMotionText({
    required String data,
    required ValueListenable<TextStyle> styleListenable,
    required TextStyle defaultStyle,
    required super.textAlign,
    required super.textDirection,
    required super.softWrap,
    required super.overflow,
    required super.maxLines,
    required super.textScaler,
    required String? semanticsLabel,
    required this._following,
  }) : _data = data,
       _styleListenable = styleListenable,
       _defaultStyle = defaultStyle,
       _semanticsLabel = semanticsLabel,
       super(
         TextSpan(
           text: data,
           style: defaultStyle.merge(styleListenable.value),
           semanticsLabel: semanticsLabel,
         ),
       );

  String _data;
  ValueListenable<TextStyle> _styleListenable;
  TextStyle _defaultStyle;
  String? _semanticsLabel;
  bool _following;
  bool _listening = false;

  void update({
    required String data,
    required ValueListenable<TextStyle> styleListenable,
    required TextStyle defaultStyle,
    required String? semanticsLabel,
    required bool following,
  }) {
    var spanChanged = false;
    if (data != _data) {
      _data = data;
      spanChanged = true;
    }
    if (defaultStyle != _defaultStyle) {
      _defaultStyle = defaultStyle;
      spanChanged = true;
    }
    if (semanticsLabel != _semanticsLabel) {
      _semanticsLabel = semanticsLabel;
      spanChanged = true;
    }
    final listenableChanged = !identical(styleListenable, _styleListenable);
    final followingChanged = following != _following;
    if (listenableChanged || followingChanged) {
      _unfollow();
      _styleListenable = styleListenable;
      _following = following;
      _follow();
      if (listenableChanged || following) {
        spanChanged = true;
      }
    }
    if (spanChanged) _syncSpan();
  }

  void _syncSpan() {
    text = TextSpan(
      text: _data,
      style: _defaultStyle.merge(_styleListenable.value),
      semanticsLabel: _semanticsLabel,
    );
  }

  void _follow() {
    if (!attached || !_following || _listening) return;
    _listening = true;
    _styleListenable.addRenderListener(_syncSpan);
  }

  void _unfollow() {
    if (!_listening) return;
    _listening = false;
    _styleListenable.removeRenderListener(_syncSpan);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow();
  }

  @override
  void detach() {
    _unfollow();
    super.detach();
  }
}
