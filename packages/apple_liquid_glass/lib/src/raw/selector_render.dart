part of 'selector.dart';

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

/// How much a fully lifted tab bar lens grows the items it shows: the held
/// item shows at 1.218 of its resting size while the swollen bar carries
/// the others at 1.052, so the lens adds 1.158, rounded to 0.16 (NEAR)
/// (iPhone 16 Pro, tab bar passport). A segmented control's lens shows
/// its label in place (0.996).
const double _tabBarMagnification = 0.16;

class _RenderSelectorRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData>,
        MotionResolveHost {
  _RenderSelectorRow({
    required this._motion,
    required this._frames,
    required this._kind,
    required this._keys,
    required this._ghosts,
    required this._itemWidths,
    required this._proportional,
    required this._collapse,
    required this._hosted,
    required this._showsLens,
    required this._hasLens,
    required this._lensShrink,
    required this._direction,
  });

  _SelectorMotion _motion;
  _SelectorMotion get motion => _motion;
  set motion(_SelectorMotion value) {
    if (identical(value, _motion)) return;
    _motion = value;
    markNeedsLayout();
  }

  _SelectorFrames _frames;
  _SelectorFrames get frames => _frames;
  set frames(_SelectorFrames value) {
    if (identical(value, _frames)) return;
    if (attached) _unlisten();
    _frames = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  GlassSelectorMotion _kind;
  GlassSelectorMotion get kind => _kind;
  set kind(GlassSelectorMotion value) {
    if (value == _kind) return;
    _kind = value;
    markNeedsLayout();
  }

  List<Object> _keys;
  List<Object> get keys => _keys;
  set keys(List<Object> value) {
    if (listEquals(value, _keys)) return;
    _keys = value;
    markNeedsLayout();
  }

  List<Object> _ghosts;
  List<Object> get ghosts => _ghosts;
  set ghosts(List<Object> value) {
    if (listEquals(value, _ghosts)) return;
    _ghosts = value;
    markNeedsLayout();
  }

  List<double?>? _itemWidths;
  List<double?>? get itemWidths => _itemWidths;
  set itemWidths(List<double?>? value) {
    if (listEquals(value, _itemWidths)) return;
    _itemWidths = value;
    markNeedsLayout();
  }

  bool _proportional;
  bool get proportional => _proportional;
  set proportional(bool value) {
    if (value == _proportional) return;
    _proportional = value;
    markNeedsLayout();
  }

  GlassSelectorCollapse? _collapse;
  GlassSelectorCollapse? get collapse => _collapse;
  set collapse(GlassSelectorCollapse? value) {
    if (identical(value, _collapse)) return;
    if (attached) _unlistenCollapse();
    final spans = (value == null) != (_collapse == null);
    _collapse = value;
    if (attached) _listenCollapse();
    if (spans) markNeedsLayout();
    markNeedsPaint();
  }

  bool _hosted;
  bool get hosted => _hosted;
  set hosted(bool value) {
    if (value == _hosted) return;
    _hosted = value;
    markNeedsLayout();
  }

  bool _showsLens;
  bool get showsLens => _showsLens;
  set showsLens(bool value) {
    if (value == _showsLens) return;
    _showsLens = value;
    markNeedsPaint();
  }

  bool _hasLens;
  bool get hasLens => _hasLens;
  set hasLens(bool value) {
    if (value == _hasLens) return;
    _hasLens = value;
    markNeedsLayout();
  }

  ValueListenable<GlassLensShrink> _lensShrink;
  ValueListenable<GlassLensShrink> get lensShrink => _lensShrink;
  set lensShrink(ValueListenable<GlassLensShrink> value) {
    if (identical(value, _lensShrink)) return;
    if (attached) _lensShrink.removeListener(markNeedsPaint);
    _lensShrink = value;
    if (attached) _lensShrink.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  // The items move in the resolve phase, after this box's layout, so only a
  // render listener hears them in the frame they move; the lens and the
  // dimming publish before build.
  void _listen() {
    _frames.lens.addListener(markNeedsPaint);
    _frames.dim.addListener(markNeedsPaint);
    _frames.items.addRenderListener(markNeedsPaint);
  }

  void _unlisten() {
    _frames.lens.removeListener(markNeedsPaint);
    _frames.dim.removeListener(markNeedsPaint);
    _frames.items.removeRenderListener(markNeedsPaint);
  }

  void _listenCollapse() {
    _collapse?.morph.addListener(markNeedsPaint);
    _collapse?.press?.addListener(markNeedsPaint);
  }

  void _unlistenCollapse() {
    _collapse?.morph.removeListener(markNeedsPaint);
    _collapse?.press?.removeListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
    _listenCollapse();
    _lensShrink.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _unlisten();
    _unlistenCollapse();
    _lensShrink.removeListener(markNeedsPaint);
    super.detach();
  }

  // The blur of the items that dissolve as the bar collapses, kept between
  // paints.
  final _othersBlur = LayerHandle<ImageFilterLayer>();

  @override
  void dispose() {
    _othersBlur.layer = null;
    super.dispose();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
  }

  RenderBox? get _lens => _hasLens ? lastChild : null;

  /// The items of the selector, without those fading out.
  Iterable<(RenderBox, RenderBox, RenderBox)> get _live =>
      _items.take(_keys.length);

  /// Every item's regular look and its selected copies under and over the
  /// lens, in order, then those of the items fading out.
  Iterable<(RenderBox, RenderBox, RenderBox)> get _items sync* {
    final lens = _lens;
    var child = firstChild;
    while (child != null && child != lens) {
      final under = childAfter(child);
      final over = under == null ? null : childAfter(under);
      if (under == null || over == null || over == lens) return;
      yield (child, under, over);
      child = childAfter(over);
    }
  }

  // UIKit sizes a tab by its regular title, not its bolder selected one.
  List<double> _itemExtents(double height) => [
    for (final (regular, _, selected) in _live)
      if (_kind == GlassSelectorMotion.tabBar)
        regular.getMaxIntrinsicWidth(height)
      else
        math.max(
          regular.getMaxIntrinsicWidth(height),
          selected.getMaxIntrinsicWidth(height),
        ),
  ];

  double get _height => _Geometry.height(_kind);

  double _natural() =>
      _Geometry.natural(_kind, _itemExtents(_height), _itemWidths);

  @override
  double computeMinIntrinsicWidth(double height) => _natural();

  @override
  double computeMaxIntrinsicWidth(double height) => _natural();

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  _Geometry _geometry(BoxConstraints constraints) => _Geometry.of(
    _kind,
    constraints,
    _itemExtents(_height),
    fixed: _itemWidths,
    proportional: _proportional,
    spans: _collapse != null,
    hosted: _hosted,
  );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _geometry(constraints).size;

  Rect _shown(Rect slot) =>
      _direction == TextDirection.rtl ? mirroredIn(slot, size.width) : slot;

  // The box's offset in its box ancestors, up to the first that is not a
  // box (a sliver under a scroll, which moves without a layout).
  Offset _origin() {
    var offset = Offset.zero;
    RenderObject node = this;
    while (node.parent is RenderBox) {
      if (node.parentData case final BoxParentData data) offset += data.offset;
      node = node.parent!;
    }
    return offset;
  }

  ({_Geometry geometry, Map<Object, Rect> rects, Offset origin})? _laidOut;

  @override
  void performLayout() {
    final geometry = _geometry(constraints);
    size = geometry.size;
    final rects = <Object, Rect>{};
    var i = 0;
    for (final (regular, under, over) in _items) {
      final Rect slot;
      if (i < _keys.length) {
        slot = _shown(geometry.slots[i]);
        rects[_keys[i]] = slot;
      } else {
        final ghost = _motion.items.laidOut(_ghosts[i - _keys.length]);
        slot = Offset.zero & (ghost?.size ?? Size.zero);
      }
      // A bar given no room lays its tabs out narrower than nothing.
      final room = Size(math.max(0, slot.width), math.max(0, slot.height));
      for (final child in [regular, under, over]) {
        child.layout(BoxConstraints.tight(room));
        (child.parentData! as _RowParentData).offset = slot.topLeft;
      }
      i++;
    }
    _lens?.layout(BoxConstraints.tight(size));
    // The parents place the box after this layout: the offset read now is
    // the one it was drawn at.
    _laidOut = (geometry: geometry, rects: rects, origin: _origin());
    scheduleResolve();
  }

  @override
  void resolve() {
    final laidOut = _laidOut;
    if (laidOut == null) return;
    _laidOut = null;
    _motion.layout(
      _motion.clock.now,
      laidOut.geometry,
      laidOut.rects,
      shift: _origin() - laidOut.origin,
      mirrored: _direction == TextDirection.rtl,
      spring: layoutSpring,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final (item, _, _) in _live) {
      final hit = result.addWithPaintOffset(
        offset: (item.parentData! as _RowParentData).offset,
        position: position,
        hitTest: (result, local) => item.hitTest(result, position: local),
      );
      if (hit) return true;
    }
    return false;
  }

  // How far the selected glyph has travelled toward the circle from the tab
  // it stands on in [slot].
  Offset _glyphTravel(Rect slot, double morph) {
    final circle = _collapse!.circleIn(size);
    return (circle.center -
            Offset(slot.center.dx, TabBarMinimizeMotion.glyphCenter)) *
        morph;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final morph = _collapse?.morph.value ?? 0;
    if (morph != 0) {
      final selected = _motion.selected;
      var i = 0;
      for (final (regular, _, above) in _live) {
        if (i == selected && identical(child, above)) {
          final travel = _glyphTravel(
            (regular.parentData! as _RowParentData).offset & regular.size,
            morph,
          );
          transform.translateByDouble(travel.dx, travel.dy, 0, 1);
        }
        i++;
      }
    }
    super.applyPaintTransform(child, transform);
  }

  // UIKit draws the regular items under the lens, cut out where it sits,
  // and a selected copy of every item masked by the lens (tab bar
  // passport); the lifted lens's glass bends the copy and, at its rim, the
  // items around it.
  @override
  void paint(PaintingContext context, Offset offset) {
    final collapse = _collapse;
    final morph = collapse?.morph.value ?? 0;
    final frame = _frames.lens.value;
    final rect = frame.drawnIn(size);
    final mask = _showsLens
        ? RSuperellipse.fromRectAndRadius(
            rect,
            Radius.circular(frame.shape.radiusIn(rect)),
          )
        : null;
    final cutter = morph == 0 ? mask : null;
    final (dimmed, opacity) = _frames.dim.value;
    final slots = <Rect>[];
    var i = 0;
    for (final (regular, _, _) in _items) {
      final live = i < _keys.length;
      final drawn = _motion.drawn(
        live ? _keys[i] : _ghosts[i - _keys.length],
      );
      final laid = (regular.parentData! as _RowParentData).offset;
      final slot = Rect.fromCenter(
        center: drawn?.$1.center ?? (laid & regular.size).center,
        width: regular.size.width,
        height: regular.size.height,
      );
      if (live) slots.add(slot);
      if (!live && drawn == null) {
        i++;
        continue;
      }
      void paintRegular(PaintingContext context, Offset offset) {
        if (cutter == null || !cutter.outerRect.overlaps(slot)) {
          context.paintChild(regular, offset + slot.topLeft);
          return;
        }
        // The slot outside the lens, without a path operation each frame:
        // even-odd leaves the slot less the lens and the lens past the slot,
        // which the slot's rect clips away.
        final cut = Path();
        cut.fillType = PathFillType.evenOdd;
        cut.addRect(slot);
        cut.addRSuperellipse(cutter);
        context.pushClipRect(
          needsCompositing,
          offset,
          slot,
          (context, offset) => context.pushClipPath(
            needsCompositing,
            offset,
            slot,
            cut,
            (context, offset) =>
                context.paintChild(regular, offset + slot.topLeft),
          ),
        );
      }

      final alpha = (drawn?.$2 ?? 1) * (i == dimmed ? opacity : 1);
      if (morph != 0) {
        // Drawn together below, where they dissolve as one.
      } else if (alpha < 1) {
        context.pushOpacity(
          offset,
          Color.getAlphaFromOpacity(alpha.clamp(0.0, 1.0)),
          paintRegular,
        );
      } else {
        paintRegular(context, offset);
      }
      i++;
    }
    if (morph != 0) _paintDissolving(context, offset, slots, morph);
    final copies = frame.opacity;
    final lift = frame.lift.clamp(0.0, 1.0);
    final glass = mask == null ? 0.0 : GlassFrame.glassnessAt(lift);
    final zoom = _kind == GlassSelectorMotion.tabBar
        ? 1 + _tabBarMagnification * lift
        : 1.0;
    if (mask != null && glass > 0 && copies > 0) {
      final (:shrink, :rim) = _lensShrink.value;
      _paintCopies(
        context,
        offset,
        mask,
        slots,
        opacity: glass * copies,
        under: true,
        zoom: zoom,
        grow: 1 + (1 / (1 - shrink * lift) - 1) * glass,
        rim: rim,
      );
    }
    final lens = _lens;
    if (lens != null) context.paintChild(lens, offset);
    if (mask != null && glass < 1 && copies > 0) {
      _paintCopies(
        context,
        offset,
        mask,
        slots,
        opacity: (1 - glass) * copies,
        under: false,
        zoom: zoom,
        grow: 1,
        rim: 0,
      );
    }
    if (morph != 0) _paintGlyph(context, offset, slots, morph, lift);
  }

  // The tabs, the selected one's regular look among them, stay about where
  // they are inside the shrinking glass and dissolve as one.
  void _paintDissolving(
    PaintingContext context,
    Offset offset,
    List<Rect> slots,
    double morph,
  ) {
    final left = 1 - morph / TabBarMinimizeMotion.othersGoneAt;
    if (left <= 0) return;
    final body = _frames.body.value.drawnIn(size);
    final toward = _collapse!.circleIn(size).center.dx;
    final together = 1 - TabBarMinimizeMotion.othersDrift * morph;
    void items(PaintingContext context, Offset offset) {
      var i = 0;
      for (final (regular, _, _) in _live) {
        final slot = slots[i++];
        final x = toward + (slot.center.dx - toward) * together;
        context.paintChild(
          regular,
          offset + Offset(x - slot.width / 2, slot.top),
        );
      }
    }

    void dissolved(PaintingContext context, Offset offset) {
      final sigma = TabBarMinimizeMotion.othersBlur * morph.clamp(0.0, 1.0);
      if (sigma <= 0) {
        _othersBlur.layer = null;
        return items(context, offset);
      }
      final layer = _othersBlur.layer ??= ImageFilterLayer();
      layer.imageFilter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      context.pushLayer(layer, items, offset);
    }

    context.pushClipRSuperellipse(
      true,
      offset,
      body,
      RSuperellipse.fromRectAndRadius(
        body,
        Radius.circular(body.shortestSide / 2),
      ),
      (context, offset) => context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(left.clamp(0.0, 1.0)),
        dissolved,
      ),
    );
  }

  // The selected glyph travels to the circle and stands in it, lifted with
  // it under a finger. Once a finger carries the lens, the lens shows the
  // selected look, and this copy goes as it lands.
  void _paintGlyph(
    PaintingContext context,
    Offset offset,
    List<Rect> slots,
    double morph,
    double lift,
  ) {
    final selected = _motion.selected;
    if (!_showsLens || selected < 0 || selected >= slots.length) return;
    final slot = slots[selected];
    final (_, _, above) = _live.elementAt(selected);
    final travel = _glyphTravel(slot, morph);
    final scale =
        1 +
        (_collapse!.press?.value ?? 0) *
            TabBarMinimizeMotion.pressGrowth *
            2 /
            TabBarMinimizeMotion.collapsedSize;
    final center =
        Offset(slot.center.dx, TabBarMinimizeMotion.glyphCenter) + travel;
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.scaleByDouble(scale, scale, 1, 1);
    transform.translateByDouble(
      -center.dx + travel.dx,
      -center.dy + travel.dy,
      0,
      1,
    );
    void glyph(PaintingContext context, Offset offset) => context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) => context.paintChild(above, offset + slot.topLeft),
    );
    final shows =
        1 -
        lift * (1 - morph / TabBarMinimizeMotion.lensGoneAt).clamp(0.0, 1.0);
    if (shows >= 1) return glyph(context, offset);
    context.pushOpacity(offset, Color.getAlphaFromOpacity(shows), glyph);
  }

  // The copy under the glass shows through it as the lifted lens takes
  // over from its platter, the one over the platter fading as it goes.
  //
  // The glass reads what lies under it [grow] times farther from the
  // nearest point of its center line (half of it is `axis`, from the lens
  // center) than it shows it: across the line beside it, radially about
  // each end beyond it. So the copy under it is grown the same way first,
  // each part exact in its own strip, and through the glass every item
  // shows on its slot while only the lens slides over it, as in UIKit.
  // Each item is magnified about its own slot by [zoom].
  void _paintCopies(
    PaintingContext context,
    Offset offset,
    RSuperellipse mask,
    List<Rect> slots, {
    required double opacity,
    required bool under,
    required double zoom,
    required double grow,
    required double rim,
  }) {
    final bounds = mask.outerRect;
    final center = bounds.center;
    final half = rim * (bounds.longestSide - bounds.shortestSide) / 2;
    final alongX = bounds.width >= bounds.height;
    final axis = grow == 1
        ? Offset.zero
        : alongX
        ? Offset(half, 0)
        : Offset(0, half);
    final start = center - axis;
    final end = center + axis;
    final strips = axis == Offset.zero
        ? [(bounds, center, grow, grow)]
        : [
            (
              alongX
                  ? Rect.fromLTRB(
                      bounds.left,
                      bounds.top,
                      start.dx,
                      bounds.bottom,
                    )
                  : Rect.fromLTRB(
                      bounds.left,
                      bounds.top,
                      bounds.right,
                      start.dy,
                    ),
              start,
              grow,
              grow,
            ),
            (
              alongX
                  ? Rect.fromLTRB(start.dx, bounds.top, end.dx, bounds.bottom)
                  : Rect.fromLTRB(bounds.left, start.dy, bounds.right, end.dy),
              center,
              alongX ? 1.0 : grow,
              alongX ? grow : 1.0,
            ),
            (
              alongX
                  ? Rect.fromLTRB(
                      end.dx,
                      bounds.top,
                      bounds.right,
                      bounds.bottom,
                    )
                  : Rect.fromLTRB(
                      bounds.left,
                      end.dy,
                      bounds.right,
                      bounds.bottom,
                    ),
              end,
              grow,
              grow,
            ),
          ];
    void paintMasked(PaintingContext context, Offset offset) =>
        context.pushClipRSuperellipse(needsCompositing, offset, bounds, mask, (
          context,
          offset,
        ) {
          for (final (strip, anchor, growX, growY) in strips) {
            if (strip.isEmpty) continue;
            context.pushClipRect(needsCompositing, offset, strip, (
              context,
              offset,
            ) {
              var i = 0;
              for (final (_, below, above) in _live) {
                final copy = under ? below : above;
                final slot = slots[i++];
                final transform = _copyTransform(
                  slot.center,
                  zoom,
                  anchor,
                  growX,
                  growY,
                );
                if (!MatrixUtils.transformRect(
                  transform,
                  slot,
                ).overlaps(strip)) {
                  continue;
                }
                context.pushTransform(
                  needsCompositing,
                  offset,
                  transform,
                  (context, offset) =>
                      context.paintChild(copy, offset + slot.topLeft),
                );
              }
            });
          }
        });
    if (opacity >= 1) {
      paintMasked(context, offset);
    } else {
      context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(opacity),
        paintMasked,
      );
    }
  }

  // An item grows about its own slot by [zoom], so it stays put while the
  // lens window slides over it, then by ([growX], [growY]) about [anchor].
  static Matrix4 _copyTransform(
    Offset slot,
    double zoom,
    Offset anchor,
    double growX,
    double growY,
  ) {
    final transform = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    transform.scaleByDouble(growX, growY, 1, 1);
    transform.translateByDouble(
      slot.dx - anchor.dx,
      slot.dy - anchor.dy,
      0,
      1,
    );
    transform.scaleByDouble(zoom, zoom, 1, 1);
    transform.translateByDouble(-slot.dx, -slot.dy, 0, 1);
    return transform;
  }
}
