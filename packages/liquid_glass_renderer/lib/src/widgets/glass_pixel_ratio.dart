import 'package:flutter/widgets.dart';

/// The device pixels per logical pixel of the view [context] draws into,
/// which glass lines its copies, mattes and snaps up with.
///
/// The view's own ratio, not a `MediaQuery`'s: a subtree that overrides
/// its `MediaQueryData` still rasterizes at the view's pixels, and glass
/// laid out at another ratio would miss them. It depends on the nearest
/// `MediaQuery` so it is read again when the view's metrics change.
double glassDevicePixelRatioOf(BuildContext context) {
  MediaQuery.maybeDevicePixelRatioOf(context);
  return View.maybeOf(context)?.devicePixelRatio ?? 1;
}
