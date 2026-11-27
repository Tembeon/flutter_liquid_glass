import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// UIKit's edit menu: a glass capsule of actions beside a selection or a
/// point, such as Cut, Copy and Paste.
///
/// UIKit: `UIEditMenuInteraction`, the menu a text input shows. Flutter:
/// `CupertinoTextSelectionToolbar`, given to a `contextMenuBuilder`.
///
/// ```dart
/// GlassTextField(
///   contextMenuBuilder: (context, editableTextState) => GlassEditMenu(
///     anchorAbove: editableTextState.contextMenuAnchors.primaryAnchor,
///     anchorBelow: editableTextState.contextMenuAnchors.secondaryAnchor ??
///         editableTextState.contextMenuAnchors.primaryAnchor,
///     buttonItems: [
///       ...editableTextState.contextMenuButtonItems,
///       ContextMenuButtonItem(label: 'Define', onPressed: define),
///     ],
///   ),
/// )
/// ```
///
/// The menu is a capsule 44 points tall, its glass 4 points past its
/// cells: each a title in 15 point regular text 16 points in from either
/// side, with a line 1 by 18 between two. It stands 15 points below
/// [anchorBelow] where that lies in the upper half of the safe area and 15
/// points above [anchorAbove] in the lower half, on the other side where
/// there is no room, centered on the anchors' x and inside the safe area.
/// It opens from a fifth of its size about the edge that faces them,
/// fading in, on a spring (UIKit's fitted response 0.23 s, damping 0.94).
/// A delete is red; an item without `onPressed` is gray and takes no tap.
/// Items that do not fit stand behind a forward button at the end, which
/// turns the menu into a list of every item, 250 points wide, its rows 42
/// tall. These are measured on the iOS 27.2 simulator (edit menu
/// passport); the press, the glow under the finger, the morph into the
/// list and the close are not reproduced, nor is the list's corner radius
/// measured.
///
/// [GlassEditMenu.editableText] is the menu of a text input: UIKit's own
/// on iOS where Flutter can show it (`SystemContextMenu`), so Paste asks
/// nothing and the system's actions come with it, and this one elsewhere.
class GlassEditMenu extends StatefulWidget {
  /// Creates a menu of [buttonItems] beside the anchors.
  const GlassEditMenu({
    required this.anchorAbove,
    required this.anchorBelow,
    required this.buttonItems,
    super.key,
  }) : _editable = null;

  /// The edit menu of [editableTextState], at its anchors with its items.
  GlassEditMenu.editableText({
    required EditableTextState editableTextState,
    super.key,
  }) : _editable = editableTextState,
       anchorAbove = editableTextState.contextMenuAnchors.primaryAnchor,
       anchorBelow =
           editableTextState.contextMenuAnchors.secondaryAnchor ??
           editableTextState.contextMenuAnchors.primaryAnchor,
       buttonItems = editableTextState.contextMenuButtonItems;

  final EditableTextState? _editable;

  /// The point the menu stands over, in global coordinates: the top of a
  /// selection.
  final Offset anchorAbove;

  /// The point the menu stands under, in global coordinates: the bottom
  /// of a selection.
  final Offset anchorBelow;

  /// The actions, in order; one without a label of its own takes the
  /// platform's label for its kind.
  final List<ContextMenuButtonItem> buttonItems;

  /// The height of the menu at the default text size.
  static const double height = 44;

  /// The space between the menu and its anchor.
  static const double gap = 15;

  @override
  State<GlassEditMenu> createState() => _GlassEditMenuState();
}

class _GlassEditMenuState extends State<GlassEditMenu> {
  EditMenuMotion? _motion;
  bool _expanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motion != null) return;
    _motion = EditMenuMotion(clock: MotionClockScope.of(context))
      ..present(
        reduceMotion: MotionTraitsOverride.of(context).reduceMotion,
      );
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget._editable;
    if (editable != null && SystemContextMenu.isSupportedByField(editable)) {
      return SystemContextMenu.editableText(editableTextState: editable);
    }
    final strings = WidgetsLocalizations.of(context);
    final items = [
      for (final item in widget.buttonItems)
        if (_labelOf(item, strings) case final label?)
          (item: item, label: label),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final room = media.padding
        .add(const EdgeInsets.symmetric(horizontal: _Metrics.margin))
        .resolve(TextDirection.ltr)
        .deflateRect(Offset.zero & media.size);
    final scale = GlassTextScale.of(context);
    final barHeight = math.max(
      GlassEditMenu.height,
      scale.scaler.scale(_Metrics.titleLine) + 2 * _Metrics.titleTop,
    );
    final above = widget.anchorAbove;
    final below = widget.anchorBelow;
    final middle = (room.top + room.bottom) / 2;
    var under = (above.dy + below.dy) / 2 < middle;
    if (under && below.dy + GlassEditMenu.gap + barHeight > room.bottom) {
      under = false;
    }
    if (!under && above.dy - GlassEditMenu.gap - barHeight < room.top) {
      under = true;
    }
    final top = under
        ? below.dy + GlassEditMenu.gap
        : above.dy - GlassEditMenu.gap - barHeight;
    final motion = _motion!;
    return CustomSingleChildLayout(
      delegate: _MenuLayout(
        top: top,
        centerX: above.dx,
        room: room,
      ),
      child: TextFieldTapRegion(
        child: MotionTransition(
          scale: motion.scale,
          opacity: motion.opacity,
          alignment: under ? Alignment.topCenter : Alignment.bottomCenter,
          child: _expanded
              ? _List(items: items)
              : _Bar(
                  items: items,
                  height: barHeight,
                  room: room.width,
                  onForward: () => setState(() => _expanded = true),
                ),
        ),
      ),
    );
  }

  static String? _labelOf(ContextMenuButtonItem item, WidgetsLocalizations s) =>
      item.label ??
      switch (item.type) {
        ContextMenuButtonType.cut => s.cutButtonLabel,
        ContextMenuButtonType.copy => s.copyButtonLabel,
        ContextMenuButtonType.paste => s.pasteButtonLabel,
        ContextMenuButtonType.selectAll => s.selectAllButtonLabel,
        ContextMenuButtonType.lookUp => s.lookUpButtonLabel,
        ContextMenuButtonType.searchWeb => s.searchWebButtonLabel,
        ContextMenuButtonType.share => s.shareButtonLabel,
        ContextMenuButtonType.delete ||
        ContextMenuButtonType.liveTextInput ||
        ContextMenuButtonType.custom => null,
      };
}

/// The edit menu passport's numbers.
abstract final class _Metrics {
  // The glass past the first and the last cell.
  static const double inset = 4;

  // A title's space on either side, and its line and top at 15 points.
  static const double cellPadding = 16;
  static const double titleLine = 18;
  static const double titleTop = 13;

  // The line between two cells.
  static const double separatorHeight = 18;
  static const separator = GlassDynamicColor.withBrightness(
    color: Color(0x1F3C3C43),
    darkColor: Color(0x80545458),
  );

  // The forward button's slot past the cells, the button 36 across with
  // a chevron 11.67 by 16.
  static const double forwardSlot = 32;
  static const double forwardButton = 36;
  static const Size chevron = Size(11.67, 16);

  // The list the forward button turns the menu into.
  static const double listWidth = 250;
  static const double listRow = 42;
  static const double listTitleStart = 28;
  static const double listRadius = 22;

  // How far the menu keeps from the safe area's sides: this package's own.
  static const double margin = 8;

  static const disabled = GlassDynamicColor.withBrightness(
    color: Color(0x993C3C43),
    darkColor: Color(0x99EBEBF5),
  );
}

typedef _Item = ({ContextMenuButtonItem item, String label});

Color _colorOf(BuildContext context, ContextMenuButtonItem item) =>
    GlassDynamicColor.resolve(
      item.onPressed == null
          ? _Metrics.disabled
          : item.type == ContextMenuButtonType.delete
          ? GlassColors.systemRed
          : GlassTheme.labelColorOf(context),
      context,
    );

class _Bar extends StatelessWidget {
  const _Bar({
    required this.items,
    required this.height,
    required this.room,
    required this.onForward,
  });

  final List<_Item> items;
  final double height;
  final double room;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final scale = GlassTextScale.of(context);
    final direction = Directionality.of(context);
    final style = scale.resolve(const TextStyle(fontSize: 15));
    double widthOf(_Item item) =>
        scale
            .measure(
              item.label,
              style,
              textDirection: direction,
              maxLines: 1,
            )
            .size
            .width +
        2 * _Metrics.cellPadding;
    final widths = [for (final item in items) widthOf(item)];
    var shown = items.length;
    final whole = widths.fold<double>(2 * _Metrics.inset, (a, b) => a + b);
    if (whole > room) {
      var used = 2 * _Metrics.inset + _Metrics.forwardSlot;
      shown = 0;
      while (shown < items.length && used + widths[shown] <= room) {
        used += widths[shown];
        shown++;
      }
      shown = math.max(shown, 1);
    }
    final separator = GlassDynamicColor.resolve(_Metrics.separator, context);
    return GlassSurface(
      role: GlassRole.panel,
      shape: LiquidRoundedSuperellipse(radius: height / 2),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _Metrics.inset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < shown; i++)
                CustomPaint(
                  foregroundPainter: i == 0
                      ? null
                      : _Separator(color: separator, direction: direction),
                  child: _Cell(
                    item: items[i].item,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _Metrics.cellPadding,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: scale.scaler,
                          style: style.copyWith(
                            color: _colorOf(context, items[i].item),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (shown < items.length)
                SizedBox(
                  width: _Metrics.forwardSlot,
                  child: OverflowBox(
                    maxWidth: _Metrics.forwardButton,
                    child: _Cell(
                      item: ContextMenuButtonItem(onPressed: onForward),
                      label: GlassLocalizations.of(context).editMenuMoreLabel,
                      child: SizedBox.square(
                        dimension: _Metrics.forwardButton,
                        child: Center(
                          child: CustomPaint(
                            size: _Metrics.chevron,
                            painter: _Chevron(
                              color: GlassDynamicColor.resolve(
                                GlassTheme.labelColorOf(context),
                                context,
                              ),
                              direction: direction,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.items});

  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final scale = GlassTextScale.of(context);
    final style = scale.resolve(const TextStyle(fontSize: 17));
    return GlassSurface(
      role: GlassRole.panel,
      shape: const LiquidRoundedSuperellipse(radius: _Metrics.listRadius),
      child: SizedBox(
        width: _Metrics.listWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (:item, :label) in items)
              _Cell(
                item: item,
                child: SizedBox(
                  height: math.max(
                    _Metrics.listRow,
                    scale.scaler.scale(_Metrics.listRow),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: _Metrics.listTitleStart,
                      end: _Metrics.cellPadding,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: scale.scaler,
                        style: style.copyWith(color: _colorOf(context, item)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One action of the menu: a button that runs it on a tap, gray and
/// still without one.
class _Cell extends StatefulWidget {
  const _Cell({required this.item, required this.child, this.label});

  final ContextMenuButtonItem item;
  final String? label;
  final Widget child;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final _tap = TapInteraction(onTap: (_) => widget.item.onPressed?.call());
  late final List<Interaction> _interactions = [_tap];

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _interactions,
    enabled: widget.item.onPressed != null,
    semantics: SemanticsProperties(label: widget.label, button: true),
    child: widget.child,
  );
}

class _Separator extends CustomPainter {
  const _Separator({required this.color, required this.direction});

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final x = direction == TextDirection.rtl ? size.width : 0.0;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(x, size.height / 2),
        width: 1,
        height: _Metrics.separatorHeight,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Separator oldDelegate) =>
      color != oldDelegate.color || direction != oldDelegate.direction;
}

class _Chevron extends CustomPainter {
  const _Chevron({required this.color, required this.direction});

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.19;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final near = stroke / 2 + size.width * 0.12;
    final far = size.width - near;
    final (from, to) = direction == TextDirection.rtl
        ? (far, near)
        : (near, far);
    canvas.drawPath(
      Path()
        ..moveTo(from, stroke / 2)
        ..lineTo(to, size.height / 2)
        ..lineTo(from, size.height - stroke / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Chevron oldDelegate) =>
      color != oldDelegate.color || direction != oldDelegate.direction;
}

/// Places the menu at [top], centered on [centerX], inside [room].
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.top, required this.centerX, required this.room});

  final double top;
  final double centerX;
  final Rect room;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(math.max(0, room.width), math.max(0, room.height)),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (centerX - childSize.width / 2).clamp(
      room.left,
      math.max(room.left, room.right - childSize.width),
    ),
    top.clamp(room.top, math.max(room.top, room.bottom - childSize.height)),
  );

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      top != oldDelegate.top ||
      centerX != oldDelegate.centerX ||
      room != oldDelegate.room;
}
