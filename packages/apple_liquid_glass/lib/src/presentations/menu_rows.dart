import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/presentations/menu_content.dart';
import 'package:apple_liquid_glass/src/presentations/menu_entries.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

class _RowKey extends LocalKey {
  const _RowKey(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is _RowKey && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// A chain of render-object widgets that follows the frames of a menu's
/// motion: [template] makes the chain again from each frame, which updates
/// the render objects and builds nothing.
@internal
MotionDriven menuDriven<T>(
  ValueListenable<T> frames,
  SingleChildRenderObjectWidget Function(T frame) template, {
  Widget? child,
  Key? key,
}) => MotionDriven(
  key: key,
  template: () => template(frames.value),
  child: child,
);

/// Lays its child out at [rect]'s size and draws it at [rect]'s corner,
/// taking all the room it is given: a move repaints, a resize lays out.
/// [inner] continues the chain inside it.
@internal
SingleChildRenderObjectWidget menuPlacement(
  Rect rect, [
  SingleChildRenderObjectWidget? inner,
]) => OverflowBox(
  alignment: Alignment.topLeft,
  minWidth: rect.width,
  maxWidth: rect.width,
  minHeight: rect.height,
  maxHeight: rect.height,
  child: Transform.translate(offset: rect.topLeft, child: inner),
);

/// A clip to [rrect] in the clipped box's coordinates; touches outside it
/// pass through.
@internal
class MenuClip extends CustomClipper<RRect> {
  /// Creates a clip to [rrect].
  const MenuClip(this.rrect);

  /// The clip.
  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(MenuClip oldClipper) => oldClipper.rrect != rrect;
}

/// The elements of one card, each at its frame in the card's content.
///
/// The element widgets are made once per layout, style and content, so
/// building the rows again with the same three rebuilds none of them.
@internal
class MenuRows extends StatefulWidget {
  /// Creates the rows of [layout]; the submenu row [hidden] names is drawn
  /// by its card instead.
  const MenuRows({
    required this.layout,
    required this.style,
    required this.hidden,
    required this.content,
    super.key,
  });

  /// The card's layout.
  final MenuLayout layout;

  /// The target of the submenu row a card grows out of, or null.
  final int? hidden;

  /// The colors.
  final MenuAppearance style;

  /// The menu's entries and their state.
  final MenuContent content;

  @override
  State<MenuRows> createState() => _MenuRowsState();
}

class _MenuRowsState extends State<MenuRows> {
  List<Widget>? _children;

  @override
  void didUpdateWidget(MenuRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.layout, widget.layout) ||
        !identical(oldWidget.style, widget.style) ||
        !identical(oldWidget.content, widget.content)) {
      _children = null;
    } else if (oldWidget.hidden != widget.hidden) {
      _rehide(oldWidget.hidden, widget.hidden);
    }
  }

  // Only the rows that hide or show again are made anew; the others keep
  // their widgets, so they do not build.
  void _rehide(int? from, int? to) {
    final children = _children;
    if (children == null) return;
    final elements = widget.layout.elements;
    var slot = 0;
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element.kind == MenuPlacedKind.cardHeader) continue;
      if (element.target >= 0 &&
          (element.target == from || element.target == to)) {
        children[slot] = _element(i);
      }
      slot++;
    }
    _children = List.of(children);
  }

  Widget _element(int i) {
    final layout = widget.layout;
    final element = layout.elements[i];
    return _MenuElement(
      key: _RowKey(i),
      element: element,
      style: widget.style,
      width: layout.width,
      content: widget.content,
      hidden:
          element.kind == MenuPlacedKind.row &&
          element.entry is GlassSubmenu &&
          widget.hidden == element.target,
    );
  }

  List<Widget> _build() => [
    for (var i = 0; i < widget.layout.elements.length; i++)
      if (widget.layout.elements[i].kind != MenuPlacedKind.cardHeader)
        _element(i),
  ];

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
    this.hidden = false,
    super.key,
  });

  final bool hidden;

  final MenuPlaced element;
  final MenuAppearance style;
  final double width;
  final MenuContent content;

  Color get _title => style.textStyle.color!;

  // A row that is a target is described by its zone in the menu's layer;
  // one that is not (a disabled row) describes itself.
  Widget _described(Widget child, {required Widget Function(Widget) own}) =>
      element.target >= 0 ? ExcludeSemantics(child: child) : own(child);

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
    return _described(
      own: (child) => Semantics(
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
        excludeSemantics: true,
        child: child,
      ),
      Stack(
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
                  painter: _ChevronPainter(color: color),
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
    return _described(
      own: (child) => Semantics(
        button: true,
        role: ui.SemanticsRole.menuItem,
        enabled: enabled,
        selected: selected,
        label: title,
        excludeSemantics: true,
        child: child,
      ),
      body,
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
            : MotionMeasure(
                onSize: (_, size) => content.reportHeight(key, size.height),
                child: child,
              ),
      ),
    );
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

/// A chevron pointing at the trailing edge; callers flip it for
/// right-to-left.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.12, h * 0.08);
    path.lineTo(w * 0.88, h * 0.5);
    path.lineTo(w * 0.12, h * 0.92);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

/// A row's activity indicator: eight spokes whose brightest one steps
/// round once a second, as UIKit's medium indicator does.
class _Spinner extends StatefulWidget {
  const _Spinner({required this.color});

  final Color color;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> {
  final _spin = _Spin();
  late final _head = _spin.select((spin) => spin.head);

  @override
  void initState() {
    super.initState();
    _spin.start(_spin.clock.now);
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(20),
    painter: _SpinnerPainter(head: _head, color: widget.color),
  );
}

/// The spokes of an activity indicator, stepping round from [start].
final class _Spin extends Motion {
  late final _loop = own(_SpinLoop());

  /// The brightest spoke now.
  int get head => _loop.head;

  /// Starts the turn at [t].
  void start(double t) {
    _loop.start = t;
    _loop.wake(t);
  }
}

final class _SpinLoop extends MotionLoop {
  static const spokes = 8;

  double start = 0;
  int head = 0;

  @override
  bool step(double t) {
    head = ((t - start) * spokes).floor() % spokes;
    return true;
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.head, required this.color})
    : super(repaint: head);

  final ValueListenable<int> head;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spokes = _SpinLoop.spokes;
    final head = this.head.value;
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
/// again on every frame of [frames].
@internal
class MenuCardHeader extends StatelessWidget {
  /// Creates the header [header] of a card.
  const MenuCardHeader({
    required this.frames,
    required this.header,
    required this.placed,
    required this.values,
    required this.style,
    required this.width,
    required this.content,
    super.key,
  });

  /// The frames on which the header reads [placed] and [values] again.
  final ValueListenable<Object?> frames;

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

  Color get _title => style.textStyle.color!;

  static const _bold = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  Widget _text(BuildContext context, TextStyle base) => Text(
    header.title ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: resolveGlassText(base, context).copyWith(color: _title),
  );

  Rect _span(double start, double extent, double height, bool rtl) =>
      Rect.fromLTWH(rtl ? width - start - extent : start, 0, extent, height);

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final entry = header.entry;
    final icon = entry is GlassSubmenu ? entry.icon : null;
    final rtl = content.rtl;
    final metrics = content.metrics;
    final height = header.rect.height;
    return Positioned.fromRect(
      rect: header.rect,
      // The header is the back target, described by its zone.
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (header.imageCenter != null && icon != null)
              menuDriven(
                frames,
                (_) => menuPlacement(
                  _span(
                    placed().imageCenter! - MenuTuning.imageSlot / 2,
                    MenuTuning.imageSlot,
                    height,
                    rtl,
                  ),
                ),
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(size: style.iconSize, color: _title),
                    child: icon,
                  ),
                ),
              ),
            menuDriven(
              frames,
              (_) {
                final now = placed();
                return menuPlacement(
                  _span(
                    now.titleStart,
                    now.titleEnd - now.titleStart,
                    height,
                    rtl,
                  ),
                );
              },
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  menuDriven(
                    frames,
                    (_) => Opacity(opacity: 1 - values().bold),
                    child: _text(context, style.textStyle),
                  ),
                  menuDriven(
                    frames,
                    (_) => Opacity(opacity: values().bold),
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
                  child: menuDriven(
                    frames,
                    (_) => Transform.rotate(
                      angle: values().turn * math.pi / 2,
                    ),
                    child: CustomPaint(
                      size: MenuTuning.chevronSize,
                      painter: _ChevronPainter(color: _title),
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
              child: menuDriven(
                frames,
                (_) => Opacity(opacity: values().separator),
                child: ColoredBox(color: style.separatorColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
