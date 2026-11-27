import 'package:flutter/widgets.dart';

/// The query of a search and whether the search is open, like Flutter's
/// `SearchController`.
///
/// UIKit: `UISearchController` (`isActive`). SwiftUI: `searchable` with
/// `isPresented`. Flutter: `SearchController`.
///
/// A `GlassTabBar` given one shows a search tab beside its tabs: opening
/// the search turns the bar into its search field, and closing it turns
/// the field back and clears the query. Listeners hear both the query and
/// the open state change.
class GlassSearchController extends TextEditingController {
  /// Creates a closed search with [text] as its query.
  GlassSearchController({super.text});

  bool _isOpen = false;

  /// Whether the search is open.
  bool get isOpen => _isOpen;

  /// Opens the search.
  void openView() {
    if (_isOpen) return;
    _isOpen = true;
    notifyListeners();
  }

  /// Closes the search; the widget showing it clears the query as it
  /// closes.
  void closeView() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  /// The search around [context]: the controller of the nearest
  /// [GlassSearchScope], as a `GlassTabScaffold` with a search gives its
  /// pages, or null outside one.
  ///
  /// SwiftUI: the `isSearching` and `dismissSearch` environment values;
  /// [isOpen] says whether the search is open and [closeView] ends it.
  /// [context] rebuilds when the search opens or closes and when its query
  /// changes.
  static GlassSearchController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSearchScope>()?.notifier;

  /// The search around [context]; see [maybeOf].
  static GlassSearchController of(BuildContext context) {
    final search = maybeOf(context);
    if (search == null) {
      throw FlutterError(
        'GlassSearchController.of called outside a GlassSearchScope.',
      );
    }
    return search;
  }
}

/// Gives the widgets below it [GlassSearchController.of], for a search an
/// app shows itself; a `GlassTabScaffold` with a search gives it its pages.
class GlassSearchScope extends InheritedNotifier<GlassSearchController> {
  /// Gives [child] the search [controller].
  const GlassSearchScope({
    required GlassSearchController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
}
