import 'dart:ui';

/// The side, in points, of the smallest area that takes a finger: Apple's
/// Human Interface Guidelines ask for a target of at least 44 by 44 points
/// for every control, whatever the size of its look.
const double glassMinimumTargetExtent = 44;

/// The smallest area that takes a finger, [glassMinimumTargetExtent] square.
const Size glassMinimumTarget = Size.square(glassMinimumTargetExtent);
