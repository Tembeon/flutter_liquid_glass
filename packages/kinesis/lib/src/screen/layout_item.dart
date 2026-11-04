import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/layout.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/selection.dart';

/// One item of a layout host: where it is drawn, and which descendants
/// draw it themselves.
@internal
final class LayoutItemEntry {
  /// Follows [id] of [motion].
  LayoutItemEntry(LayoutMotion motion, this.id)
    : item = motion.select((m) => m.itemAt(id));

  /// The item's key.
  final Object id;

  /// Where the item is drawn.
  final MotionSelection<LayoutItem> item;

  /// The probe's key, which keeps the item's element through moves.
  final GlobalKey key = GlobalKey();

  final Set<Element> _adopters = {};

  /// The probe that draws the item, told when adoption changes.
  RenderObject? probe;

  /// The widget the item last built, which a leaving item keeps.
  Widget? last;

  /// Whether a descendant draws the item itself.
  bool get adopted => _adopters.isNotEmpty;

  /// Records whether [adopter] draws the item.
  void adopt(Element adopter, {required bool adopts}) {
    final was = adopted;
    if (adopts) {
      _adopters.add(adopter);
    } else {
      _adopters.remove(adopter);
    }
    if (adopted != was) probe?.markNeedsCompositedLayerUpdate();
  }
}

/// The aspect under which a descendant adopts its item.
@internal
const Object adoptsItem = #adopts;

/// Hands an item's [entry] to the item's content.
@internal
class LayoutItemScope extends InheritedWidget {
  /// Scopes [child] to [entry].
  const LayoutItemScope({required this.entry, required super.child, super.key});

  /// The item.
  final LayoutItemEntry entry;

  /// Where the item is drawn.
  ValueListenable<LayoutItem> get item => entry.item;

  /// The item around [context], or null; with [adopt] the dependent draws
  /// it itself.
  static ValueListenable<LayoutItem>? of(
    BuildContext context, {
    bool adopt = false,
  }) => context
      .dependOnInheritedWidgetOfExactType<LayoutItemScope>(
        aspect: adopt ? adoptsItem : null,
      )
      ?.item;

  @override
  bool updateShouldNotify(LayoutItemScope oldWidget) =>
      !identical(oldWidget.entry, entry);

  @override
  InheritedElement createElement() => _LayoutItemScopeElement(this);
}

class _LayoutItemScopeElement extends InheritedElement {
  _LayoutItemScopeElement(super.widget);

  LayoutItemEntry get _entry => (widget as LayoutItemScope).entry;

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    super.updateDependencies(dependent, aspect);
    if (identical(aspect, adoptsItem)) _entry.adopt(dependent, adopts: true);
  }

  @override
  void removeDependent(Element dependent) {
    _entry.adopt(dependent, adopts: false);
    super.removeDependent(dependent);
  }

  @override
  void updated(LayoutItemScope oldWidget) {
    if (!identical(oldWidget.entry, _entry)) {
      for (final adopter in oldWidget.entry._adopters.toList()) {
        oldWidget.entry.adopt(adopter, adopts: false);
        _entry.adopt(adopter, adopts: true);
      }
    }
    super.updated(oldWidget);
  }
}
