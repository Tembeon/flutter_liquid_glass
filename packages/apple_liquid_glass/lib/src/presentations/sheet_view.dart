part of 'sheet.dart';

class _SheetView extends StatefulWidget {
  const _SheetView({required this.motion, required this.spec});

  final _SheetPresented motion;
  final _SheetSpec spec;

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView> implements GlassSheet {
  // Everything _publish reads, so a frame that moved the sheet publishes it
  // and one that did not costs nothing.
  late final MotionSelection<Object?> _frames = widget.motion.select((m) {
    final sheet = m.sheet;
    if (sheet == null) return null;
    return (
      sheet.height,
      sheet.visibleRect(_size.height),
      sheet.bottomRadius,
      sheet.fill,
      sheet.hasEvents,
    );
  });
  late final _SheetScrollController _scroll = _SheetScrollController(this);
  final _frame = ValueNotifier(
    _Frame(
      height: 0,
      transform: Matrix4.identity(),
      body: RSuperellipse.zero,
    ),
  );
  final _fill = ValueNotifier<double>(0);
  late final MotionSelection<bool> _glass = widget.motion.select(
    (m) => (m.sheet?.fill ?? 0) < 1,
  );
  late final MotionSelection<bool> _opaque = widget.motion.select(
    (m) => (m.sheet?.fill ?? 0) >= 1,
  );
  late final MotionSelection<bool> _fading = widget.motion.select((m) {
    final fill = m.sheet?.fill ?? 0;
    return fill > 0 && fill < 1;
  });
  List<int> _order = const [];
  // The detent the sheet rests at or heads to, as an index of its detents.
  final _detent = ValueNotifier<int>(0);
  late final _range = _DetentRange(this);
  late final List<Interaction> _detentInput = [_DetentStep(_step)];
  late final _SheetTouch _touchInput = _SheetTouch(this);
  List<Interaction> _input = const [];
  double? _contendedSlop;
  Size _size = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;
  double _keyboard = 0;
  double? _fitted;
  double? _displayRadius;
  double _dragY = 0;
  // The stamp of the latest event of a touch on the sheet, which a drag
  // the content's scrollable hands on happens at.
  double _stamp = 0;
  int? _touch;
  Offset _touchFrom = Offset.zero;
  bool _touchDragged = false;

  _SheetSpec get _spec => widget.spec;

  SheetMotion? get _motion => widget.motion.sheet;

  bool get _leaving => widget.motion.left;

  double get _now => widget.motion.clock.now;

  // The time a release or a cancel acts at: the frame's, not an earlier
  // stamp's.
  double get _frameTime => widget.motion.clock.frameTime;

  @override
  List<GlassSheetDetent> get detents => _spec.detents;

  @override
  GlassSheetDetent get detent => detents[_detent.value];

  @override
  void initState() {
    super.initState();
    _detent.value = math.max(
      0,
      detents.indexOf(_spec.initialDetent ?? detents[0]),
    );
    _frames.addListener(_stepped);
  }

  @override
  void dispose() {
    _frames.removeListener(_stepped);
    _scroll.dispose();
    _frame.dispose();
    _fill.dispose();
    _detent.dispose();
    super.dispose();
  }

  void _stepped() {
    _deliver();
    _publish();
  }

  @override
  void animateTo(GlassSheetDetent detent) {
    final i = detents.indexOf(detent);
    final motion = _motion;
    if (i < 0 || motion == null || _leaving) return;
    motion.animateTo(_now, _order.indexOf(i));
    _deliver();
  }

  void _deliver() {
    final motion = _motion;
    if (motion == null) return;
    for (final event in motion.drainEvents()) {
      if (!mounted) return;
      switch (event) {
        case SheetDetentChanged(:final index, :final byUser):
          _detent.value = _order[index];
          // UIKit reports a detent the user picks, not one set from code.
          if (byUser) _spec.onDetentChanged?.call(detent);
        case SheetDismissed() || SheetDismissRefused():
          if (!_leaving) {
            PresentationHandle.of(
              context,
            ).dismiss(DismissTrigger.interaction);
          }
      }
    }
  }

  bool get _dismissAllowed =>
      PresentationHandle.of(context).canDismiss(DismissTrigger.interaction);

  void _fittedHeight(double t, Size size) {
    if (!mounted || _fitted == size.height) return;
    _fitted = size.height;
    _layout(_size, _padding, _keyboard, at: t);
  }

  // A keyboard raises the sheet as UIKit's does (simulator capture): each
  // detent grows by the keyboard's height up to the maximum, and the sheet
  // moves to its largest detent while the keyboard shows, back to the
  // selected one when it hides, neither reported as a detent change.
  void _layout(
    Size size,
    EdgeInsets padding,
    double keyboard, {
    double? at,
  }) {
    if (at == null &&
        size == _size &&
        padding == _padding &&
        keyboard == _keyboard &&
        _motion != null) {
      return;
    }
    final raised = keyboard > 0;
    final wasRaised = _keyboard > 0;
    _size = size;
    _padding = padding;
    _keyboard = keyboard;
    final maximum = math.max<double>(
      0,
      size.height - padding.top - padding.bottom,
    );
    final values = [
      for (final d in detents)
        math.min(
              d.resolve(maximum, fittedHeight: _fitted) + keyboard,
              maximum,
            ) +
            padding.bottom,
    ];
    final order = List<int>.generate(detents.length, (i) => i);
    order.sort((a, b) => values[a].compareTo(values[b]));
    _order = order;
    final heights = [for (final i in order) values[i]];
    final docked = order.indexWhere((i) => detents[i].isLarge);
    final undimmed = _spec.largestUndimmedDetent;
    final undimmedAt = undimmed == null
        ? -1
        : order.indexWhere((i) => detents[i] == undimmed);
    final index = raised ? order.length - 1 : order.indexOf(_detent.value);
    final motion = _motion;
    if (motion == null) {
      final created = SheetMotion(
        heights: heights,
        width: size.width,
        initial: index,
        fullHeight: maximum + padding.bottom,
        dockedIndex: docked < 0 ? null : docked,
        undimmedIndex: undimmedAt < 0 ? null : undimmedAt,
        dismissible: _spec.isDismissible,
        displayRadius: _displayRadius,
      );
      widget.motion.attach(_now, created);
    } else {
      motion.relayout(
        at ?? _now,
        heights,
        size.width,
        fullHeight: maximum + padding.bottom,
        index: raised == wasRaised ? null : index,
      );
    }
  }

  void _publish() {
    final motion = _motion;
    if (motion == null) return;
    final h = motion.height;
    final drawn = motion.visibleRect(_size.height);
    final k = _size.width <= 0 ? 1.0 : drawn.width / _size.width;
    final ky = motion.stretch != 1 && h > 0 ? drawn.height / h : k;
    final transform = Matrix4.translationValues(drawn.left, drawn.top, 0);
    transform.multiply(Matrix4.diagonal3Values(k, ky, 1));
    final bottom = Radius.circular(motion.bottomRadius);
    const top = Radius.circular(_SheetLook.topRadius);
    _frame.value = _Frame(
      height: h,
      transform: transform,
      body: RSuperellipse.fromLTRBAndCorners(
        0,
        0,
        _size.width,
        h,
        topLeft: top,
        topRight: top,
        bottomLeft: bottom,
        bottomRight: bottom,
      ),
    );
    _fill.value = motion.fill;
  }

  // The drag and its release follow DragInteraction's travel past the
  // slop, which counts in screen points as the sheet moves and scales
  // under the finger.
  List<Interaction> _inputFor(double contendedSlop) {
    if (contendedSlop == _contendedSlop) return _input;
    _contendedSlop = contendedSlop;
    return _input = [
      _touchInput,
      // Alone in the gesture arena the sheet starts past UIKit's slop.
      // Over a control or a list that wants the touch too, it starts past
      // the list's slop, and a list that passes it on the same move takes
      // the touch. NEAR: 18 points there, against 12 on the device.
      DragInteraction(
        axis: Axis.vertical,
        slop: SheetMotion.dragSlop,
        contendedSlop: contendedSlop,
        global: true,
        onStart: _dragStart,
        onUpdate: _dragUpdate,
        onEnd: (details) => _release(details.time, details.velocity.dy),
        onCancel: (t) => _motion?.dragCancel(_frameTime),
      ),
    ];
  }

  void _down(PointerDownInput input) {
    _stamp = input.time;
    final motion = _motion;
    if (motion == null || _leaving || _touch != null) return;
    _touch = input.pointer;
    _touchFrom = input.position;
    _touchDragged = false;
    motion.press(_stamp);
  }

  void _move(PointerMoveInput input) {
    _stamp = input.time;
    if (input.pointer != _touch) return;
    if ((input.position - _touchFrom).distance > kTouchSlop) {
      _touchDragged = true;
    }
  }

  void _up(int pointer, double t, {required bool lifted}) {
    _stamp = t;
    if (pointer != _touch) return;
    _touch = null;
    final motion = _motion;
    if (motion == null) return;
    if (!motion.isDragging) motion.unpress(_stamp);
    if (lifted &&
        !_touchDragged &&
        _touchFrom.dy < SheetMotion.grabberHitHeight) {
      if (motion.isDragging) motion.dragCancel(_stamp);
      motion.tapGrabber(_stamp);
    }
    _deliver();
  }

  void _dragStart(DragInteractionDetails details) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    motion.dismissible = _dismissAllowed;
    motion.dragStart(details.time, details.translation.dy);
  }

  void _dragUpdate(DragInteractionDetails details) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragUpdate(details.time, details.translation.dy);
  }

  void _release(double t, double velocity) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragEnd(math.max(t, _frameTime), velocity);
    _deliver();
  }

  void _scrollDragBy(double delta) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    final t = math.max(_stamp, _frameTime);
    if (!motion.isDragging) {
      motion.dismissible = _dismissAllowed;
      _dragY = 0;
      motion.dragStart(t, 0);
    }
    _dragY += delta;
    motion.dragUpdate(t, _dragY);
  }

  bool get _canExpand {
    final motion = _motion;
    if (motion == null) return false;
    return motion.height < motion.heights.last - 0.5;
  }

  bool get _scrollDragging => _motion?.isDragging ?? false;

  // The content widget is reused while its inputs hold, so a rebuild of
  // the chrome (each keyboard-inset frame) leaves the app's builder alone.
  // A detent change hands the scope a new detent over the same content:
  // only what reads the sheet through GlassSheet.of rebuilds.
  Widget? _content;
  TextStyle? _style;

  Widget _contentFor(BuildContext context) {
    final text = TextStyle(
      fontSize: 17,
      color: GlassTheme.labelColorOf(context),
    ).merge(_spec.lookOf(context).textStyle);
    final style = resolveGlassText(
      text.copyWith(color: GlassDynamicColor.resolve(text.color!, context)),
      context,
    );
    var content = _content;
    if (content == null || style != _style) {
      _style = style;
      content = _content = DefaultTextStyle(
        style: style,
        child: detents.any((d) => d.isFitted)
            ? Align(
                alignment: Alignment.topLeft,
                child: MotionMeasure(
                  onSize: _fittedHeight,
                  child: Builder(builder: _spec.builder),
                ),
              )
            : Builder(builder: _spec.builder),
      );
    }
    return content;
  }

  // A step of the keyboard or a screen reader, along the detents by
  // height.
  void _step(double t, ValueCommand command) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    final at = _order.indexOf(_detent.value);
    final last = _order.length - 1;
    final to = switch (command) {
      .increase || .increaseLarge => at + 1,
      .decrease || .decreaseLarge => at - 1,
      .toMinimum => 0,
      .toMaximum => last,
    }.clamp(0, last);
    if (to == at) return;
    motion.pick(t, to);
    _deliver();
  }

  String _detentName(GlassLocalizations strings, int index) {
    final detent = detents[index];
    if (detent.isLarge) return strings.sheetLargeDetentValue;
    if (detent == GlassSheetDetent.medium) {
      return strings.sheetMediumDetentValue;
    }
    return strings.sheetDetentValue(_order.indexOf(index) + 1, _order.length);
  }

  // The scale of the sheet floating on a screen of this width: the target
  // keeps its 44 points on screen at the smallest scale the sheet rests at.
  double _floatingScale(BuildContext context) =>
      1 - 2 * SheetMotion.floatingInset / MediaQuery.sizeOf(context).width;

  // The band at the top where a tap cycles the detents, as a target the
  // keyboard and screen readers step the detents with: a box from the
  // sheet's top edge at least 44 points square on screen, so the target
  // stays inside the sheet's clip. No finger reaches it: a touch there is
  // the sheet's drag and tap, and reaches the content below.
  Widget _grabber(BuildContext context, Color color) {
    final handle = SizedBox.fromSize(size: _SheetLook.grabberSize);
    final top = _SheetLook.grabberOffset - _SheetLook.grabberSize.height / 2;
    final side = _target / _floatingScale(context);
    return Align(
      alignment: Alignment.topCenter,
      child: InputRegion(
        interactions: _detentInput,
        semantics: SemanticsProperties(
          label: GlassLocalizations.of(context).sheetGrabberLabel,
        ),
        adjustRange: _range,
        child: _DetentValue(
          state: this,
          child: SizedBox(
            width: math.max(_SheetLook.grabberSize.width, side),
            height: math.max(top + _SheetLook.grabberSize.height, side),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: _spec.showDragHandle
                    ? DecoratedBox(
                        decoration: ShapeDecoration(
                          color: color,
                          shape: const StadiumBorder(),
                        ),
                        child: handle,
                      )
                    : handle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final input = _inputFor(media.gestureSettings.touchSlop ?? kTouchSlop);
    _displayRadius = MediaQuery.maybeDisplayCornerRadiiOf(
      context,
    )?.bottomLeft.x;
    final content = _contentFor(context);
    final look = _spec.lookOf(context);
    final docked = GlassDynamicColor.resolve(
      look.backgroundColor ?? _Colors.docked,
      context,
    );
    final grabber = GlassDynamicColor.resolve(
      look.dragHandleColor ?? _Colors.grabber,
      context,
    );
    final inner = MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          top: 0,
          bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
        ),
        viewPadding: media.viewPadding.copyWith(top: 0),
        viewInsets: EdgeInsets.zero,
      ),
      child: content,
    );
    return _SheetScope(
      state: this,
      child: _DetentScope(
        state: this,
        detent: _detent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _layout(
              constraints.biggest,
              EdgeInsets.only(
                top: media.padding.top,
                bottom: media.padding.bottom,
              ),
              media.viewInsets.bottom,
            );
            _motion!.displayRadius = _displayRadius;
            _publish();
            return Stack(
              children: [
                Positioned.fill(
                  key: const ValueKey('sheet'),
                  child: _SheetBox(
                    frame: _frame,
                    child: Semantics(
                      explicitChildNodes: true,
                      child: InputRegion(
                        interactions: input,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MotionVisibility(
                              visible: _glass,
                              child: const GlassSurface(
                                shape: GlassShape.superellipse(
                                  _SheetLook.topRadius,
                                ),
                                role: GlassRole.panel,
                                child: SizedBox.expand(),
                              ),
                            ),
                            MotionVisibility(
                              visible: _opaque,
                              child: ColoredBox(color: docked),
                            ),
                            MotionVisibility(
                              visible: _fading,
                              child: MotionTransition(
                                opacity: _fill,
                                child: ColoredBox(color: docked),
                              ),
                            ),
                            // Fitted content lays out up to the maximum, not
                            // the sheet's height, so content that grows is
                            // measured at its new height in the frame it
                            // grows, while the sheet follows a frame later.
                            if (detents.any((d) => d.isFitted))
                              OverflowBox(
                                alignment: Alignment.topLeft,
                                minHeight: 0,
                                maxHeight: math.max(
                                  0,
                                  constraints.maxHeight -
                                      media.padding.top -
                                      media.padding.bottom,
                                ),
                                child: inner,
                              )
                            else
                              inner,
                            if (_spec.showDragHandle || detents.length > 1)
                              _grabber(context, grabber),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
