import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/src/menu/appearance.dart';
import 'package:apple_liquid_glass/src/menu/content.dart';
import 'package:apple_liquid_glass/src/menu/entries.dart';
import 'package:apple_liquid_glass/src/menu/layout.dart';
import 'package:apple_liquid_glass/src/menu/motion.dart';
import 'package:apple_liquid_glass/src/motion/live.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class _RowKey extends LocalKey {
  const _RowKey(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is _RowKey && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// The elements of one card, each at its frame in the card's content.
///
/// The element widgets are made once per layout and style, so building
/// the rows again with the same layout rebuilds none of them.
@internal
class MenuRows extends StatefulWidget {
  /// Creates the rows of [layout]; the submenu row [hidden] names is drawn
  /// by its card instead.
  const MenuRows({
    required this.layout,
    required this.style,
    required this.hidden,
    required this.content,
    required this.onSelect,
    super.key,
  });

  /// The card's layout.
  final MenuLayout layout;

  /// The target of the submenu row a card grows out of, or null.
  final ValueListenable<int?> hidden;

  /// The colors.
  final MenuAppearance style;

  /// The menu's entries and their state.
  final MenuContent content;

  /// Called with the target of a row a screen reader activates.
  final ValueChanged<int> onSelect;

  @override
  State<MenuRows> createState() => _MenuRowsState();
}

class _MenuRowsState extends State<MenuRows> {
  final ValueNotifier<int?> _hidden = ValueNotifier<int?>(null);
  List<Widget>? _children;

  @override
  void initState() {
    super.initState();
    widget.hidden.addListener(_hiddenChanged);
    _hidden.value = widget.hidden.value;
  }

  @override
  void didUpdateWidget(MenuRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden.removeListener(_hiddenChanged);
      widget.hidden.addListener(_hiddenChanged);
      _hidden.value = widget.hidden.value;
    }
    if (!identical(oldWidget.layout, widget.layout) ||
        !identical(oldWidget.style, widget.style) ||
        !identical(oldWidget.content, widget.content)) {
      _children = null;
    }
  }

  @override
  void dispose() {
    widget.hidden.removeListener(_hiddenChanged);
    _hidden.dispose();
    super.dispose();
  }

  void _hiddenChanged() => _hidden.value = widget.hidden.value;

  void _select(int target) => widget.onSelect(target);

  List<Widget> _build() {
    final layout = widget.layout;
    final children = <Widget>[];
    for (var i = 0; i < layout.elements.length; i++) {
      final element = layout.elements[i];
      if (element.kind == MenuPlacedKind.cardHeader) continue;
      children.add(
        element.entry is GlassSubmenu && element.kind == MenuPlacedKind.row
            ? ValueListenableBuilder<int?>(
                key: _RowKey(i),
                valueListenable: _hidden,
                builder: (BuildContext context, int? hidden, Widget? _) =>
                    _MenuElement(
                      element: element,
                      style: widget.style,
                      width: layout.width,
                      content: widget.content,
                      onSelect: _select,
                      hidden: hidden == element.target,
                    ),
              )
            : _MenuElement(
                key: _RowKey(i),
                element: element,
                style: widget.style,
                width: layout.width,
                content: widget.content,
                onSelect: _select,
              ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final all = _children ??= _build();
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        clipBehavior: .none,
        children: all,
      ),
    );
  }
}

class _MenuElement extends StatelessWidget {
  const _MenuElement({
    required this.element,
    required this.style,
    required this.width,
    required this.content,
    required this.onSelect,
    this.hidden = false,
    super.key,
  });

  final bool hidden;

  final MenuPlaced element;
  final MenuAppearance style;
  final double width;
  final MenuContent content;
  final ValueChanged<int> onSelect;

  Color get _title => style.textStyle.color ?? style.iconColor;

  VoidCallback? get _tap {
    final target = element.target;
    return target < 0 ? null : () => onSelect(target);
  }

  Widget _at(double center, double extent, Widget child) =>
      PositionedDirectional(
        start: center - extent / 2,
        width: extent,
        top: 0,
        bottom: 0,
        child: Center(child: child),
      );

  Widget _text(
    BuildContext context,
    String text,
    TextStyle base,
    Color color, {
    int maxLines = 1,
    TextAlign? align,
  }) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: resolveGlassText(base, context).copyWith(color: color),
  );

  @override
  Widget build(BuildContext context) {
    final element = this.element;
    final rect = element.rect;
    return Positioned.fromRect(
      rect: rect,
      child: switch (element.kind) {
        MenuPlacedKind.row when hidden => Opacity(
          opacity: 0,
          child: _row(context),
        ),
        MenuPlacedKind.row => _row(context),
        MenuPlacedKind.header => _header(context),
        MenuPlacedKind.separator => ColoredBox(
          color: style.separatorColor,
        ),
        MenuPlacedKind.palette ||
        MenuPlacedKind.small ||
        MenuPlacedKind.medium => _cell(context),
        MenuPlacedKind.loading => _loading(context),
        MenuPlacedKind.widget => _widget(),
        MenuPlacedKind.cardHeader => const SizedBox.shrink(),
      },
    );
  }

  Widget _row(BuildContext context) {
    final entry = element.entry;
    final String title;
    final String? subtitle;
    final Widget? icon;
    final bool enabled;
    final bool destructive;
    var state = GlassMenuItemState.off;
    var submenu = false;
    Color? iconColor;
    switch (entry) {
      case GlassMenuItem():
        title = entry.title;
        subtitle = entry.subtitle;
        state = entry.state;
        icon = entry.iconVisibility == GlassMenuIconVisibility.hidden
            ? null
            : state != GlassMenuItemState.off && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case GlassSubmenu():
        title = entry.title;
        subtitle = entry.subtitle;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        submenu = true;
      default:
        return const SizedBox.shrink();
    }
    final color = !enabled
        ? style.disabledColor
        : destructive
        ? style.destructiveColor
        : _title;
    final check = element.checkCenter;
    final image = element.imageCenter;
    return Semantics(
      button: true,
      role: ui.SemanticsRole.menuItem,
      enabled: enabled,
      checked: state == GlassMenuItemState.off || submenu
          ? null
          : state == GlassMenuItemState.on,
      mixed: state == GlassMenuItemState.mixed ? true : null,
      expanded: submenu ? false : null,
      label: title,
      value: subtitle,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: Stack(
        children: [
          if (check != null && state != GlassMenuItemState.off)
            _at(
              check,
              MenuTuning.markSlot,
              CustomPaint(
                size: state == GlassMenuItemState.on
                    ? MenuTuning.checkSize
                    : MenuTuning.mixedSize,
                painter: _MarkPainter(
                  color: color,
                  mixed: state == GlassMenuItemState.mixed,
                ),
              ),
            ),
          if (image != null && icon != null)
            _at(
              image,
              MenuTuning.imageSlot,
              IconTheme.merge(
                data: IconThemeData(
                  size: style.iconSize,
                  color: iconColor ?? color,
                ),
                child: icon,
              ),
            ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                _text(
                  context,
                  title,
                  style.textStyle,
                  color,
                  maxLines: element.maxLines,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: MenuTuning.subtitleGap),
                  _text(
                    context,
                    subtitle,
                    _subtitleStyle,
                    style.secondaryColor,
                  ),
                ],
              ],
            ),
          ),
          if (submenu)
            _at(
              _metrics.chevronCenter,
              MenuTuning.markSlot,
              Transform.flip(
                flipX: content.rtl,
                child: CustomPaint(
                  size: MenuTuning.chevronSize,
                  painter: _ChevronPainter(color: color, down: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  MenuMetrics get _metrics => content.metrics;

  static const _subtitleStyle = TextStyle(fontSize: 13);

  Widget _header(BuildContext context) {
    return Semantics(
      header: true,
      label: element.title,
      excludeSemantics: true,
      child: Stack(
        children: [
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: _metrics.headerLabelTop,
            child: _text(
              context,
              element.title ?? '',
              _subtitleStyle,
              style.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context) {
    final entry = element.entry;
    final String title;
    final Widget? icon;
    final bool enabled;
    final bool destructive;
    var selected = false;
    Color? iconColor;
    switch (entry) {
      case GlassMenuItem():
        title = entry.title;
        selected = entry.state != GlassMenuItemState.off;
        icon = selected && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case GlassSubmenu():
        title = entry.title;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
      default:
        return const SizedBox.shrink();
    }
    final color = !enabled
        ? style.disabledColor
        : destructive
        ? style.destructiveColor
        : _title;
    final kind = element.kind;
    final metrics = _metrics;
    final Widget body;
    if (kind == MenuPlacedKind.medium) {
      body = Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: metrics.mediumLabelTop,
            child: Center(
              child: icon == null
                  ? null
                  : IconTheme.merge(
                      data: IconThemeData(
                        size: style.iconSize,
                        color: iconColor ?? color,
                      ),
                      child: icon,
                    ),
            ),
          ),
          Positioned(
            left: 2,
            right: 2,
            top: metrics.mediumLabelTop,
            child: _text(
              context,
              title,
              const TextStyle(fontSize: 12),
              color,
              align: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      final palette = kind == MenuPlacedKind.palette;
      body = Stack(
        alignment: Alignment.center,
        children: [
          if (palette && selected)
            SizedBox.square(
              dimension: metrics.palettePlatter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: style.paletteSelectionColor,
                  borderRadius: .circular(metrics.palettePlatterRadius),
                ),
              ),
            ),
          if (icon != null)
            IconTheme.merge(
              data: IconThemeData(
                size: palette ? metrics.paletteImageSize : style.iconSize,
                color: iconColor ?? color,
              ),
              child: icon,
            ),
        ],
      );
    }
    return Semantics(
      button: true,
      role: ui.SemanticsRole.menuItem,
      enabled: enabled,
      selected: selected,
      label: title,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: body,
    );
  }

  Widget _loading(BuildContext context) {
    final check = element.imageCenter ?? _metrics.imageCenter;
    return Semantics(
      label: element.title,
      liveRegion: true,
      excludeSemantics: true,
      child: Stack(
        children: [
          _at(
            check,
            MenuTuning.imageSlot,
            _Spinner(color: style.disabledColor),
          ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _text(
                context,
                element.title ?? '',
                style.textStyle,
                style.disabledColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _widget() {
    final entry = element.entry;
    if (entry is! GlassMenuWidget) return const SizedBox.shrink();
    final key = element.key;
    final Widget child = Builder(builder: entry.builder);
    return OverflowBox(
      alignment: .topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Padding(
        padding: .symmetric(horizontal: _metrics.widgetInset),
        child: entry.height != null || key == null
            ? child
            : _HeightReporter(
                onHeight: (double height) => content.reportHeight(key, height),
                child: child,
              ),
      ),
    );
  }
}

/// Reports the height [child] lays out at, after the frame.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (attached) onHeight(height);
    });
  }
}

/// The checkmark or the dash of a row's selection mark.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.color, required this.mixed});

  final Color color;
  final bool mixed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    if (mixed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        paint,
      );
      return;
    }
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.1;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    path.moveTo(size.width * 0.06, size.height * 0.55);
    path.lineTo(size.width * 0.36, size.height * 0.92);
    path.lineTo(size.width * 0.94, size.height * 0.08);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mixed != mixed;
}

/// A chevron pointing forward (mirrored in right-to-left text) or down.
/// The shadow a submenu card casts around itself, kept off its face: the
/// card is translucent.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.down});

  final Color color;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    final w = size.width;
    final h = size.height;
    if (down) {
      path.moveTo(w * 0.08, h * 0.12);
      path.lineTo(w * 0.5, h * 0.88);
      path.lineTo(w * 0.92, h * 0.12);
    } else {
      path.moveTo(w * 0.12, h * 0.08);
      path.lineTo(w * 0.88, h * 0.5);
      path.lineTo(w * 0.12, h * 0.92);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.down != down;
}

/// A row's activity indicator: eight spokes whose brightest one steps
/// round once a second, as UIKit's medium indicator does.
class _Spinner extends StatefulWidget {
  const _Spinner({required this.color});

  final Color color;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(20),
    painter: _SpinnerPainter(turn: _turn, color: widget.color),
  );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.turn, required this.color})
    : super(repaint: turn);

  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spokes = 8;
    final head = (turn.value * spokes).floor();
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint();
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    for (var i = 0; i < spokes; i++) {
      final age = (head - i) % spokes;
      paint.color = color.withValues(alpha: color.a * (1 - age / spokes));
      final angle = 2 * math.pi * i / spokes - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * radius * 0.45,
        center + direction * radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => oldDelegate.color != color;
}

/// How bold a card header's title is, how far its chevron has turned and
/// the opacity of its separator, each from 0 to 1.
@internal
typedef MenuHeaderValues = ({double bold, double turn, double separator});

/// The header of a submenu card: the row it grew out of, its title
/// turning bold and its chevron turning down as the card opens, each read
/// again on every notification of [live].
@internal
class MenuCardHeader extends StatelessWidget {
  /// Creates the header [header] of a card.
  const MenuCardHeader({
    required this.live,
    required this.header,
    required this.placed,
    required this.values,
    required this.style,
    required this.width,
    required this.content,
    required this.onSelect,
    super.key,
  });

  /// What tells the header to read [placed] and [values] again.
  final Listenable live;

  /// The header as the card's layout places it.
  final MenuPlaced header;

  /// The header now: its columns move from the row's to its own.
  final MenuPlaced Function() placed;

  /// The header's moving values now.
  final MenuHeaderValues Function() values;

  /// The colors.
  final MenuAppearance style;

  /// The card's width.
  final double width;

  /// The menu's entries and their state.
  final MenuContent content;

  /// Called with the header's target when a screen reader activates it.
  final ValueChanged<int> onSelect;

  Color get _title => style.textStyle.color ?? style.iconColor;

  static const _bold = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  Widget _text(BuildContext context, TextStyle base) => Text(
    header.title ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: resolveGlassText(base, context).copyWith(color: _title),
  );

  // A span along the header from its leading edge, in the header's box.
  Rect _span(double start, double extent, double height, bool rtl) =>
      Rect.fromLTWH(rtl ? width - start - extent : start, 0, extent, height);

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final entry = header.entry;
    final icon = entry is GlassSubmenu ? entry.icon : null;
    final target = header.target;
    final rtl = content.rtl;
    final metrics = content.metrics;
    final height = header.rect.height;
    return Positioned.fromRect(
      rect: header.rect,
      child: Semantics(
        button: true,
        role: ui.SemanticsRole.menuItem,
        expanded: true,
        label: header.title,
        onTap: target < 0 ? null : () => onSelect(target),
        excludeSemantics: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (header.imageCenter != null && icon != null)
              LivePlacement(
                live: live,
                rectOf: () => _span(
                  placed().imageCenter! - MenuTuning.imageSlot / 2,
                  MenuTuning.imageSlot,
                  height,
                  rtl,
                ),
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(size: style.iconSize, color: _title),
                    child: icon,
                  ),
                ),
              ),
            LivePlacement(
              live: live,
              rectOf: () {
                final now = placed();
                return _span(
                  now.titleStart,
                  now.titleEnd - now.titleStart,
                  height,
                  rtl,
                );
              },
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  LiveFade(
                    live: live,
                    opacityOf: () => 1 - values().bold,
                    child: _text(context, style.textStyle),
                  ),
                  LiveFade(
                    live: live,
                    opacityOf: () => values().bold,
                    child: _text(context, style.textStyle.merge(_bold)),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              start: metrics.chevronCenter - MenuTuning.markSlot / 2,
              width: MenuTuning.markSlot,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.flip(
                  flipX: rtl,
                  child: LiveTransform(
                    live: live,
                    matrixOf: () =>
                        Matrix4.rotationZ(values().turn * math.pi / 2),
                    child: CustomPaint(
                      size: MenuTuning.chevronSize,
                      painter: _ChevronPainter(color: _title, down: false),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: metrics.separatorInset,
              right: metrics.separatorInset,
              bottom: 0,
              height: 1,
              child: LiveFade(
                live: live,
                opacityOf: () => values().separator,
                child: ColoredBox(color: style.separatorColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
