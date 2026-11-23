import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

const _widgets = 'package:flutter/widgets.dart';
const _rendering = 'package:flutter/rendering.dart';
const _services = 'package:flutter/services.dart';
const _gestures = 'package:flutter/gestures.dart';

/// motion < input < widgets < presentation. The kernel and the input model
/// stay below widgets and rendering so they can live beside any widget set
/// and replay a recording without a screen; the motion kernel takes no
/// pointer events and no platform services either.
const _rules = LayerRules(
  package: 'kinesis',
  libraries: {
    'motion': {},
    'input': {'motion'},
    'widgets': {'motion', 'input'},
    'presentation': {'motion', 'input', 'widgets'},
  },
  umbrella: 'kinesis',
  unchecked: {'testing'},
  otherLibrariesThroughSource: true,
  packages: {'flutter', 'meta'},
  forbidden: {
    everyLibrary: [
      'package:material_ui/material_ui.dart',
      'package:cupertino_ui/cupertino_ui.dart',
    ],
    'motion': [_widgets, _rendering, _services, _gestures],
    'input': [_widgets, _rendering, _services],
  },
  bans: [
    ...workspaceBans,
    Ban(
      'presence-table',
      r'PresenceStatus\.(?:shown|hidden)\s*:\s*PresenceStatus\.(?:opening|leaving)\b',
      reason:
          'Whether a presentation is shown or on its way is answered by '
          'PresenceStatus.of.',
    ),
    Ban(
      'AnimationController',
      animationControllerPattern,
      reason:
          'Motion runs on a MotionClock, which a subtree can replay on a '
          'clock of its own, and reaches the screen without a rebuild.',
    ),
    Ban(
      'Ticker',
      tickerPattern,
      reason:
          "Motion runs on a MotionClock. A route's didPush must return a "
          'TickerFuture; the route gets it from a muted ticker that runs '
          'until its motion settles.',
      allowedIn: {'lib/src/presentation/route.dart'},
    ),
    Ban(
      'MotionClock.instance',
      r'\bMotionClock\.instance\b',
      reason:
          'A widget or a shell runs on the clock of its place or of its '
          'motion (MotionClockScope.of, Motion.clock), so a subtree '
          'replays on a clock of its own.',
      allowedIn: {'lib/src/motion/', 'lib/src/widgets/scope.dart'},
    ),
    Ban(
      'implements MotionFollowed',
      r'\bimplements\s+MotionFollowed\b',
      reason:
          'A value the clock steps and publishes keeps its listeners in a '
          'ClockPublisher; a motion and an animator follow the clock '
          'themselves.',
      bannedIn: {'lib/src/motion/'},
      allowedIn: {
        'lib/src/motion/clock.dart',
        'lib/src/motion/motion.dart',
        'lib/src/motion/animator.dart',
      },
    ),
    Ban(
      'List<VoidCallback>.of',
      r'List<VoidCallback>\.of\(',
      reason:
          'Listeners are called through notifyGuarded, which copies them '
          'and reports one that throws without stopping the frame.',
      bannedIn: {'lib/src/motion/'},
      allowedIn: {'lib/src/motion/clock.dart'},
    ),
    Ban(
      'guardMotion',
      r'\bguardMotion\(',
      reason:
          'Listeners are called through notifyGuarded, which copies them '
          'and reports one that throws without stopping the frame.',
      allowedIn: {'lib/src/motion/clock.dart'},
    ),
    Ban(
      'ValueNotifier or ChangeNotifier',
      r'\b(ValueNotifier|ChangeNotifier)\b',
      reason:
          "A motion's listeners hear in the clock's publish phase, after "
          "the frame's values moved; a notifier calls them inside the "
          'command, before the values it drives.',
      bannedIn: {'lib/src/motion/'},
    ),
    Ban(
      'an opacity turned into an alpha',
      r'\*\s*255\b|\bgetAlphaFromOpacity\b',
      reason:
          'MotionTransitionLayer.update turns an opacity into an alpha by '
          "the SDK's rule, so every layer and a transition's transparency "
          'round it alike.',
      allowedIn: {'lib/src/widgets/transition.dart'},
    ),
    Ban(
      'MotionTransaction.layoutSpring',
      r'\bMotionTransaction\.layoutSpring\b',
      reason:
          "A layout host reads the frame's layout spring in one place, "
          'LayoutMotionOwner, and hands it to LayoutMotion.layout, which '
          'decides from it whether the layout jumps, moves or carries.',
      allowedIn: {'lib/src/widgets/layout_item.dart'},
    ),
    Ban(
      'a planner set by a host',
      r'(?<!\bthis)\.planner\s*=[^=]',
      reason:
          "A layout owner hands its widget's planner on in one place; what "
          'differs per layout, such as the rows a list scrolled into view, '
          'goes to LayoutMotion.layout as an argument, never as a planner '
          'swapped around the call.',
      bannedIn: {'lib/src/widgets/'},
      allowedIn: {'lib/src/widgets/layout_item.dart'},
    ),
    Ban(
      'a capped list of running changes',
      r'\bmaxChanges\b|List<MotionValue<double>>',
      reason:
          'Changes that run at once, each a progress of its own, at most '
          'three, are MotionChanges: a text or a content that changes owns '
          'one, never a list of its own.',
      allowedIn: {'lib/src/motion/changes.dart'},
    ),
    Ban(
      'MouseRegion',
      r'\bMouseRegion\(',
      reason:
          "An input target's box is its own mouse annotation (MouseTarget): "
          'its cursor is resolved once per state change and shows on the '
          'enter, with no element, hit test entry or rebuild of a '
          'MouseRegion.',
    ),
    Ban(
      'member-level @internal',
      r'^[ \t]+@internal\b',
      reason:
          'What the package shares among its files and no app may call is '
          'a private member reached through an @internal extension in the '
          "class's own file, or an @internal top-level declaration: a member "
          'marked @internal stays in the public API listing and in every '
          "subclass's interface.",
    ),
    Ban(
      'a positioned input built outside the event intake',
      r'\b(?:Pointer(?:Down|Move|Up|Hover|Scroll)Input|ContextMenuInput)\((?!\s*[):])',
      reason:
          'A positioned input is made from its event where events become '
          'inputs (the pointer line, the input target); moved or handed on '
          'it is copied beside its class (InteractionInputInternal.shifted, '
          'PointerDownInputInternal), so a field added to it is never lost.',
      bannedIn: {'lib/src/widgets/'},
      allowedIn: {
        'lib/src/widgets/pointer_line.dart',
        'lib/src/widgets/input_target.dart',
      },
    ),
    Ban(
      'a touch mirrored by hand',
      r'width - \w+(?:\.\w+)*\.dx\b',
      reason:
          'A touch is mirrored for a right-to-left layout by its input '
          '(PointerDownInput.mirrored and the move and up forms), about the '
          "region's width at the down, never by subtracting from a width "
          'of its own.',
      allowedIn: {'lib/src/input/interaction_input.dart'},
    ),
    Ban(
      'a look decided under Reduce Motion',
      r'\.reduceMotion\s*\?',
      reason:
          'What content wears of a look under Reduce Motion is decided once, '
          'MotionPoseWorn.wornUnder (and wornDuringChange for a change); a '
          'host keeps its transition and wears it, never swapping it for a '
          'fade or zeroing a direction.',
      bannedIn: {'lib/'},
      allowedIn: {'lib/src/motion/pose.dart'},
    ),
    Ban(
      'a pose worn by hand',
      r'\.offsetFor\(',
      reason:
          'A look is worn on a layer through poseTransform, which maps every '
          'field of a MotionPose; only the numeric text, which paints its '
          'glyphs on a canvas, reads the fields itself.',
      bannedIn: {'lib/'},
      allowedIn: {
        'lib/src/widgets/transition.dart',
        'lib/src/widgets/motion_numeric_text.dart',
      },
    ),
    Ban(
      'dismissal vocabulary in motion',
      r'\bDismiss(Trigger|Policy)\b',
      reason:
          "What asked a presentation to go and which askers it lets through "
          "are the presentation shell's; a presented motion leaves the same "
          'whoever asked.',
      bannedIn: {'lib/src/motion/'},
    ),
    Ban(
      'states written outside a region or zone',
      r'\bshownStates\(',
      reason:
          "A control's states have one writer, its InputRegion or its "
          "InputZones host; a control says its facts there and reads them "
          'through ControlStates.withStates.',
      bannedIn: {'lib/'},
      allowedIn: {
        'lib/src/widgets/control_states.dart',
        'lib/src/widgets/input_region.dart',
        'lib/src/widgets/input_zones.dart',
      },
    ),
    Ban(
      'a muted ticker read by a host',
      r'TickerMode\.(valuesOf|of|getNotifier)\(',
      reason:
          'Whether a host follows its motion under a muted TickerMode is one '
          'rule, followsMotion; a render host hears its values through '
          'MotionFollow.',
      bannedIn: {'lib/'},
      allowedIn: {'lib/src/widgets/follow.dart'},
    ),
    Ban(
      'a keys-only interaction by hand',
      r'\bget takes\s*=>\s*const\s*\{(?![^}]*InputKind\.pointer)',
      reason:
          'An interaction that takes no pointer is a CommandInteraction: the '
          'keyboard and accessibility reach it, and its region or zone leaves '
          'touches to what lies under or around it.',
      bannedIn: {'lib/'},
    ),
    Ban(
      'a widget hearing a motion past MotionFollow',
      r'\.addRenderListener\(',
      reason:
          'A widget hears a motion through MotionFollow, which stops '
          'hearing under a muted TickerMode; the layout item hears its slot '
          'and the drop of its items itself.',
      bannedIn: {'lib/src/widgets/', 'lib/src/presentation/'},
      allowedIn: {
        'lib/src/widgets/follow.dart',
        'lib/src/widgets/layout_item.dart',
      },
    ),
    Ban(
      'a part settled by hand',
      r'dueAfter\([^)]*\)\s*==\s*null',
      reason:
          'A part is settled at a time when it rests and nothing of its own '
          'is due after: settledAt says it once.',
      bannedIn: {'lib/'},
      allowedIn: {'lib/src/motion/part.dart'},
    ),
    Ban(
      'a ghost decided by a layout host',
      r'\bghosts\.add\(|\bmuted\s*=',
      reason:
          'Whether an item that left is drawn leaving is decided once, '
          'LayoutMotionOwner.updateGhosts, with the ticker read it needs.',
      bannedIn: {'lib/src/widgets/'},
      allowedIn: {'lib/src/widgets/layout_item.dart'},
    ),
    Ban(
      'Duration',
      r'\bDuration\b',
      reason:
          'Times are seconds on the motion clock; a Duration is only the '
          "engine's stamp or the SDK's own API.",
      bannedIn: {'lib/'},
      allowedIn: {
        'lib/src/motion/clock.dart',
        'lib/src/motion/frame_cadence.dart',
        'lib/src/motion/frame_time.dart',
        'lib/src/motion/pointer_clock_io.dart',
        'lib/src/motion/pointer_clock_stub.dart',
        'lib/src/widgets/haptics.dart',
        'lib/src/widgets/input_target.dart',
        'lib/src/widgets/pointer_line.dart',
        'lib/src/presentation/route.dart',
      },
    ),
  ],
);

void main() {
  final report = checkLayers(Directory.current, _rules);

  test('every lib/src folder is one library behind one library file', () {
    expect(report.structure, isEmpty);
  });

  test('imports and bans break the rules only as test/rules/debt.txt '
      'lists', () {
    final failure = holdDebt(
      File('test/rules/debt.txt'),
      report.violations,
      update: updateDebtRequested,
    );
    if (failure != null) fail(failure);
  });
}
