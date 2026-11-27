import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/widgets/controls/button.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_anchor.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:flutter/widgets.dart';

/// One choice of a [GlassPopUpButton].
@immutable
class GlassPopUpItem<T> {
  /// Creates a choice of [value], shown as [title].
  const GlassPopUpItem({
    required this.value,
    required this.title,
    this.icon,
    this.enabled = true,
  });

  /// What the choice stands for.
  final T value;

  /// What the menu row and, once chosen, the button show.
  final String title;

  /// The row's icon, or null for none.
  final Widget? icon;

  /// Whether the row can be chosen.
  final bool enabled;
}

/// Builds the button of a [GlassPopUpButton] around [label]; a null
/// [onPressed] disables it.
typedef GlassPopUpButtonBuilder = Widget Function(
  BuildContext context,
  VoidCallback? onPressed,
  Widget label,
);

/// A button that shows its chosen value and opens a menu of the others.
///
/// UIKit: `UIButton` with a `menu`, `showsMenuAsPrimaryAction` and
/// `changesSelectionAsPrimaryAction`. SwiftUI: `Picker` in the `.menu`
/// style. Flutter: `DropdownButton`.
///
/// ```dart
/// GlassPopUpButton<String>(
///   value: sort,
///   items: const [
///     GlassPopUpItem(value: 'name', title: 'Name'),
///     GlassPopUpItem(value: 'date', title: 'Date'),
///   ],
///   onChanged: (value) => setState(() => sort = value),
/// )
/// ```
///
/// The button shows the chosen item's title and, 4 points after it, UIKit's
/// up and down chevrons, 12.33 by 14.67: two strokes 8.67 wide, 5 tall,
/// in the label's color. A tap opens a [GlassMenuAnchor] menu of [items],
/// the chosen one checked, and a row chosen calls [onChanged]. [builder]
/// gives the button, a glass [GlassButton] by default:
/// `(context, onPressed, label) => GlassButton.gray(onPressed: onPressed,
/// child: label)` for UIKit's gray one. A null [onChanged] disables it.
///
/// Fidelity. The chevrons' box, ink and place are measured on the iOS 27.2
/// simulator (button passport, a tree dump and a screenshot of gray and
/// glass pop-up buttons titled "One", 72 by 34.33).
class GlassPopUpButton<T> extends StatelessWidget {
  /// Creates a pop-up button showing the item of [value].
  const GlassPopUpButton({
    required this.value,
    required this.items,
    required this.onChanged,
    this.builder,
    this.semanticLabel,
    super.key,
  });

  /// The chosen value; the item that holds it shows on the button.
  final T value;

  /// The choices, in the menu's order.
  final List<GlassPopUpItem<T>> items;

  /// Called with the value of a row chosen from the menu; null disables
  /// the button.
  final ValueChanged<T>? onChanged;

  /// Builds the button around its label, or null for a [GlassButton].
  final GlassPopUpButtonBuilder? builder;

  /// What the menu is called for screen readers, or null for the button's
  /// label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chosen = items.where((item) => item.value == value).firstOrNull;
    final onChanged = this.onChanged;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(chosen?.title ?? '', maxLines: 1)),
        const SizedBox(width: _PopUpChevrons.gap),
        const _PopUpChevrons(),
      ],
    );
    final build =
        builder ??
        (context, onPressed, label) =>
            GlassButton(onPressed: onPressed, child: label);
    return GlassMenuAnchor(
      semanticLabel: semanticLabel,
      enabled: onChanged != null,
      menuChildren: [
        for (final item in items)
          GlassMenuItem(
            title: item.title,
            icon: item.icon,
            enabled: item.enabled,
            state: item.value == value
                ? GlassMenuItemState.on
                : GlassMenuItemState.off,
            onPressed: onChanged == null ? null : () => onChanged(item.value),
          ),
      ],
      builder: (context, controller, _) =>
          build(context, onChanged == null ? null : controller.open, label),
    );
  }
}

/// UIKit's `chevron.up.chevron.down` of a pop-up button: two chevrons 8.67
/// wide and 5 tall in a 12.33 by 14.67 box, 1.67 in from its leading side,
/// the upper from 1 point down, the lower from 8.67 (screenshot of the iOS
/// 27.2 simulator at 3x).
class _PopUpChevrons extends StatelessWidget {
  const _PopUpChevrons();

  static const double gap = 4;
  static const Size size = Size(12.33, 14.67);

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        GlassDynamicColor.resolve(GlassColors.label, context);
    return ExcludeSemantics(
      child: CustomPaint(size: size, painter: _ChevronsPainter(color)),
    );
  }
}

class _ChevronsPainter extends CustomPainter {
  _ChevronsPainter(this.color);

  final Color color;

  static const double _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    const half = _stroke / 2;
    const left = 1.67 + half;
    const right = 1.67 + 8.67 - half;
    const middle = 1.67 + 8.67 / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(left, 6 - half)
          ..lineTo(middle, 1 + half)
          ..lineTo(right, 6 - half),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(left, 8.67 + half)
          ..lineTo(middle, 13.67 - half)
          ..lineTo(right, 8.67 + half),
        paint,
      );
  }

  @override
  bool shouldRepaint(_ChevronsPainter oldDelegate) =>
      oldDelegate.color != color;
}
