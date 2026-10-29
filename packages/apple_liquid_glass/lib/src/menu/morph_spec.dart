import 'package:kinesis/kinesis.dart';

/// The tuning of UIKit's morph between a control and the surface it opens,
/// such as a button turning into its menu.
///
/// The defaults are the `liquidMorph` tuning read live from iOS 27, the
/// set a glass button's menu uses. Geometry (position, size, transform)
/// and content travel on slightly underdamped springs; character comes
/// from a separate [kick] and [settle], and the opening ([eject]) and
/// closing ([absorb]) of the main shape use their own springs. Only
/// [eject], [absorb], [speed], [kicks] and [fuses] drive the menu
/// implementation. All other fields preserve UIKit's reference settings;
/// changing them does not change the menu. UIKit divides time by [speed],
/// so the effective response of every spring is its response times
/// [speed].
///
/// [context] is the morph of a context menu, which grows out of a blob at
/// the held view's center beside the lifted preview instead of out of a
/// button.
class MenuMorphSpec {
  /// Creates a morph spec from explicit values.
  const MenuMorphSpec({
    this.position = const Spring.response(0.3, dampingRatio: 0.8),
    this.size = const Spring.response(0.3, dampingRatio: 0.8),
    this.transform = const Spring.response(0.3, dampingRatio: 0.8),
    this.content = const Spring.response(0.3, dampingRatio: 0.8),
    this.kick = const Spring.response(0.35, dampingRatio: 0.8),
    this.settle = const Spring.response(0.5, dampingRatio: 0.8),
    this.eject = const Spring.response(0.5, dampingRatio: 0.75),
    this.absorb = const Spring.response(0.7, dampingRatio: 0.8),
    this.blurIn = const Spring.response(0.3),
    this.blurOut = const Spring.response(0.45, dampingRatio: 0.8),
    this.blurOutMinScale = 1.2,
    this.blurOutMaxScale = 1.65,
    this.secondStepDelay = 0.03,
    this.growingIntermediateShapeRatio = 0.25,
    this.shrinkingIntermediateShapeRatio = 0.9,
    this.genieScale = 0.4,
    this.speed = 0.7,
    this.kicks = true,
    this.fuses = true,
  });

  /// The spring of the surface's position.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring position;

  /// The spring of the surface's width and height.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring size;

  /// The spring of the surface's transform.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring transform;

  /// The spring of the content crossfade.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring content;

  /// The spring of the impact kick.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring kick;

  /// The spring that settles the surface after the kick.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring settle;

  /// The spring of the main shape while it opens.
  final Spring eject;

  /// The spring of the main shape while it closes.
  final Spring absorb;

  /// The spring that brings blurred content into focus.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring blurIn;

  /// The spring that blurs content away.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final Spring blurOut;

  /// The smallest scale of content blurring away.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double blurOutMinScale;

  /// The largest scale of content blurring away.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double blurOutMaxScale;

  /// The delay, in seconds, before the second step of the morph starts.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double secondStepDelay;

  /// Where the intermediate shape sits while the surface grows, as a ratio.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double growingIntermediateShapeRatio;

  /// Where the intermediate shape sits while the surface shrinks, as a
  /// ratio.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double shrinkingIntermediateShapeRatio;

  /// The scale of the genie distortion.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double genieScale;

  /// The speed multiplier UIKit applies to the morph.
  final double speed;

  /// Whether the menu and source shapes ring with their measured kicks:
  /// the menu shape's open kick and close strike and the source shape's
  /// kick. A context menu has no source shape and its menu follows the
  /// plain spring (0.6 percent rms of travel on the device morph).
  final bool kicks;

  /// Whether the menu and source shapes fuse into one silhouette while
  /// they part and meet. The context menu draws its preview on glass of
  /// its own, which the menu never fuses with (read from UIKit, notes
  /// private).
  final bool fuses;

  /// [spring] as it runs at [speed]: its response times [speed], its
  /// damping ratio unchanged.
  Spring atSpeed(Spring spring) => Spring.response(
    spring.response * speed,
    dampingRatio: spring.dampingRatio,
  );

  /// UIKit's `liquidMorph` tuning.
  static const standard = MenuMorphSpec();

  /// The morph of UIKit's context menu, measured on an iPhone 16 Pro (iOS
  /// 27, `ios27-device/context_menu/morph.json`): the menu grows out of
  /// its blob and retracts into it on one spring both ways, response
  /// 0.284 s and damping ratio 0.81, the spring the preview resizes on
  /// (0.4 - 0.6 percent rms of travel), without kicks and without fusing
  /// with the preview.
  static const context = MenuMorphSpec(
    eject: Spring.response(0.284, dampingRatio: 0.81),
    absorb: Spring.response(0.284, dampingRatio: 0.81),
    speed: 1,
    kicks: false,
    fuses: false,
  );
}
