import 'package:layer_rules/src/rules.dart';

/// The bans every package of this workspace holds, the owner's rules for
/// any code in it.
const workspaceBans = <Ban>[
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
  Ban(
    'addPostFrameCallback',
    r'\baddPostFrameCallback\b',
    reason:
        'The end of a frame is for what a frame leaves behind: disposal, a '
        'report, a flag reset. A value shown after the frame is a frame '
        'late, so each use says on the line above it why it is not one.',
    allowedWith: 'After the frame:',
  ),
];

/// Flutter's tickers and what makes them: `Ticker`,
/// `SingleTickerProviderStateMixin`, `TickerProviderStateMixin` and
/// `createTicker`, for a ban whose reason is the package's own.
const tickerPattern =
    r'\b(?:Single)?Ticker(?:Provider(?:StateMixin)?)?\b|\bcreateTicker\b';

/// Flutter's `AnimationController`, for a ban whose reason is the
/// package's own.
const animationControllerPattern = r'\bAnimationController\b';
