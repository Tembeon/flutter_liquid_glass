part of 'tab_bar.dart';

class _AccessoryScope
    extends InheritedNotifier<ValueNotifier<GlassTabAccessoryPlacement>> {
  const _AccessoryScope({required super.notifier, required super.child});
}

/// Lays the accessory's content out in [rect], laid out again when it
/// changes, without a rebuild.
class _AccessoryLayout extends SingleChildLayoutDelegate {
  _AccessoryLayout(this.rect) : super(relayout: rect);

  final ValueListenable<Rect> rect;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(rect.value.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => rect.value.topLeft;

  @override
  bool shouldRelayout(_AccessoryLayout oldDelegate) =>
      !identical(oldDelegate.rect, rect);
}

/// Where the bottom accessory stands in its box: `expanded` above the
/// bar, `inline` beside the minimized circle and, beside a search tab,
/// `searching` while the search is open.
typedef _AccessoryPlaces = ({Rect expanded, Rect inline, Rect? searching});

/// The bottom accessory: its glass goes from above the bar to beside the
/// circle with the bar's glass, and over the search morph to its place
/// above the tab circle; its content stands in the place its glass heads
/// for, switching as the transition starts, clipped to the moving glass.
class _Accessory extends StatefulWidget {
  const _Accessory({
    required this.body,
    required this.places,
    required this.look,
    required this.child,
    this.search,
  });

  final _MinimizeFrames body;
  final _AccessoryPlaces places;

  /// The search's morph, 0 at rest and 1 searching, and whether it is open,
  /// beside a search tab.
  final ({ValueListenable<double> morph, ValueListenable<bool> open})? search;
  final GlassTabBarStyle look;
  final Widget child;

  @override
  State<_Accessory> createState() => _AccessoryState();
}

class _AccessoryState extends State<_Accessory> {
  late MotionSelection<GlassFrame> _frame = _frameNow();
  late MotionSelection<Rect> _heading = _headingNow();
  late MotionSelection<Offset> _carried = _carriedNow();
  final _placement = ValueNotifier(GlassTabAccessoryPlacement.expanded);

  @override
  void initState() {
    super.initState();
    widget.body.minimized.addListener(_placed);
    widget.search?.open.addListener(_placed);
    _placed();
  }

  @override
  void didUpdateWidget(_Accessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.body, widget.body)) {
      oldWidget.body.minimized.removeListener(_placed);
      widget.body.minimized.addListener(_placed);
    }
    if (!identical(oldWidget.search?.open, widget.search?.open)) {
      oldWidget.search?.open.removeListener(_placed);
      widget.search?.open.addListener(_placed);
    }
    if (!identical(oldWidget.body, widget.body) ||
        oldWidget.places != widget.places ||
        oldWidget.search != widget.search) {
      _frame = _frameNow();
      _heading = _headingNow();
      _carried = _carriedNow();
    }
    _placed();
  }

  @override
  void dispose() {
    widget.body.minimized.removeListener(_placed);
    widget.search?.open.removeListener(_placed);
    _placement.dispose();
    super.dispose();
  }

  MotionSelection<GlassFrame> _frameNow() {
    final body = widget.body;
    final (:expanded, :inline, :searching) = widget.places;
    final search = widget.search;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    return MotionSelection(clock: body.accessoryX.clock, () {
      final x = body.accessoryX.value;
      final y = body.accessoryY.value;
      final rect = Rect.fromLTRB(
        lerp(expanded.left, inline.left, x),
        lerp(expanded.top, inline.top, y),
        lerp(expanded.right, inline.right, x),
        lerp(expanded.bottom, inline.bottom, y),
      );
      if (searching == null || search == null) return GlassFrame(rect: rect);
      return GlassFrame(rect: Rect.lerp(rect, searching, search.morph.value));
    });
  }

  MotionSelection<Rect> _headingNow() {
    final (:expanded, :inline, :searching) = widget.places;
    final open = widget.search?.open;
    return MotionSelection(clock: _frame.clock, () {
      if (searching != null && (open?.value ?? false)) return searching;
      return widget.body.minimized.value ? inline : expanded;
    });
  }

  MotionSelection<Offset> _carriedNow() => MotionSelection(
    clock: _frame.clock,
    () => _frame.value.rect!.center - _heading.value.center,
  );

  void _placed() {
    final open = widget.search?.open.value ?? false;
    _placement.value = widget.body.minimized.value && !open
        ? GlassTabAccessoryPlacement.inline
        : GlassTabAccessoryPlacement.expanded;
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.look.backgroundColor?.resolve(const {});
    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.bar,
            glass: Glass.regular(
              tint: background == null
                  ? null
                  : GlassDynamicColor.resolve(background, context),
            ),
            frame: _frame,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: GlassClip.live(
            frame: _frame,
            child: CustomSingleChildLayout(
              delegate: _AccessoryLayout(_heading),
              child: MotionTransition(
                offset: _carried,
                child: _AccessoryScope(
                  notifier: _placement,
                  child: Padding(
                    padding: _accessoryPadding,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The space between the bottom accessory's glass and its content (top 8,
/// leading 16, bottom 8, trailing 16; read from UIKit).
const _accessoryPadding = EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8);
