import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// How a search field stacked under a navigation bar's large title draws:
/// [height] points tall, its glass only as present as [glass], over the
/// plain fill its bar draws under it.
@internal
class SearchFieldStacking extends InheritedWidget {
  /// Stacks the search fields below.
  const SearchFieldStacking({
    required this.height,
    required this.glass,
    required super.child,
    super.key,
  });

  /// The height of the field.
  final double height;

  /// How present the field's glass is, 0 to 1.
  final MotionValue<double> glass;

  /// The stacking around [context], or null.
  static SearchFieldStacking? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchFieldStacking>();

  @override
  bool updateShouldNotify(SearchFieldStacking oldWidget) =>
      height != oldWidget.height || glass != oldWidget.glass;
}

/// The signal a host's close button fires through [end] when a search ends.
@internal
class SearchEndSignal extends ChangeNotifier {
  /// Tells the listeners that a search ended.
  void end() => notifyListeners();
}

/// Where a search field hears that its search ended outside it: the close
/// button of a toolbar that hosts it.
@internal
class SearchEnds extends InheritedWidget {
  /// Tells the search fields below that [ends] notifies when a search
  /// ends.
  const SearchEnds({required this.ends, required super.child, super.key});

  /// Notifies when a search ends.
  final Listenable ends;

  /// The ends around [context], or null.
  static Listenable? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchEnds>()?.ends;

  @override
  bool updateShouldNotify(SearchEnds oldWidget) => ends != oldWidget.ends;
}
