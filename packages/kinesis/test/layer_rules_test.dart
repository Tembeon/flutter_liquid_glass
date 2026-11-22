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
    Ban(
      'addPostFrameCallback',
      r'\baddPostFrameCallback\b',
      reason:
          'A value shown after the frame is a frame late, so each use '
          'says on the line above it why it is not one: disposal, a '
          'report, a flag reset.',
      allowedWith: 'After the frame:',
    ),
    Ban(
      'ignore',
      r'//\s*ignore:',
      reason: 'A lint is fixed in the code, never silenced.',
      code: false,
    ),
    Ban(
      'ignore_for_file',
      r'//\s*ignore_for_file:',
      reason: 'A lint is fixed in the code, never silenced.',
      code: false,
    ),
    Ban(
      'AnimationController',
      r'\bAnimationController\b',
      reason:
          'Motion runs on a MotionClock, which a subtree can replay on a '
          'clock of its own, and reaches the screen without a rebuild.',
    ),
    Ban(
      'Ticker',
      r'\bTicker\b',
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
      'dynamic',
      r'\bdynamic\b',
      reason: 'Object? keeps the type checker on, where dynamic turns it off.',
    ),
    Ban(
      'SingleChildScrollView',
      r'\bSingleChildScrollView\b',
      reason:
          'A SingleChildScrollView lays out and paints its whole child, '
          'however little of it shows; a sliver builds what shows.',
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
