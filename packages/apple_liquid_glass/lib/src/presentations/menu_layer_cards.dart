import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/presentations/menu_anchor_look.dart';
import 'package:apple_liquid_glass/src/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/presentations/menu_card_geometry.dart';
import 'package:apple_liquid_glass/src/presentations/menu_layer_highlight.dart';
import 'package:apple_liquid_glass/src/presentations/menu_layer_scope.dart';
import 'package:apple_liquid_glass/src/presentations/menu_layer_scroll.dart';
import 'package:apple_liquid_glass/src/presentations/menu_rows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The trees of an open menu's cards: the root list in its scroll view and
/// each submenu card on its glass, with their rows, highlight and header,
/// following the motion's frames without a rebuild.
@internal
class MenuLayerCards {
  /// Creates the cards of the layer it is given, whose root list scrolls
  /// with [scroll] and whose rows show [highlight].
  MenuLayerCards(
    this._layer, {
    required this.scroll,
    required this.highlight,
  });

  final MenuLayerScope _layer;

  /// The root list's scrolling.
  final MenuLayerScroll scroll;

  /// The highlight the cards' rows show.
  final MenuLayerHighlight highlight;
  final Map<MenuLayout, (int?, Widget)> _rows = Map.identity();
  MenuAppearance? _rowsStyle;

  MenuMotion get _motion => _layer.motion;

  double get _width => _motion.menuWidth;

  Widget _rowsOf(int card, MenuLayout layout, MenuAppearance style) {
    if (style != _rowsStyle) {
      _rows.clear();
      _rowsStyle = style;
    }
    final hidden = _layer.built.hidden[card];
    final cached = _rows[layout];
    if (cached != null && cached.$1 == hidden) return cached.$2;
    final rows = RepaintBoundary(
      child: DefaultTextStyle(
        style: resolveGlassText(style.textStyle, _layer.context),
        child: MenuRows(
          layout: layout,
          style: style,
          hidden: hidden,
          content: _layer.content,
        ),
      ),
    );
    _rows[layout] = (hidden, rows);
    return rows;
  }

  Widget _root(
    MenuLayout layout,
    MenuAppearance style, {
    required bool locked,
  }) {
    final content = SizedBox(
      width: _width,
      height: layout.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          highlight.of(layout, style, 0),
          _rowsOf(0, layout, style),
        ],
      ),
    );
    final body = _layer.built.scrolls
        ? scroll.body(content, style)
        : OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: layout.height,
            maxHeight: layout.height,
            child: content,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        locked ? _motion.cornerRadius : 0,
      ),
      child: IgnorePointer(ignoring: locked, child: body),
    );
  }

  /// Card [index], laid out as [layout] in [style], following the
  /// motion's frames: the root list, or a submenu card on its glass.
  Widget card(int index, MenuLayout layout, MenuAppearance style) {
    final width = _width;
    if (index == 0) {
      final locked = _layer.built.layouts.length > 1;
      scroll.lock(locked: locked);
      return _driven(
        key: const ValueKey<int>(0),
        (motion) {
          final root = motion.cards[0];
          final s = root.scale;
          return menuPlacement(
            Rect.fromLTWH(
              width / 2 * (1 - s),
              0,
              width,
              motion.visibleRootHeight,
            ),
            Transform(
              alignment: Alignment.topLeft,
              transform: Matrix4.diagonal3Values(s, s, 1),
              child: Opacity(opacity: root.rowOpacity.clamp(0.0, 1.0)),
            ),
          );
        },
        child: _root(layout, style, locked: locked),
      );
    }
    // A card that has just gone keeps its last frame until the layer
    // builds without it: the render objects hear the tick first.
    var last = _motion.cards[index];
    MenuCard card() {
      final cards = _motion.cards;
      if (index < cards.length) last = cards[index];
      return last;
    }

    var lastShown = Rect.zero;
    MenuPlaced? header;
    for (final element in layout.elements) {
      if (element.kind == MenuPlacedKind.cardHeader) header = element;
    }
    double radius() => math.min(_motion.cornerRadius, card().rect.height / 2);
    return _driven(
      key: ValueKey<int>(index),
      (motion) {
        if (index < motion.cards.length) {
          lastShown = menuCardShown(
            motion.cards,
            index,
            width,
            motion.visibleRootHeight,
          );
        }
        final flex = motion.cardFlex(index);
        final center = lastShown.center + flex.shift;
        final now = card();
        final size = now.rect.size;
        final s = now.scale;
        return menuPlacement(
          Offset(
                center.dx - (lastShown.width + flex.width) / 2,
                center.dy - (lastShown.height + flex.height) / 2,
              ) &
              size,
          Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.diagonal3Values(
              s + flex.width / size.width,
              s + flex.height / size.height,
              1,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: MenuLiveGlass(
              live: _layer.frames,
              frameOf: () => GlassFrame(
                shape: GlassShape.roundedRect(radius()),
                glow: _motion.cardGlow(index),
                opacity: card().platterOpacity * _motion.cardMaterialOpacity,
              ),
            ),
          ),
          _driven(
            (_) => ClipRRect(
              clipper: MenuClip(
                RRect.fromRectAndRadius(
                  Offset.zero & card().rect.size,
                  Radius.circular(radius()),
                ),
              ),
            ),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width,
              maxWidth: width,
              minHeight: layout.height,
              maxHeight: layout.height,
              child: _driven(
                (_) => Transform.translate(
                  offset: Offset(-card().rect.left, card().contentTop),
                ),
                child: SizedBox(
                  width: width,
                  height: layout.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      highlight.of(layout, style, index),
                      _driven((_) {
                        final now = card();
                        return Opacity(
                          opacity:
                              (now.rowsOpacity *
                                      now.rowOpacity *
                                      now.closeOpacity)
                                  .clamp(0.0, 1.0),
                        );
                      }, child: _rowsOf(index, layout, style)),
                      if (header != null)
                        _driven(
                          (_) {
                            final now = card();
                            return Opacity(
                              opacity: (now.rowOpacity * now.closeOpacity)
                                  .clamp(0.0, 1.0),
                            );
                          },
                          child: DefaultTextStyle(
                            style: resolveGlassText(
                              style.textStyle,
                              _layer.context,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                MenuCardHeader(
                                  frames: _layer.frames,
                                  header: header,
                                  placed: () => index < _motion.cards.length
                                      ? menuCardHeaderAt(
                                          _motion.cards,
                                          index,
                                          header!,
                                        )
                                      : header!,
                                  values: () {
                                    final now = card();
                                    return (
                                      bold: now.headerBold.clamp(0.0, 1.0),
                                      turn: now.chevronTurn.clamp(0.0, 1.0),
                                      separator: now.platterOpacity.clamp(
                                        0.0,
                                        1.0,
                                      ),
                                    );
                                  },
                                  style: style,
                                  width: layout.width,
                                  content: _layer.content,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  MotionDriven _driven(
    SingleChildRenderObjectWidget Function(MenuMotion motion) template, {
    Widget? child,
    Key? key,
  }) => menuDriven(_layer.frames, template, child: child, key: key);
}
