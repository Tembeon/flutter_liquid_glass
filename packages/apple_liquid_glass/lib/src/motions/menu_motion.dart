import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/menu_event.dart';
import 'package:apple_liquid_glass/src/motions/menu_flex.dart';
import 'package:apple_liquid_glass/src/motions/menu_fusion.dart';
import 'package:apple_liquid_glass/src/motions/menu_layout.dart';
import 'package:apple_liquid_glass/src/motions/menu_metrics.dart';
import 'package:apple_liquid_glass/src/motions/menu_outline_math.dart';
import 'package:apple_liquid_glass/src/motions/menu_placed.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:apple_liquid_glass/src/motions/outline_boxes.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

part 'menu_motion_state.dart';

/// The motion of a glass button turning into its menu and back: a pure
/// function of the touches it is fed and the time it is advanced to.
///
/// One progress drives two shapes. The menu shape grows out of the button: a
/// square of the menu's width scaled down to half the button's height that
/// stretches to the menu's height while it scales up, rides from the button's
/// center to the menu's center and dips past it on a vertical kick. The button
/// shape shrinks to a quarter and slides a quarter of the way toward the menu.
/// The two are drawn as one body: fused, neck included, while a turn's fusion
/// runs ([fusionRadius]), their plain union otherwise. The button's glyph rides
/// the button shape, widening as it blurs out early; the menu content rides the
/// menu shape at the shape's scale, swelling a little with its kick, and fades
/// in with the progress, so the menu unfolds out of the drop.
///
/// The kicks are a second degree of freedom per shape, driven by the
/// progress spring: while the menu opens, the menu shape's kick chases
/// the velocity of the opening spring, played from the moment the menu
/// started opening, on [MenuTuning.openKickSpring]; a close strikes
/// it away from the button ([MenuTuning.closeKickImpulse]) and it
/// rings out on [MenuTuning.closeKickSpring], and the button
/// shape's kick chases the velocity of the closing spring. Each kick steps
/// on its own fixed grid ([MenuTuning.kickIntegrationStep]), so it carries
/// through every reversal.
///
/// The content is a [MenuLayout]: uniform rows for a plain item count, or
/// whatever the `layout` builder lays out. A submenu
/// target opens a card that grows out of its row over the menu
/// ([MenuTuning.submenuSpring]), the cards under it shrink to
/// [MenuTuning.parentScale] and dim, and the menu grows to cover the
/// card; a card's header, or a touch beside it, sends it back. Content
/// that changes while the menu is open ([updateLayout]) resizes the menu
/// on [MenuTuning.growSpring] or [MenuTuning.shrinkSpring].
/// Content taller than [MenuMetrics.maxHeight] or the safe area is
/// cut to it and scrolls by [scrollOffset].
///
/// Feed pointer events in the coordinate space the menu is placed in with
/// their timestamps, call [advance] with the frame time, then read [menuBlob],
/// [buttonBlob] and the crossfade values. A tap opens on release, a hold
/// opens after [MenuTuning.holdDuration]; a release outside the
/// menu closes it and a release on a target chooses it. The finger that
/// opened the menu by holding chooses only after it has left the button:
/// released on the button it leaves the menu open, as UIKit does.
///
/// What a host acts on comes out as [MenuEvent]s ([drainEvents]).
class MenuMotion extends Motion with Presented {
  /// Creates the motion of the source `source` whose menu is `layout`
  /// (uniform rows of `itemCount` when null), inside `bounds` minus the
  /// safe-area `padding`.
  ///
  /// `layout` is asked for the content in the order it shows: reversed when the
  /// menu opens upward.
  ///
  /// With an [attachment] the menu is a context menu: it stands beside the
  /// attachment's preview and grows out of the blob at the held view's
  /// center ([MenuAttachment.blobSize]) instead of out of the source,
  /// along a straight line from the blob to its frame on the progress,
  /// and no source shape is drawn ([drawsSource]). The source is then the
  /// held view's frame, which a finger holding the menu open leaves to
  /// choose.
  ///
  MenuMotion({
    required this._source,
    required this._bounds,
    this._itemCount = 0,
    MenuLayout Function({required bool reversed})? layout,
    this._padding = EdgeInsets.zero,
    @internal this.tuning = MenuTuning.standard,
    this._attachment,
    super.clock,
  }) : _layoutFor = layout {
    _radius = own(
      MotionValue<double>(0, spring: tuning.openSpring),
      rest: () => _progressRest,
    );
    _kicks = own(_KickLoop(this));
    _root = _build(reversed: false);
    _rootHeight = own(
      MotionValue<double>(_visibleRoot(_root), spring: tuning.growSpring),
      rest: () => MotionRest.length,
    );
    _cardContainer = own(
      MotionValue<double>(1, spring: tuning.cardContainerSpring),
      rest: () => _cardContainerActive ? _cardRest : double.infinity,
    );
    _place(1);
  }

  /// Creates the motion of an iOS 27 context menu: the menu of the default
  /// constructor on the context menu's morph, dimming the page under it,
  /// beside the preview of [attachment].
  MenuMotion.context({
    required MenuSource source,
    required Size bounds,
    required MenuAttachment attachment,
    MenuLayout Function({required bool reversed})? layout,
    EdgeInsets padding = EdgeInsets.zero,
    MotionClock? clock,
  }) : this(
         source: source,
         bounds: bounds,
         layout: layout,
         padding: padding,
         tuning: MenuTuning.context,
         attachment: attachment,
         clock: clock,
       );

  /// Seconds a held finger needs to open the menu without a release: a
  /// host that takes the touch from its control once a hold opens the menu
  /// claims it after this.
  static double get holdDuration => MenuTuning.standard.holdDuration;

  /// Seconds the mouse rests on a submenu row before its card opens: 0,
  /// the default `hoverOpenDelay` of Flutter's `SubmenuButton` (Flutter
  /// 3.47, `material/menu_anchor.dart`), since no public document gives the
  /// delay of a Mac menu. Not measured; a finger waits
  /// [MenuTuning.hoverOpenDelay].
  static const double mouseSubmenuDelay = 0;

  // UIKit's link for the open and the close asks for 48 - 120 Hz and the
  // device's rows step at 120 Hz [device, menu-button.md]: at 60 the morph
  // reads as stuttering beside everything else on a 120 Hz screen.
  @override
  double get minFrameRate => 120;

  /// The measured behavior this motion reproduces.
  @internal
  final MenuTuning tuning;

  /// The width of the open menu.
  double get menuWidth => tuning.menuWidth;

  /// The height of one row.
  double get rowHeight => tuning.rowHeight;

  /// The corner radius of the open menu.
  double get cornerRadius => tuning.cornerRadius;

  late final MotionValue<double> _progress = own(
    MotionValue<double>(0, spring: tuning.openSpring),
    rest: () => _progressRest,
  );
  final MenuLayout Function({required bool reversed})? _layoutFor;

  MenuSource _source;
  MenuAttachment? _attachment;
  Offset _shift = Offset.zero;
  final int _itemCount;
  Size _bounds;
  EdgeInsets _padding;

  late final MotionValue<double> _radius;
  late final GlassPress _press = own(
    GlassPress(
      size: _source.shape.size,
      law: FlexLaw(stretches: false, activationDelay: tuning.pressDelay),
    ),
  );
  late final MenuFlex _flex = own(
    MenuFlex(
      tuning,
      frame: () => menuRect,
      side: () => _down ? 1.0 : -1.0,
      active: () => _phase == _Phase.opening,
    ),
  );
  late final MotionValue<double> _rootHeight;
  late final MotionValue<double> _cardContainer;
  bool _cardContainerActive = false;

  late MenuLayout _root;
  bool _reversed = false;
  final List<_Card> _cards = [];
  Ramp _cardFade = const Ramp(from: 1);
  double _resizeTo = 0;
  bool _resizeGrows = false;

  static const _resizeSlot = #resize;
  static const _dwellSlot = #dwell;
  static const _cardSlot = #card;
  static const _radiusSlot = #radius;
  static const _containerSlot = #container;
  static const _closeKickSlot = #closeKick;

  late final _KickLoop _kicks;
  MotionValue<double>? _openReference;
  MotionValue<double>? _closeReference;

  // A kick sleeps only while its input, the reference's velocity, has
  // died out.
  static bool _referenceRests(MotionValue<double> spring, double t) =>
      (spring.valueAt(t) - spring.target).abs() < MenuTuning.kickRestValue &&
      spring.velocityAt(t).abs() < MenuTuning.kickRestVelocity;
  late final FusionTurns _fusions = FusionTurns(tuning);
  final MenuFusion _fusion = MenuFusion();

  _Phase _phase = _Phase.idle;
  double _sourceScale = 1;
  double _left = 0;
  double _anchor = 0;
  bool _down = true;
  double _amplitude = 1;
  double _closeAmplitude = 1;
  double _sourceAmplitude = 1;
  double _radiusFrom = 0;
  double _closeRadius = 0;
  double _closeProgress = 1;
  double _closeStart = 0;
  double _closeSource = 1;
  double _closeLive = 1;
  Ramp _contentFade = const Ramp();
  bool _openPending = false;
  bool _returned = false;
  ({double t, Offset position})? _earlyRelease;
  _Pointer? _pointer;
  int? _highlighted;
  int _highlightCard = 0;
  late final TouchGlowMotion _touchGlow = own(tuning.touchGlow());

  late final MotionValue<double> _dim = own(
    MotionValue<double>(0),
    rest: () => MotionRest.opacity,
  );

  // Whether the menu's glass fades with the dim: from a close until a
  // fresh open. UIKit fades the menu view out on the dim's close spring as
  // it retracts (context-menu.md); a fresh open keeps it whole.
  bool _fadesGlass = false;

  /// How far the page under the menu is dimmed, 0 clear to 1 fully dimmed;
  /// 0 without a [MenuTuning.dim].
  double get dim => _dim.valueAt(_now).clamp(0.0, 1.0);

  /// How present the menu's glass is, 0 gone to 1 there: it follows [dim]
  /// out from a close, and back in should the menu reopen before it has
  /// gone.
  double get glassOpacity => _fadesGlass ? dim : 1;

  /// Whether a finger lights the open menu ([touchGlow]): false under
  /// Reduce Transparency, so the menu spends no frame on a glow.
  bool lightsGlow = true;

  void _lightGlow(double t, Offset position) {
    if (lightsGlow) _touchGlow.pointerDown(t, position);
  }

  /// Whether a tap on the button opens the menu, as a menu that is the
  /// button's primary action; false opens it only by holding, and a tap
  /// released on the button, or within [MenuTuning.tapSlop] of it,
  /// raises [MenuTapped] instead.
  bool opensOnTap = true;

  /// Lays out the card opened by a submenu target; no card opens while
  /// it is null or returns null.
  MenuLayout? Function(MenuTarget target)? submenuLayout;

  /// Whether choosing a target closes the menu: null leaves it to the
  /// target ([MenuTarget.keepsOpen]), true always closes, false
  /// never does (SwiftUI's `menuActionDismissBehavior`).
  bool? dismissOnSelect;

  /// How far the root list is scrolled, in points.
  ///
  /// Only content taller than the menu scrolls; the host keeps this in
  /// step with its scroll view so touches find the rows under them.
  double scrollOffset = 0;

  double get _now => _peekTime ?? now;

  double? _peekTime;
  double? _prefetchedFrom;

  /// The time the motion was last advanced to, in seconds.
  double get time => _now;

  /// Where a context menu stands, or null for a menu that grows out of its
  /// button.
  MenuAttachment? get attachment => _attachment;

  /// How far a context menu moved its preview to fit the menu inside the
  /// safe area; zero for a menu without an [attachment].
  Offset get previewShift => _shift;

  /// Whether the menu draws a source shape it grows out of: the button
  /// shape, which a context menu has none of.
  bool get drawsSource => _attachment == null;

  /// The blob a context menu grows out of, centered on the held view.
  Rect get _blob {
    final size = MenuAttachment.blobSize(_source.shape.size, menuRect.height);
    return Rect.fromCenter(
      center: _source.shape.center,
      width: size.width,
      height: size.height,
    );
  }

  /// The area a finger that opened the menu by holding leaves to choose:
  /// the button, or a context menu's lifted preview.
  Rect get _holdArea {
    final attachment = _attachment;
    if (attachment == null) return _source.shape;
    return attachment.preview.shift(_shift);
  }

  /// The content of the root list, in the order it shows.
  MenuLayout get layout => _root;

  /// The height of the menu's visible root list.
  double get visibleRootHeight => _rootHeight.valueAt(_now);

  MenuLayout _build({required bool reversed}) {
    final builder = _layoutFor;
    if (builder != null) return builder(reversed: reversed);
    return MenuLayout.uniform(
      _itemCount,
      width: tuning.menuWidth,
      rowHeight: tuning.rowHeight,
      inset: tuning.verticalPadding,
      reversed: reversed,
    );
  }

  double get _cap => math.max(
    tuning.rowHeight + 2 * tuning.verticalPadding,
    math.min(
      tuning.metrics.maxHeight,
      _bounds.height - _padding.top - _padding.bottom,
    ),
  );

  double _visibleRoot(MenuLayout layout) => math.min(layout.height, _cap);

  /// Updates the geometry; ignored while the menu is shown.
  void relayout({
    required MenuSource source,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    MenuAttachment? attachment,
  }) {
    if (_phase != _Phase.idle) return;
    _attachment = attachment;
    _source = source;
    _bounds = bounds;
    _padding = padding;
    _press.size = source.shape.size;
    _root = _build(reversed: _reversed);
    _rootHeight.snap(_now, _visibleRoot(_root));
    _place(_press.scaleAt(_now));
  }

  /// Lays the content out again at time [t], as after a change of the
  /// entries while the menu is open.
  ///
  /// With [animate] the menu grows on [MenuTuning.growSpring] or
  /// shrinks on [MenuTuning.shrinkSpring] after their delays, the
  /// way an open UIKit menu takes `updateVisibleMenu`; otherwise the new
  /// height applies at once. A change in the same direction while a
  /// resize waits for its delay joins it: the resize takes the latest
  /// height, so content that changes every frame still resizes the menu.
  /// Open cards are laid out again from the targets that opened them; a
  /// card whose target is gone closes.
  void updateLayout(double t, {bool animate = true}) {
    _take(t);
    _root = _build(reversed: _reversed);
    for (var i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      final parent = i == 0 ? _root : _cards[i - 1].layout;
      final source = card.source < parent.targets.length
          ? parent.targets[card.source]
          : null;
      final layout = source == null || source.kind != .submenu
          ? null
          : submenuLayout?.call(source);
      if (layout == null) {
        _dropCards(i);
        _setHighlight(null, 0);
        break;
      }
      card.layout = layout;
      card.top = _clampCardTop(card.top, layout.height);
    }
    if (_highlighted != null) {
      final targets = _layoutOf(_highlightCard).targets;
      if (_highlighted! >= targets.length) _setHighlight(null, 0);
    }
    final height = _visibleRoot(_root);
    if (_phase == _Phase.idle || !animate) {
      unschedule(_resizeSlot);
      _rootHeight.snap(t, height);
      if (_phase == _Phase.idle) _place(_press.scaleAt(t));
      return;
    }
    final unchanged = (height - _rootHeight.target).abs() < 1e-6;
    final grow = height > _rootHeight.target;
    if (isScheduled(_resizeSlot)) {
      if (unchanged) {
        unschedule(_resizeSlot);
        return;
      }
      if (grow == _resizeGrows) {
        _resizeTo = height;
        return;
      }
    }
    if (unchanged) return;
    _resizeTo = height;
    _resizeGrows = grow;
    at(
      t + (grow ? tuning.growDelay : tuning.shrinkDelay),
      (double s) => _rootHeight.retarget(
        s,
        _resizeTo,
        spring: grow ? tuning.growSpring : tuning.shrinkSpring,
      ),
      slot: _resizeSlot,
    );
  }

  MenuLayout _layoutOf(int card) =>
      card == 0 || card > _cards.length ? _root : _cards[card - 1].layout;

  /// The progress of the morph at the time the motion was last advanced
  /// to: 0 is the button, 1 the menu.
  ///
  /// The opening spring overshoots, so the value briefly exceeds 1, and
  /// the closing one briefly dips below 0.
  double get progress => _progress.valueAt(_now);

  /// Whether the menu is on screen, opening, open or closing.
  bool get isPresented => _phase != _Phase.idle;

  /// Whether the menu is opening or open.
  bool get isOpen => _phase == _Phase.opening;

  /// Whether the menu is closing.
  bool get isClosing => _phase == _Phase.closing;

  /// Whether closing cards use the carrier's matched glass copy.
  /// In mm-sub-tap the card's original SDF element leaves its material
  /// group 12 ms after the logical close, at the morph's kick; the rows
  /// and the matched glass copy remain in the shrinking carrier.
  bool get cardGlassTransferred =>
      isClosing &&
      _cards.isNotEmpty &&
      _now >= _closeStart + tuning.closeKickDelay;

  /// Visibility of the matched card material during a whole-stack close.
  /// mm-sub-tap's copied key-fill layer follows the carrier spring, with
  /// opacity equal to (window width - 50) / 200 at 120 Hz.
  double get cardMaterialOpacity =>
      cardGlassTransferred ? _cardContainer.valueAt(_now).clamp(0.0, 1.0) : 1;

  /// Whether a tap's release has scheduled the opening and the menu is
  /// not on its way yet.
  ///
  /// A touch that lands anywhere in this window belongs to the menu, as
  /// on iOS: it is held until the menu opens, and a release that came
  /// before then is applied at the opening - on a row it selects the row,
  /// outside the menu it closes the menu again
  /// [MenuTuning.earlyCloseDelay] after the opening.
  bool get isOpenPending => _openPending;

  /// Whether the menu is not shown yet but a touch may open it: a finger
  /// held on the button, or a tap's opening pending.
  bool get isArming =>
      _phase == _Phase.idle &&
      (_openPending || (_pointer?.fromButton ?? false));

  /// The frame of the open menu at the time the motion was last advanced
  /// to; its height follows resizes and submenu cards.
  Rect get menuRect => _frameAt(_now);

  /// The swing at which a card's progress and the card container rest.
  /// NEAR: a card lands by up to 0.001 of its travel (0.25 pt on a 250 pt
  /// menu), looser than [MotionRest.length]; resting at 0.1 pt adds five
  /// frames of captured glass to the menu-card perf scene.
  static const double _cardRest = 1e-3;

  /// The visible rest ([MotionRest], NEAR) of the progresses that grow the
  /// menu, its corners and its cards out of the button: a swing below it
  /// moves no edge of the open menu by [MotionRest.length] and changes no
  /// fade by [MotionRest.opacity].
  double get _progressRest => math.min(
    MotionRest.opacity,
    MotionRest.scale(math.max(tuning.menuWidth, _rootHeight.target)),
  );

  Rect _frameAt(double t) {
    final h = _rootHeight.valueAt(t) + _cardsExtra(t);
    var top = _down ? _anchor : _anchor - h;
    final maxBottom = _bounds.height - _padding.bottom;
    top = math.max(_padding.top, math.min(top, maxBottom - h));
    return Rect.fromLTWH(_left, top, tuning.menuWidth, h);
  }

  void _dropCards(int from) {
    while (_cards.length > from) {
      _dropCard(_cards.removeLast());
    }
  }

  void _dropCard(_Card card) {
    disown(card.progress);
    disown(card.flex);
  }

  double _cardsExtra(double t) {
    var reach = _rootHeight.target;
    var extra = 0.0;
    for (final card in _cards) {
      final bottom = card.top + math.min(card.layout.height, _cap);
      if (bottom > reach) {
        extra += (bottom - reach) * card.progress.valueAt(t);
        reach = bottom;
      }
    }
    return extra;
  }

  double _headerCenter(MenuLayout layout) {
    for (final element in layout.elements) {
      if (element.kind == MenuPlacedKind.cardHeader) {
        return element.rect.center.dy;
      }
    }
    return 0;
  }

  double _cardFadeProgress(double t) =>
      _phase == _Phase.idle ? 1 : _progress.valueAt(t + tuning.fadeLead);

  double _clampCardTop(double top, double height) {
    final cap = math.max(_cap, _rootHeight.target);
    return math.max(0, math.min(top, cap - math.min(height, _cap)));
  }

  double _scaleUnder(int card, double t) {
    var scale = 1.0;
    for (var k = card; k < _cards.length; k++) {
      final q = _cards[k].progress.valueAt(t);
      scale *= 1 - (1 - tuning.parentScale) * q;
    }
    return scale;
  }

  /// The cards of the menu, the root list first.
  List<MenuCard> get cards {
    final t = _now;
    final result = <MenuCard>[];
    final count = _cards.length;
    for (var i = 0; i <= count; i++) {
      final scale = _scaleUnder(i, t);
      final above = i < count ? _cards[i].progress.valueAt(t) : 0.0;
      final opacity = (1 - (1 - tuning.parentRowOpacity) * above).clamp(
        0.0,
        1.0,
      );
      if (i == 0) {
        result.add(
          MenuCard(
            layout: _root,
            rect: Rect.fromLTWH(0, 0, tuning.menuWidth, _root.height),
            scale: scale,
            rowOpacity: opacity,
            progress: 1,
          ),
        );
        continue;
      }
      final card = _cards[i - 1];
      final q = card.progress.valueAt(t);
      final to = Rect.fromLTWH(
        0,
        card.top,
        tuning.menuWidth,
        math.min(card.layout.height, _cap),
      );
      final rect = Rect.lerp(card.from, to, q)!;
      final parent = result[i - 1];
      final targets = parent.layout.targets;
      final row = card.source < targets.length
          ? parent.rect.top +
                targets[card.source].rect.center.dy -
                (i == 1 ? scrollOffset : 0)
          : card.from.center.dy;
      final ratio = scale == 0 ? 1.0 : parent.scale / scale;
      final onRow = ratio * row - _headerCenter(card.layout);
      final contentTop = onRow + (card.top - onRow) * q;
      final c = q.clamp(0.0, 1.0);
      final from = card.backFrom.clamp(1e-6, 1.0);
      result.add(
        MenuCard(
          layout: card.layout,
          rect: rect,
          scale: scale,
          rowOpacity: opacity,
          progress: q,
          contentTop: contentTop - rect.top,
          rowsOpacity: card.backing
              ? _ramp(c, tuning.cardRowsFadeOut * from, from)
              : _ramp(c, 0, tuning.cardRowsFadeIn),
          platterOpacity: math.sqrt(_ramp(c, 0, tuning.cardPlatterFade)),
          headerBold: card.backing
              ? _ramp(c, tuning.cardHeaderBoldBack * from, from)
              : _ramp(c, tuning.cardHeaderBoldStart, tuning.cardHeaderBoldEnd),
          chevronTurn: card.backing
              ? _ramp(c, tuning.cardChevronBack * from, from)
              : _ramp(c, 0, tuning.cardChevronTurn),
          closeOpacity: i == count ? _cardFade.at(_cardFadeProgress(t)) : 1,
          backing: card.backing,
          source: card.source,
        ),
      );
    }
    return result;
  }

  /// Whether the menu opens below the button; otherwise it opens above it
  /// and its content is reversed.
  bool get opensDown => _down;

  /// The scale of the button's press growth.
  double get pressScale => _press.scaleAt(_now);

  /// The highlighted target of [highlightedCard] - under the finger, or
  /// the chosen one while the menu closes.
  int? get highlighted => _highlighted;

  /// Whether the held button's finger is sliding through the menu.
  bool get isSliding => _pointer?.openedByHold ?? false;

  /// The card [highlighted] belongs to, 0 for the root list.
  int get highlightedCard => _highlightCard;

  void _setHighlight(int? target, int card, {bool tracked = false}) {
    if (target == _highlighted && card == _highlightCard) return;
    final from = _targetOf(_highlightCard, _highlighted);
    _highlighted = target;
    _highlightCard = card;
    unschedule(_dwellSlot);
    final to = _targetOf(card, target);
    if (from != null || to != null || tracked) {
      _emit(MenuHighlightChanged(_now, from, to, tracked: tracked));
    }
  }

  MenuTarget? _targetOf(int card, int? index) {
    if (index == null) return null;
    final targets = _layoutOf(card).targets;
    return index < targets.length ? targets[index] : null;
  }

  /// The glow under a finger on the menu, centered in the motion's
  /// coordinates, or null while it does not show.
  GlassTouchGlow? get touchGlow => _touchGlow.glow;

  /// [touchGlow] on the root list: while a card is on top, the finger lights
  /// the card.
  GlassTouchGlow? get rootGlow => _topCard == 0 ? touchGlow : null;

  /// [touchGlow] on card [index], in the card's own coordinates, while it is
  /// the top card.
  GlassTouchGlow? cardGlow(int index) {
    final glow = touchGlow;
    if (glow == null || index == 0 || index != _topCard) return null;
    return GlassTouchGlow(
      wash: glow.wash,
      center: _unflexed(glow.center) - _cardFrame(_cards[index - 1]).topLeft,
      radius: glow.radius,
      spot: glow.spot,
    );
  }

  Rect _cardFrame(_Card card) {
    final frame = menuRect;
    return Rect.fromLTWH(
      frame.left,
      frame.top + card.top,
      tuning.menuWidth,
      math.min(card.layout.height, _cap),
    );
  }

  /// The flex of card [index] under a finger: the shift of its center and
  /// the growth of its width and height. Its content rides it 1:1.
  ({Offset shift, double width, double height}) cardFlex(int index) {
    if (index == 0 || index > _cards.length) return _noFlex;
    final card = _cards[index - 1];
    return _flexIn(card.flex, _cardFrame(card), _now);
  }

  final List<MenuEvent> _events = [];

  void _emit(MenuEvent event) => _events.add(event);

  /// The events raised since the last call, oldest first.
  List<MenuEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final drained = List<MenuEvent>.of(_events);
    _events.clear();
    return drained;
  }

  /// The opacity of the menu content.
  double get contentOpacity => _contentOpacityAt(_now);

  double _contentOpacityAt(double t) {
    if (_phase == _Phase.idle) {
      return _ramp(
        _progress.valueAt(t),
        tuning.contentFadeStart,
        tuning.contentFadeEnd,
      );
    }
    return _contentFade.at(_progress.valueAt(t + tuning.fadeLead));
  }

  void _fade(
    double t, {
    required double from,
    required bool opening,
    bool fresh = false,
  }) {
    final p = _progress.valueAt(t + tuning.fadeLead);
    _contentFade = Ramp(
      from: from,
      to: opening ? 1 : 0,
      start: opening && fresh ? tuning.contentFadeStart : p,
      end: opening
          ? tuning.contentFadeEnd
          : _closeEnd(p, tuning.contentCloseFadeEnd),
    );
  }

  /// The blur radius of the menu content, in logical pixels on screen.
  double get contentBlur => math.max(
    0,
    tuning.contentBlur * (1 - progress) +
        tuning.contentKickBlur * _relativeKick,
  );

  /// The scale of the menu content relative to its final size. Closing
  /// cards use their measured container; other content follows the menu
  /// shape's scale plus its kick.
  ///
  /// The content is placed by [contentRect] at this scale, times
  /// [contentStretch] along each axis. Root rows clip to their platter;
  /// each submenu clips its rows independently.
  double get contentScale {
    if (!_cardContainerActive) return _contentScale(menuBlob);
    final end = (tuning.cardContainerEndWidth / tuning.menuWidth).clamp(
      0.0,
      1.0,
    );
    return end + (1 - end) * _cardContainer.valueAt(_now);
  }

  double _contentScale(MenuBlob menu) =>
      menu.scale + tuning.contentKickScale * _relativeKick;

  /// The frame of the menu content at [contentScale]. Closing cards
  /// contract about the button's center; other content rides [menuBlob].
  ///
  /// A menu taller than it is wide keeps its first row on the shape's top
  /// edge, like a list scrolled to its start, and grows below it; a menu
  /// as wide as it is tall or wider is centered on the shape.
  ///
  /// While a finger flexes the open menu, the frame is stretched with the
  /// shape by [contentStretch].
  Rect get contentRect {
    final rect = _contentRectUnflexed;
    final stretch = _stretch;
    if (stretch == null) return rect;
    final from = stretch.from;
    final to = stretch.to;
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    return Rect.fromLTWH(
      to.left + (rect.left - from.left) * sx,
      to.top + (rect.top - from.top) * sy,
      rect.width * sx,
      rect.height * sy,
    );
  }

  Rect get _contentRectUnflexed {
    if (_cardContainerActive) {
      final frame = menuRect;
      final scale = contentScale;
      final at = _source.origin + (frame.topLeft - _source.origin) * scale;
      return Rect.fromLTWH(
        at.dx,
        at.dy,
        frame.width * scale,
        frame.height * scale,
      );
    }
    final menu = _blobFor(menuRect, flexed: false);
    final frame = menuRect;
    final scale = _contentScale(menu);
    final width = frame.width * scale;
    final height = frame.height * scale;
    final shape = menu.rect;
    _Card? card;
    for (final open in _cards) {
      if (!open.backing) card = open;
    }
    if (card != null) {
      final f = ((1 - progress) / tuning.cardCloseCenter).clamp(0.0, 1.0);
      final middle = frame.height / 2;
      final focus = card.top + math.min(card.layout.height, _cap) / 2;
      final anchor = middle + (focus - middle) * f;
      return Rect.fromLTWH(
        shape.center.dx - width / 2,
        shape.center.dy - anchor * scale,
        width,
        height,
      );
    }
    if (frame.height > frame.width) {
      return Rect.fromLTWH(
        shape.center.dx - width / 2,
        shape.top,
        width,
        height,
      );
    }
    return Rect.fromCenter(center: shape.center, width: width, height: height);
  }

  /// The opacity of the button's look inside the button shape.
  double get buttonLookOpacity =>
      1 - _ramp(_leadingProgress, tuning.lookFadeStart, tuning.lookFadeEnd);

  /// The blur radius of the button's look.
  double get buttonLookBlur => tuning.crossfadeBlur * progress.clamp(0.0, 1.0);

  /// The horizontal stretch of the button's look relative to the button
  /// shape's scale.
  double get buttonLookStretch =>
      1 + tuning.lookStretch * progress.clamp(0.0, 1.0);

  double get _leadingProgress => _phase == _Phase.idle
      ? progress
      : _progress.valueAt(_now + tuning.fadeLead);

  double get _relativeKick {
    final height = menuRect.height;
    return height > 0 ? menuKick / height : 0;
  }

  /// The end a fade that closes from progress [p] lands at: [end], or
  /// nothing left when [p] is already within a twentieth of it.
  static double _closeEnd(double p, double end) => p > end + 0.05 ? end : 0;

  static double _ramp(double value, double from, double to) =>
      ((value - from) / (to - from)).clamp(0.0, 1.0);

  /// The fusion radius: the standard deviation, in pixels, of the
  /// Gaussian blur UIKit applies to the distance field of [menuBlob] and
  /// [buttonBlob] to fuse them into one silhouette; 0 when they are
  /// drawn as their plain union.
  ///
  /// Every open and every close starts its own envelope
  /// ([MenuTuning.fusionEnvelope]); the radius is the largest of the
  /// envelopes still running, limited to
  /// [MenuTuning.fusionRadius], so a reversal never makes it jump.
  double get fusionRadius => _fusions.radiusAt(_now);

  /// The silhouette of [rootBlob] and [buttonBlob] fused at
  /// [fusionRadius], in the motion's coordinates. Below 1 pixel it is
  /// the exact plain union of the two; null only while idle. Its field is
  /// computed when a renderer first reads it.
  GlassOutline? get silhouette {
    if (_phase == _Phase.idle) return null;
    if (!drawsSource) return unionOutline([rootBlob.rrect]);
    final radius = fusionRadius;
    final outline = radius < MenuFusion.minimumRadius
        ? unionOutline([rootBlob.rrect, buttonBlob.rrect])
        : _fusion.outline(rootBlob.rrect, buttonBlob.rrect, radius)!;
    _prefetchSilhouette();
    return outline;
  }

  /// Whether the menu and its source draw as one [silhouette] this frame:
  /// [fusionRadius] blurs them enough to move an edge.
  bool get fused => fusionRadius >= MenuFusion.minimumRadius;

  /// The glass body of the root menu this frame, in the motion's
  /// coordinates: the [silhouette] while [fused]; else the rounded rect
  /// `shape` of [rootBlob] alone (a null `outline`) when no source is
  /// drawn or the menu covers it; else the plain union of the menu and
  /// [buttonBlob] as the `outline`.
  ({RRect shape, GlassOutline? outline}) get rootBody {
    final root = rootBlob.rrect;
    if (fused) return (shape: root, outline: silhouette);
    final source = drawsSource ? buttonBlob.rrect : null;
    if (source == null || encloses(root, source)) {
      return (shape: root, outline: null);
    }
    return (shape: root, outline: unionOutline([root, source]));
  }

  /// Hands the coming frames' fusions to [MenuFusion.prefetch]: the
  /// shapes and radius at the next [MenuFusion.prefetchFrames]
  /// frames' times as the motion stands, the kicks integrated up to each.
  /// A fusion that comes back after the next frame started still serves
  /// the frame after it. The fusions carry the field once a renderer has
  /// read one ([MenuFusion.shades]), and are the edge alone before.
  ///
  /// The coming frames are the nodes of the source clock's frame grid
  /// after the motion's time (the [clock]'s frame time plus multiples of
  /// its frame period), so a frame on the grid asks for exactly the time
  /// it was fused for, and a silhouette read at an event's time between
  /// frames still predicts the frames. Nothing is fused ahead before the
  /// clock has seen steady frames.
  void _prefetchSilhouette() {
    if (!MenuFusion.prefetches) return;
    final period = clock.framePeriod;
    final t = now;
    if (period == null || t == _prefetchedFrom) return;
    _prefetchedFrom = t;
    final frameTime = clock.frameTime;
    var ahead = frameTime + period * ((t - frameTime) / period + 1).floor();
    if (ahead <= t) ahead += period;
    for (var frame = 0; frame < MenuFusion.prefetchFrames; frame++) {
      _prefetchAt(ahead + period * frame);
    }
  }

  void _prefetchAt(double ahead) => _kicks.peek(ahead, () {
    _peekTime = ahead;
    try {
      final radius = fusionRadius;
      if (radius >= MenuFusion.minimumRadius) {
        _fusion.prefetch(rootBlob.rrect, buttonBlob.rrect, radius);
      }
    } finally {
      _peekTime = null;
    }
  });

  // A close that starts near the source kicks it away first, so the source
  // being near says nothing until the kick has come and gone.
  bool _sourceReturned(double t) {
    if (!drawsSource ||
        _cards.isNotEmpty ||
        t - _closeStart < tuning.sourceReturnAfter) {
      return false;
    }
    final rest = _source.shape;
    final shape = buttonBlob.rect;
    final tolerance = tuning.sourceReturnTolerance;
    final bounds = rest.inflate(tolerance);
    final menu = menuBlob.rect;
    return (shape.left - rest.left).abs() <= tolerance &&
        (shape.top - rest.top).abs() <= tolerance &&
        (shape.right - rest.right).abs() <= tolerance &&
        (shape.bottom - rest.bottom).abs() <= tolerance &&
        bounds.contains(menu.topLeft) &&
        bounds.contains(menu.bottomRight);
  }

  bool _fusionAtRest(double t) {
    if (!_fusions.endedAt(t)) return false;
    _fusion.settle();
    return true;
  }

  /// The vertical kick of the menu shape, positive toward the side the
  /// menu opens to.
  double get menuKick => _kicks.menu.value;

  /// The vertical kick of the button shape, positive toward the side the
  /// menu opens to.
  double get buttonKick => _kicks.button.value;

  /// The menu shape: grows out of the button into the menu.
  MenuBlob get menuBlob => _blobFor(menuRect);

  MenuBlob _blobFor(
    Rect frame, {
    double parentScale = 1,
    bool flexed = true,
  }) {
    if (_attachment != null) {
      return _attachedBlobFor(frame, parentScale: parentScale, flexed: flexed);
    }
    final p = progress;
    final w = frame.width;
    final h = frame.height;
    final s0 = 0.5 * _source.height / math.max(w, h);
    final scale = s0 + (1 - s0) * p;
    final localHeight = w + (h - w) * p;
    final from = _source.origin;
    final to = frame.center;
    final sign = _down ? 1.0 : -1.0;
    final flex = flexed ? _flexAt(_now) : _noFlex;
    final center = Offset(
      from.dx + (to.dx - from.dx) * p + flex.shift.dx,
      from.dy + (to.dy - from.dy) * p + sign * menuKick + flex.shift.dy,
    );
    return MenuBlob(
      rect: Rect.fromCenter(
        center: center,
        width: w * scale + flex.width,
        height: localHeight * scale + flex.height,
      ),
      radius: _localRadius(p, localHeight, h) * parentScale * scale,
      scale: scale,
      localSize: Size(w, localHeight),
    );
  }

  /// A context menu's shape: a straight line on the progress from the blob
  /// at the held view's center to [frame], flexed by the finger on it, its
  /// corners from the blob's capsule to the menu's.
  MenuBlob _attachedBlobFor(
    Rect frame, {
    required double parentScale,
    required bool flexed,
  }) {
    final p = progress;
    final from = _blob;
    final flex = flexed ? _flexAt(_now) : _noFlex;
    final to = Rect.fromCenter(
      center: frame.center + flex.shift,
      width: frame.width + flex.width,
      height: frame.height + flex.height,
    );
    final rect = Rect.lerp(from, to, p)!;
    final width = from.width + (frame.width - from.width) * p;
    final height = from.height + (frame.height - from.height) * p;
    final scale = frame.width > 0 ? width / frame.width : 1.0;
    final fromRadius = math.min(from.width, from.height) / 2;
    final toRadius =
        math.min(tuning.cornerRadius, frame.height / 2) * parentScale;
    final radius = fromRadius + (toRadius - fromRadius) * p.clamp(0.0, 1.0);
    return MenuBlob(
      rect: rect,
      radius: math.max(
        0,
        math.min(radius, math.min(rect.width, rect.height) / 2),
      ),
      scale: scale,
      localSize: Size(frame.width, scale > 0 ? height / scale : frame.height),
    );
  }

  static const ({Offset shift, double width, double height}) _noFlex = (
    shift: Offset.zero,
    width: 0,
    height: 0,
  );

  /// The menu shape without the flex (`from`) and with it (`to`), or null
  /// while nothing flexes it. The content and the hit testing follow the
  /// one affine map that takes `from` onto `to`.
  ({Rect from, Rect to})? get _stretch {
    final flex = _flexAt(_now);
    if (flex.shift == Offset.zero && flex.width == 0 && flex.height == 0) {
      return null;
    }
    final from = _blobFor(menuRect, flexed: false).rect;
    if (from.width <= 0 || from.height <= 0) return null;
    return (from: from, to: menuBlob.rect);
  }

  /// How much the flex of the open menu stretches its content along each
  /// axis on top of [contentScale]: the content fills the flexed
  /// [menuBlob] as it fills the shape without the flex, the one stretch,
  /// about the same anchor and with the same shift as the shape's, so
  /// rows, icons, the highlight, headers and submenu cards ride the
  /// shape 1:1 while a finger stretches and pulses it. (1, 1)
  /// while nothing flexes the menu.
  ///
  /// The flex keeps the shape a rectangle, so the map is exact for its
  /// frame; the corners keep their radius while the content in them
  /// stretches by at most a few percent (NEAR).
  Offset get contentStretch {
    final stretch = _stretch;
    if (stretch == null) return const Offset(1, 1);
    return Offset(
      stretch.to.width / stretch.from.width,
      stretch.to.height / stretch.from.height,
    );
  }

  /// [position] mapped back through the flex: where the unflexed menu has
  /// what the flexed one shows at [position].
  Offset _unflexed(Offset position) {
    final stretch = _stretch;
    final inMenu = stretch == null
        ? position
        : _mapped(position, stretch.to, stretch.from);
    final top = _topCard;
    if (top == 0) return inMenu;
    final flex = cardFlex(top);
    if (identical(flex, _noFlex)) return inMenu;
    final from = _cardFrame(_cards[top - 1]);
    final to = Rect.fromCenter(
      center: from.center + flex.shift,
      width: from.width + flex.width,
      height: from.height + flex.height,
    );
    return _mapped(inMenu, to, from);
  }

  static Offset _mapped(Offset position, Rect from, Rect to) => Offset(
    to.left + (position.dx - from.left) * to.width / from.width,
    to.top + (position.dy - from.top) * to.height / from.height,
  );

  /// What the flex's pulse channel ([MenuTuning.flexPulseSpring])
  /// last published: its value and its velocity per second of its own
  /// clock.
  @visibleForTesting
  ({double value, double velocity}) get flexPulse => _flex.pulse;

  /// [menuRect] flexed by the finger on the menu, without the morph from
  /// the button: the frame UIKit's `_UIContextMenuListView` takes.
  @visibleForTesting
  Rect get flexedMenuRect {
    final frame = menuRect;
    final flex = _flexAt(_now);
    return Rect.fromCenter(
      center: frame.center + flex.shift,
      width: frame.width + flex.width,
      height: frame.height + flex.height,
    );
  }

  /// The flex of the open menu under a finger at time [t]: the shift of
  /// its center and the growth of its width and height.
  ///
  /// The menu takes the scales and drifts of [MenuFlex.valuesAt]: its width
  /// and height scale about the center across and about the edge facing
  /// the button along the vertical, which the vertical drift moves.
  ({Offset shift, double width, double height}) _flexAt(double t) =>
      _flexIn(_flex, menuRect, t);

  ({Offset shift, double width, double height}) _flexIn(
    MenuFlex list,
    Rect frame,
    double t,
  ) {
    final d = list.valuesAt(t);
    if (d.scaleX == 1 && d.scaleY == 1 && d.driftX == 0 && d.driftY == 0) {
      return _noFlex;
    }
    final side = _down ? 1.0 : -1.0;
    final grow = frame.height * (d.scaleY - 1);
    return (
      shift: Offset(d.driftX, d.driftY + side * grow / 2),
      width: frame.width * (d.scaleX - 1),
      height: grow,
    );
  }

  /// The root list's glass shape, scaled about its top center by
  /// [MenuTuning.parentScale] per open card, independently of the vessel
  /// that holds the whole stack; [menuBlob] while no card is open.
  MenuBlob get rootBlob {
    if (_cards.isEmpty) return menuBlob;
    final frame = menuRect;
    final parentScale = _scaleUnder(0, _now);
    final root = Rect.fromLTWH(
      frame.left + frame.width * (1 - parentScale) / 2,
      frame.top,
      frame.width * parentScale,
      visibleRootHeight * parentScale,
    );
    return _blobFor(root, parentScale: parentScale);
  }

  /// The button shape: shrinks into the menu.
  MenuBlob get buttonBlob {
    final p = progress;
    final from = _sourceScaleAt(_now);
    final scale = from + (tuning.sourceEndScale - from) * p;
    final start = _source.shape.center;
    final grows = _source.origin;
    final end = grows + (menuRect.center - grows) * tuning.sourceTravel;
    final sign = _down ? 1.0 : -1.0;
    final center = start + (end - start) * p + Offset(0, sign * buttonKick);
    final size = _source.shape.size * scale;
    final endWidth =
        (_source is MenuCapsuleSource
            ? _source.shape.height
            : _source.shape.width) *
        tuning.sourceEndScale;
    final startWidth = _source.shape.width * from;
    return MenuBlob(
      rect: Rect.fromCenter(
        center: center,
        width: startWidth + (endWidth - startWidth) * p,
        height: size.height,
      ),
      radius: math.min(
        math.min(size.width, size.height) / 2,
        (_source.radius ?? double.infinity) * scale,
      ),
      scale: scale,
      localSize: _source.shape.size,
    );
  }

  /// Whether something besides the parts keeps the motion awake: a finger
  /// scrolling the content, a close under way, or the fusion of the open
  /// menu still turning.
  ///
  /// A finger resting on the menu or its button does not keep it awake once
  /// the glow under it has faded in: its next move or release wakes it.
  @override
  bool get holds {
    if (_pointer?.scrolled ?? false) return true;
    return switch (_phase) {
      _Phase.closing => true,
      _Phase.opening => !_fusionAtRest(_now),
      _Phase.idle => false,
    };
  }

  /// The motion time of the next pending event while a finger rests and
  /// nothing else moves, or null otherwise.
  ///
  /// Until that time every frame shows the same picture, so the clock
  /// driving the motion may doze until then instead of advancing it. Only
  /// a resting finger waits long (a submenu opens after
  /// [MenuTuning.hoverOpenDelay]); the reactions to a release come
  /// due within a few frames, which keep coming, so a test's
  /// `pumpAndSettle` still sees them through.
  @override
  double? get wakeTime => _pointer != null ? super.wakeTime : null;

  /// The target at [position] on the top card, or null.
  ///
  /// [position] is where the target shows: the hit testing follows the
  /// content through the flex ([contentStretch]).
  int? rowAt(Offset position) => _hitAt(position).target;

  /// Where target [index] of the top card shows, through the root list's
  /// scroll and the flex: the box a finger at any point of it hits
  /// ([rowAt]), for the keyboard focus, the mouse and accessibility. Null
  /// while the menu is not open or the top card has no such target.
  Rect? targetRect(int index) {
    if (_phase != _Phase.opening) return null;
    final top = _topCard;
    final targets = _layoutOf(top).targets;
    if (index < 0 || index >= targets.length) return null;
    final frame = menuRect;
    final origin = top == 0
        ? frame.topLeft - Offset(0, scrollOffset)
        : frame.topLeft + cards[top].rect.topLeft;
    final rect = targets[index].rect.shift(origin);
    return Rect.fromPoints(_flexed(rect.topLeft), _flexed(rect.bottomRight));
  }

  /// Whether [position], where it shows, lies on the menu beside its top
  /// submenu card: where a finger lifted sends the card back.
  bool isBesideCard(Offset position) =>
      _phase == _Phase.opening && _topCard > 0 && _hitAt(position).beside;

  /// Whether [position], where it shows, lies on the top submenu card.
  bool isOnCard(Offset position) {
    if (_phase != _Phase.opening || _topCard == 0) return false;
    final hit = _hitAt(position);
    return !hit.beside && _onMenu(position);
  }

  /// Whether [position] is on the menu as it shows, flexed.
  bool _onMenu(Offset position) => menuRect.contains(_unflexed(position));

  /// [position] in the unflexed menu mapped through the flex: where the
  /// flexed menu shows it; the inverse of [_unflexed].
  Offset _flexed(Offset position) {
    var shown = position;
    final top = _topCard;
    if (top > 0) {
      final flex = cardFlex(top);
      if (!identical(flex, _noFlex)) {
        final from = _cardFrame(_cards[top - 1]);
        final to = Rect.fromCenter(
          center: from.center + flex.shift,
          width: from.width + flex.width,
          height: from.height + flex.height,
        );
        shown = _mapped(shown, from, to);
      }
    }
    final stretch = _stretch;
    return stretch == null ? shown : _mapped(shown, stretch.from, stretch.to);
  }

  MenuFlex get _topFlex {
    final top = _topCard;
    return top == 0 ? _flex : _cards[top - 1].flex;
  }

  ({int card, int? target, bool beside}) _hitAt(Offset shown) {
    final position = _unflexed(shown);
    final top = _topCard;
    if (_phase == _Phase.idle) return (card: top, target: null, beside: false);
    final frame = menuRect;
    if (!frame.contains(position)) {
      return (card: top, target: null, beside: false);
    }
    final local = position - frame.topLeft;
    if (top > 0) {
      final card = cards[top];
      if (!card.rect.contains(local)) {
        return (card: top, target: null, beside: true);
      }
      return (
        card: top,
        target: card.layout.targetAt(local - card.rect.topLeft),
        beside: false,
      );
    }
    return (
      card: 0,
      target: _root.targetAt(local + Offset(0, scrollOffset)),
      beside: false,
    );
  }

  bool _onWidgetRow(Offset shown) {
    final position = _unflexed(shown);
    final frame = menuRect;
    if (!frame.contains(position)) return false;
    final local = position - frame.topLeft;
    final top = _topCard;
    final card = cards[top];
    final at = top == 0
        ? local + Offset(0, scrollOffset)
        : local - card.rect.topLeft;
    return card.layout.elements.any(
      (MenuPlaced element) =>
          element.kind == MenuPlacedKind.widget && element.rect.contains(at),
    );
  }

  /// The index in [cards] of the card that takes the highlight and the
  /// choice: the newest one that is not on its way back.
  @internal
  int get topCard => _topCard;

  int get _topCard {
    var top = _cards.length;
    while (top > 0 && _cards[top - 1].backing) {
      top--;
    }
    return top;
  }

  /// Opens the menu at time [t].
  ///
  /// [sourceScale] is the button's scale at that moment, which sizes the
  /// frame the menu aligns to; it defaults to the current press scale.
  @override
  void open(double t, {double? sourceScale}) {
    _take(t);
    _open(t, sourceScale: sourceScale);
  }

  /// Where the menu stands: shown once its open has come to rest, leaving
  /// from its close until the source's shape is back
  /// ([MenuTuning.sourceReturnTolerance]), or, for a menu without a source
  /// shape, until nothing of it moves.
  @override
  PresenceStatus get presence => switch (_phase) {
    _Phase.opening =>
      _progress.restsAt(_now, _progressRest)
          ? PresenceStatus.shown
          : PresenceStatus.opening,
    _Phase.closing => PresenceStatus.leaving,
    _Phase.idle =>
      _returned || isSettled ? PresenceStatus.hidden : PresenceStatus.leaving,
  };

  /// Closes the menu at time [t] for any [trigger]; a menu already on its
  /// way out keeps going.
  @override
  bool leave(double t, DismissTrigger trigger) {
    if (_phase == _Phase.opening) close(t);
    return presence != PresenceStatus.hidden;
  }

  /// Closes the menu at time [t].
  void close(double t) {
    changed();
    _openPending = false;
    unscheduleAll();
    _press.unscheduleAll();
    _flex.unscheduleAll();
    for (final card in _cards) {
      card.flex.unscheduleAll();
    }
    _pointer = null;
    advance(t);
    _close(t);
  }

  /// Chooses target [index] of the top card at time [t] as a release on
  /// it would.
  void select(double t, int index) {
    _take(t);
    if (_phase != _Phase.opening) return;
    final card = _topCard;
    if (index < 0 || index >= _layoutOf(card).targets.length) return;
    _select(t, card, index);
  }

  /// Highlights target [index] of the top card at time [t], as a finger
  /// or the keyboard would; null clears the highlight.
  void highlight(double t, int? index) {
    _take(t);
    if (_phase != _Phase.opening) return;
    _setHighlight(index, _topCard);
  }

  /// Sends the top submenu card back into its row at time [t]; returns
  /// whether there was one.
  bool back(double t) {
    _take(t);
    if (_phase != _Phase.opening || _topCard == 0) return false;
    _back(t);
    return true;
  }

  /// Opens the menu at time [t] under a finger that has held its source
  /// and rests at [position]: the finger then slides onto a row and
  /// chooses it on release, as after a held button's opening, and a
  /// release before it left the source (a context menu's preview) keeps
  /// the menu open.
  void holdOpen(double t, Offset position) {
    _take(t);
    final pointer = _Pointer(
      fromButton: true,
      position: position,
    );
    pointer.openedByHold = true;
    _pointer = pointer;
    _open(t);
  }

  /// A finger touched down at [position].
  void pointerDown(double t, Offset position) {
    _take(t);
    if (_pointer != null) return;
    if (_phase == _Phase.opening) {
      final pointer = _Pointer(
        fromButton: false,
        position: position,
      );
      _pointer = pointer;
      if (_onWidgetRow(position)) {
        pointer.scrolled = true;
        return;
      }
      pointer.startedOnParent = _hitAt(position).beside;
      pointer.touchesTopList = _onMenu(position) && !pointer.startedOnParent;
      if (!pointer.touchesTopList) {
        pointer.start = position;
        return;
      }
      _track(t, pointer, position);
      _lightGlow(t, position);
      final flex = pointer.flex = _topFlex;
      flex.down(t, position);
      return;
    }
    if (_openPending) {
      _pointer = _Pointer(
        fromButton: false,
        position: position,
      );
      return;
    }
    if (!_source.touches.contains(position)) return;
    final pointer = _Pointer(
      fromButton: true,
      position: position,
    );
    _pointer = pointer;
    _press.pointerDown(t, position - _source.shape.topLeft);
    at(t + tuning.holdDuration, (double s) {
      if (!identical(_pointer, pointer) ||
          _phase == _Phase.opening ||
          pointer.holdForfeited) {
        return;
      }
      pointer.openedByHold = true;
      _open(s);
    });
  }

  void _track(double t, _Pointer pointer, Offset position) {
    if (pointer.scrolled) return;
    final hit = _hitAt(position);
    final moved =
        hit.target != null &&
        (hit.target != _highlighted || hit.card != _highlightCard);
    _setHighlight(hit.target, hit.card, tracked: moved);
    final target = _targetOf(hit.card, hit.target);
    if (target == null || target.kind != MenuTargetKind.submenu) return;
    final card = hit.card;
    final index = hit.target!;
    at(t + tuning.hoverOpenDelay, (double s) {
      if (identical(_pointer, pointer)) _openCard(s, card, index);
    }, slot: _dwellSlot);
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    _take(t);
    final pointer = _pointer;
    if (pointer == null) return;
    final previous = pointer.position;
    pointer.position = position;
    if (pointer.fromButton && !_holdArea.contains(position)) {
      pointer.leftButton = true;
      if (!pointer.openedByHold &&
          !_source.touches.inflate(tuning.tapSlop).contains(position)) {
        pointer.holdForfeited = true;
      }
    }
    if (_phase != _Phase.opening || pointer.scrolled) return;
    if (!pointer.touchesTopList) {
      if (!pointer.startedOnParent &&
          (position - pointer.start).distance >= MenuTuning.outsideMoveClose) {
        _close(t);
      }
      return;
    }
    final hit = _hitAt(position);
    if (hit.target != _highlighted || hit.card != _highlightCard) {
      _track(t, pointer, position);
    }
    // A finger that held the menu open lights it once it moves (device:
    // none under a still hold).
    if (_touchGlow.isDown) {
      _touchGlow.pointerMove(t, position);
    } else {
      _lightGlow(t, position);
    }
    final flex = pointer.flex ??= _topFlex;
    if (!flex.isTouched) flex.down(t, previous);
    flex.move(t, position);
  }

  /// The finger on the menu started to scroll its content: it no longer
  /// chooses anything.
  void pointerScrolled(double t) {
    _take(t);
    final pointer = _pointer;
    if (pointer == null || pointer.scrolled) return;
    pointer.scrolled = true;
    _setHighlight(null, _highlightCard);
    _relax(t);
  }

  /// The finger lifted at [position].
  void pointerUp(double t, Offset position) {
    _take(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    pointer.position = position;
    _relax(t);
    if (pointer.fromButton) {
      _press.release(t);
      if (!pointer.openedByHold) {
        final inside = _source.touches
            .inflate(tuning.tapSlop)
            .contains(position);
        if (!opensOnTap) {
          if (_phase != _Phase.opening && inside) _emit(MenuTapped(t));
          return;
        }
        if (_phase != _Phase.opening && inside) {
          _openPending = true;
          at(t + tuning.tapOpenDelay, _open);
        }
        return;
      }
    }
    if (_phase != _Phase.opening) {
      if (_openPending) _earlyRelease = (t: t, position: position);
      return;
    }
    if (pointer.scrolled) return;
    if (!pointer.touchesTopList) {
      if (!pointer.startedOnParent) {
        at(t + tuning.dismissDelay, _close);
      } else if (_hitAt(position).beside) {
        at(t + tuning.backDelay, _back);
      }
      return;
    }
    if (pointer.fromButton && !pointer.leftButton) {
      _setHighlight(null, _highlightCard);
      return;
    }
    final hit = _hitAt(position);
    final target = hit.target;
    if (target != null) {
      _select(t, hit.card, target);
      return;
    }
    _setHighlight(null, _highlightCard);
    if (hit.beside) {
      at(t + tuning.backDelay, _back);
    } else if (!pointer.fromButton && _topCard == 0 && !_onMenu(position)) {
      at(t + tuning.dismissDelay, _close);
    }
  }

  /// Opens the menu as a tap released on the source at [t] does when the
  /// tap opens it ([opensOnTap]): after [MenuTuning.tapOpenDelay]. For an
  /// owner that heard [MenuTapped] and whose source's tap opens the menu.
  void openAfterTap(double t) {
    _take(t);
    if (_phase == _Phase.opening || _openPending) return;
    _openPending = true;
    at(t + tuning.tapOpenDelay, _open);
  }

  /// The touch was cancelled.
  void pointerCancel(double t) {
    _take(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    _relax(t);
    if (_phase == _Phase.opening) _setHighlight(null, _highlightCard);
    if (pointer.fromButton) _press.release(t);
  }

  // A command advances to its time and tells the selections it may have
  // changed what they read, the flags of the layout and the highlight
  // included.
  void _take(double t) {
    advance(t);
    changed();
  }

  @override
  void didAdvance(double t) {
    for (var i = _cards.length - 1; i >= 0; i--) {
      final card = _cards[i];
      if (card.backing && card.progress.valueAt(t) < tuning.cardGone) {
        _dropCard(_cards.removeAt(i));
      }
    }
    final returned = _phase == _Phase.closing && _sourceReturned(t);
    if (returned) {
      _returned = true;
      _fusions.clear();
      _fusion.settle();
      _progress.snap(t, 0);
    }
    if (returned ||
        (_phase == _Phase.closing &&
            _progress.restsAt(t, _progressRest) &&
            _kicks.menu.isAtRest &&
            _kicks.button.isAtRest &&
            _fusionAtRest(t))) {
      _phase = _Phase.idle;
      _highlighted = null;
      _highlightCard = 0;
      _dropCards(0);
      _cardContainerActive = false;
      scrollOffset = 0;
      _kicks.menu.reset();
      _kicks.button.reset();
      _openReference = null;
      _closeReference = null;
    }
  }

  /// The final frame of a menu of [size] opened from a button whose frame
  /// at its current scale is [button], inside [bounds] minus [padding].
  ///
  /// The menu opens downward with its top on the button's top when the
  /// button's center is in the upper half of the safe area, and upward with its
  /// bottom on the button's bottom otherwise. It is centered on the button
  /// when that keeps [edgeMargin] from the safe area's sides, and aligns
  /// with the button's nearer edge otherwise; the result is then clamped
  /// into the safe area.
  static ({Rect rect, bool down}) place({
    required Rect button,
    required Size size,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    double edgeMargin = MenuTuning.defaultEdgeMargin,
  }) {
    final down =
        button.center.dy <= (padding.top + bounds.height - padding.bottom) / 2;
    final minLeft = padding.left;
    final maxRight = bounds.width - padding.right;
    var left = button.center.dx - size.width / 2;
    if (left < minLeft + edgeMargin ||
        left + size.width > maxRight - edgeMargin) {
      left = button.center.dx < bounds.width / 2
          ? button.left
          : button.right - size.width;
    }
    left = math.max(minLeft, math.min(left, maxRight - size.width));
    var top = down ? button.top : button.bottom - size.height;
    final maxBottom = bounds.height - padding.bottom;
    top = math.max(padding.top, math.min(top, maxBottom - size.height));
    return (
      rect: Rect.fromLTWH(left, top, size.width, size.height),
      down: down,
    );
  }

  /// The final frame of a context menu of [size] attached to
  /// [attachment] inside [bounds] minus [padding], whether it stands below
  /// the preview, and how far the preview moves with it.
  ///
  /// The menu stands [MenuAttachment.gap] below the preview when the
  /// preview, its accessory and the menu fit inside the safe area minus
  /// [MenuAttachment.margin] that way, above it when they fit that
  /// way, and below it otherwise, the preview and the menu then shifting
  /// together. If their whole column cannot fit, the preview stays inside
  /// the safe top and the menu overlaps it at the safe bottom. Across, the menu
  /// centers on the preview when that keeps [edgeMargin] from the safe
  /// area and aligns with the preview's nearer edge otherwise; a preview
  /// that leaves the safe area moves back into it.
  static ({Rect rect, bool down, Offset shift}) placeAttached({
    required MenuAttachment attachment,
    required Size size,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    double edgeMargin = MenuTuning.defaultEdgeMargin,
  }) {
    final preview = attachment.preview;
    final gap = attachment.gap;
    final margin = attachment.margin;
    final top = padding.top + margin;
    final bottom = bounds.height - padding.bottom - margin;
    final left = padding.left + margin;
    final right = bounds.width - padding.right - margin;
    final columnTop = preview.top - attachment.accessory;
    final below = preview.bottom + gap + size.height;
    final above = columnTop - gap - size.height;
    var down = true;
    var dy = 0.0;
    if (columnTop >= top && below <= bottom) {
      down = true;
    } else if (above >= top && preview.bottom <= bottom) {
      down = false;
    } else {
      dy = math.min(0, bottom - below);
      if (columnTop + dy < top) dy = top - columnTop;
    }
    var dx = 0.0;
    if (preview.right > right) dx = right - preview.right;
    if (preview.left + dx < left) dx = left - preview.left;
    final shifted = preview.shift(Offset(dx, dy));
    var x = shifted.center.dx - size.width / 2;
    final minLeft = padding.left + edgeMargin;
    final maxRight = bounds.width - padding.right - edgeMargin;
    if (x < minLeft || x + size.width > maxRight) {
      x = shifted.center.dx < bounds.width / 2
          ? shifted.left
          : shifted.right - size.width;
    }
    x = math.max(left, math.min(x, right - size.width));
    final y = down
        ? math.min(shifted.bottom + gap, bottom - size.height)
        : shifted.top - attachment.accessory - gap - size.height;
    return (
      rect: Rect.fromLTWH(x, y, size.width, size.height),
      down: down,
      shift: Offset(dx, dy),
    );
  }

  /// The opening kick's amplitude relative to a 146-pixel menu, for a
  /// menu [height] pixels tall; it scales [MenuTuning.openKickGain].
  static double kickAmplitude(double height) =>
      _interpolate(_kickAmplitude, height);

  static double _interpolate(List<(double, double)> table, double height) {
    if (height <= table.first.$1) return table.first.$2;
    for (var i = 1; i < table.length; i++) {
      final (h1, a1) = table[i];
      if (height <= h1) {
        final (h0, a0) = table[i - 1];
        return a0 + (a1 - a0) * (height - h0) / (h1 - h0);
      }
    }
    return table.last.$2;
  }

  /// One frame of the kicks at time [t]; answers whether they need
  /// another.
  bool _stepKicks(double t, _DrivenKick menu, _DrivenKick button) {
    if (_phase == _Phase.idle || !tuning.morph.kicks) return false;
    const h = MenuTuning.kickIntegrationStep;
    final mid = t - h / 2;
    final opening = _phase == _Phase.opening;
    final open = opening ? _openReference : null;
    final close = _closeReference;
    menu.integrate(
      h,
      opening ? tuning.openKickSpring : tuning.closeKickSpring,
      open == null
          ? 0
          : tuning.openKickGain * _amplitude * open.velocityAt(mid),
    );
    button.integrate(
      h,
      tuning.sourceKickSpring,
      close == null
          ? 0
          : tuning.sourceKickGain * _sourceAmplitude * close.velocityAt(mid),
    );
    return !(menu.isAtRest &&
        button.isAtRest &&
        (open == null || _referenceRests(open, t)) &&
        (close == null || _referenceRests(close, t)));
  }

  void _place(double sourceScale) {
    _sourceScale = sourceScale;
    final pressed = switch (_source) {
      final MenuCapsuleSource capsule => Rect.fromCenter(
        center: _source.shape.center,
        width:
            _source.shape.width +
            2 *
                (_pointer?.openedByHold ?? false
                    ? tuning.capsuleHoldLanding
                    : capsule.alone
                    ? tuning.capsuleAloneLanding
                    : tuning.capsuleSharedLanding),
        height: _source.shape.height,
      ),
      _ => Rect.fromCenter(
        center: _source.shape.center,
        width: _source.shape.width * sourceScale,
        height: _source.shape.height * sourceScale,
      ),
    };
    final height = _visibleRoot(_root);
    final size = Size(tuning.menuWidth, height);
    final attachment = _attachment;
    if (attachment != null) {
      final placed = placeAttached(
        attachment: attachment,
        size: size,
        bounds: _bounds,
        padding: _padding,
        edgeMargin: tuning.edgeMargin,
      );
      _left = placed.rect.left;
      _down = placed.down;
      _shift = placed.shift;
      _anchor = _down ? placed.rect.top : placed.rect.bottom;
    } else {
      final placed = place(
        button: pressed,
        size: size,
        bounds: _bounds,
        padding: _padding,
        edgeMargin: tuning.edgeMargin,
      );
      _left = placed.rect.left;
      _down = placed.down;
      _shift = Offset.zero;
      _anchor = _down ? placed.rect.top : placed.rect.bottom;
    }
    final reversed = !_down;
    if (reversed != _reversed) {
      _reversed = reversed;
      _root = _build(reversed: reversed);
    }
    _rootHeight.snap(_now, height);
    _amplitude = kickAmplitude(size.height);
    _closeAmplitude = _interpolate(_closeKickAmplitude, size.height);
    _sourceAmplitude = _interpolate(_sourceKickAmplitude, size.height);
  }

  void _open(double t, {double? sourceScale}) {
    _openPending = false;
    _returned = false;
    if (_phase == _Phase.opening) return;
    final fresh = _phase == _Phase.idle;
    final opacity = fresh ? 0.0 : _contentOpacityAt(t);
    if (_phase == _Phase.idle) {
      _place(sourceScale ?? _press.scaleAt(t));
      _radiusFrom = tuning.openingRadius;
    } else {
      _sourceScale = sourceScale ?? _sourceScaleAt(t);
      _radiusFrom = _closingRadius(_progress.valueAt(t));
    }
    _phase = _Phase.opening;
    if (tuning.dim case final dim?) {
      if (fresh) _fadesGlass = false;
      _dim.retarget(t, 1, spring: dim.openSpring, delay: dim.openDelay);
    }
    if (fresh) {
      _cardContainerActive = false;
      _cardContainer.snap(t, 1);
    } else if (_cardContainerActive) {
      _cardContainer.retarget(t, 1, spring: tuning.openSpring);
    }
    if (tuning.morph.fuses && drawsSource) {
      _fusions.start(t, opening: true);
    }
    final reference = MotionValue<double>(0, spring: tuning.openSpring);
    reference.retarget(t, 1);
    _openReference = reference;
    _kicks.wake(t);
    final p = _cardFadeProgress(t);
    _cardFade = Ramp(from: fresh ? 1 : _cardFade.at(p), start: p);
    _progress.retarget(t, 1, spring: tuning.openSpring);
    _fade(t, from: opacity, opening: true, fresh: fresh);
    _radius.snap(t, 0);
    unschedule(_containerSlot);
    unschedule(_closeKickSlot);
    at(
      t + tuning.radiusDelay,
      (double s) => _radius.retarget(s, 1, spring: tuning.openSpring),
      slot: _radiusSlot,
    );
    _takeEarlyTouch(t);
  }

  void _takeEarlyTouch(double t) {
    final pointer = _pointer;
    if (pointer != null && !pointer.fromButton) {
      _setHighlight(rowAt(pointer.position), _topCard);
      _lightGlow(t, pointer.position);
    }
    final release = _earlyRelease;
    _earlyRelease = null;
    if (release == null) return;
    final row = rowAt(release.position);
    final target = _targetOf(0, row);
    if (row != null && target != null && target.kind == MenuTargetKind.action) {
      _setHighlight(row, 0);
      at(t + tuning.actionDelay, (double s) => _activate(s, 0, row));
      at(t + tuning.earlyCloseDelay, _close);
    } else if (!_onMenu(release.position)) {
      at(t + tuning.earlyCloseDelay, _close);
    }
  }

  void _close(double t) {
    if (_phase != _Phase.opening) return;
    final opacity = _contentOpacityAt(t);
    _closeRadius = _openingRadius(t);
    _closeProgress = _progress.valueAt(t);
    _closeStart = t;
    _closeSource = _sourceScale;
    _closeLive = _press.scaleAt(t);
    unschedule(_radiusSlot);
    unschedule(_resizeSlot);
    unschedule(_cardSlot);
    _phase = _Phase.closing;
    if (tuning.dim case final dim?) {
      _fadesGlass = true;
      _dim.retarget(t, 0, spring: dim.closeSpring, delay: dim.closeDelay);
    }
    if (tuning.morph.fuses && drawsSource) {
      _fusions.start(t, opening: false);
    }
    _relax(t);
    final reference = MotionValue<double>(1, spring: tuning.closeSpring);
    reference.retarget(t, 0);
    _closeReference = reference;
    _kicks.wake(t);
    final p = _cardFadeProgress(t);
    _cardFade = Ramp(
      from: _cardFade.at(p),
      to: 0,
      start: p,
      end: _closeEnd(p, tuning.cardCloseFadeEnd),
    );
    _progress.retarget(t, 0, spring: tuning.closeSpring);
    _fade(t, from: opacity, opening: false);
    if (_cards.isNotEmpty && !_cardContainerActive) {
      _cardContainerActive = true;
      _cardContainer.snap(t, 1);
    }
    if (_cardContainerActive) {
      at(
        t + tuning.cardContainerDelay,
        (double s) =>
            _cardContainer.retarget(s, 0, spring: tuning.cardContainerSpring),
        slot: _containerSlot,
      );
    }
    if (!tuning.morph.kicks) return;
    at(t + tuning.closeKickDelay, (double s) {
      final kick = _kicks.menu;
      final reach = tuning.closeKickReach * _closeAmplitude;
      final room = (1 - kick.value / reach).clamp(0.0, 1.0);
      kick.velocity += tuning.closeKickImpulse * _closeAmplitude * room;
      _kicks.wake(s);
    }, slot: _closeKickSlot);
  }

  void _activate(double t, int card, int index) {
    final target = _targetOf(card, index);
    if (target == null) return;
    _emit(MenuActivated(t, target, card: card, index: index));
  }

  void _select(double t, int card, int index) {
    final target = _targetOf(card, index);
    if (target == null) return;
    switch (target.kind) {
      case MenuTargetKind.submenu:
        _setHighlight(index, card);
        final delay = card == 0
            ? tuning.submenuDelay
            : tuning.deeperSubmenuDelay;
        at(t + delay, (double s) => _openCard(s, card, index), slot: _cardSlot);
      case MenuTargetKind.back:
        _setHighlight(null, card);
        at(t + tuning.backDelay, _back);
      case MenuTargetKind.action:
        final keep = switch (dismissOnSelect) {
          null => target.keepsOpen,
          final bool dismiss => !dismiss,
        };
        if (keep) {
          _setHighlight(null, card);
          at(
            t + tuning.keptActionDelay,
            (double s) => _activate(s, card, index),
          );
          return;
        }
        _setHighlight(index, card);
        final delay = card == 0
            ? tuning.actionDelay
            : tuning.submenuActionDelay;
        at(t + delay, (double s) => _activate(s, card, index));
        at(
          t + (card == 0 ? tuning.dismissDelay : tuning.submenuCloseDelay),
          _close,
        );
    }
  }

  void _openCard(double t, int card, int index) {
    if (_phase != _Phase.opening) return;
    final source = _targetOf(card, index);
    if (source == null || source.kind != MenuTargetKind.submenu) return;
    while (_cards.length > card) {
      final last = _cards.last;
      if (!last.backing) break;
      if (_cards.length == card + 1 && last.source == index) {
        last.backing = false;
        last.progress.retarget(
          t,
          1,
          spring: card == 0 ? tuning.submenuSpring : tuning.deeperSubmenuSpring,
        );
        _setHighlight(null, card + 1);
        return;
      }
      _dropCard(_cards.removeLast());
    }
    if (_cards.length != card) return;
    final layout = submenuLayout?.call(source);
    if (layout == null) return;
    final shown = cards[card];
    final rowLocal = source.rect.center.dy - (card == 0 ? scrollOffset : 0);
    final rowCenter = shown.rect.top + rowLocal;
    final from = Rect.fromCenter(
      center: Offset(tuning.menuWidth / 2, rowCenter),
      width: tuning.cardStartWidth,
      height: source.rect.height,
    );
    final spring = card == 0
        ? tuning.submenuSpring
        : tuning.deeperSubmenuSpring;
    final progress = own(
      MotionValue<double>(0, spring: spring),
      rest: () => _cardRest,
    );
    progress.retarget(t, 1);
    final opened = _Card(
      layout: layout,
      source: index,
      from: from,
      top: _clampCardTop(
        shown.rect.top +
            (rowLocal - tuning.cardLead) * (card == 0 ? 1 : tuning.parentScale),
        layout.height,
      ),
      progress: progress,
    );
    opened.flex = own(
      MenuFlex(
        tuning,
        frame: () => _cardFrame(opened),
        side: () => _down ? 1.0 : -1.0,
        active: () => _phase == _Phase.opening,
      ),
    );
    _cards.add(opened);
    _setHighlight(null, card + 1);
  }

  void _back(double t) {
    if (_phase != _Phase.opening) return;
    final top = _topCard;
    if (top == 0) return;
    final card = _cards[top - 1];
    card.backing = true;
    card.backFrom = card.progress.valueAt(t);
    card.progress.retarget(t, 0, spring: tuning.backSpring);
    _setHighlight(null, top - 1);
  }

  void _relax(double t) {
    _flex.up(t);
    for (final card in _cards) {
      card.flex.up(t);
    }
    _touchGlow.pointerUp(t);
  }

  double _sourceScaleAt(double t) {
    if (_phase != _Phase.closing) return _sourceScale;
    final live = _press.scaleAt(t);
    final decay = math.exp(-(t - _closeStart) / tuning.sourceRelax);
    return live + (_closeSource - _closeLive) * decay;
  }

  double _openingRadius(double t) {
    final target = math.min(tuning.cornerRadius, _frameAt(t).height / 2);
    return _radiusFrom + (target - _radiusFrom) * _radius.valueAt(t);
  }

  double _closingRadius(double p) {
    final half = tuning.menuWidth / 2;
    if (_closeProgress.abs() < 1e-3) return half;
    return half + (_closeRadius - half) * p / _closeProgress;
  }

  double _localRadius(double p, double localHeight, double height) {
    final raw = _phase == _Phase.closing
        ? _closingRadius(p)
        : _openingRadius(_now);
    final capped = math.min(
      raw,
      math.min(tuning.menuWidth / 2, localHeight / 2),
    );
    return math.max(0, capped);
  }
}
