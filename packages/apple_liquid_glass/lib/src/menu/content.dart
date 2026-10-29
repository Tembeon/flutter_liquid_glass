import 'package:apple_liquid_glass/src/menu/entries.dart';
import 'package:apple_liquid_glass/src/menu/layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The entries of an open menu and everything that is not in them: the
/// answers of deferred groups, the measured heights of free-form rows;
/// lays them out and runs their actions.
///
/// The shared menu host keeps one content model, so entries behave the
/// same in a menu button and a bar button menu.
@internal
class MenuContent {
  /// Creates the content; [onChanged] runs when it changes on its own (a
  /// deferred group answered, a free-form row measured), with whether the
  /// change should animate the menu's size.
  MenuContent({required this.onChanged});

  /// Called when the content changed outside a rebuild of the entries.
  final void Function({required bool animate}) onChanged;

  /// The entries, top to bottom.
  List<GlassMenuEntry> entries = const [];

  /// The order of the entries relative to the button.
  GlassMenuOrder order = GlassMenuOrder.automatic;

  /// Whether the menu is laid out right to left.
  bool rtl = false;

  /// The layout of the inside of the menu.
  MenuMetrics metrics = MenuMetrics.standard;

  /// The style row titles are measured in when they may wrap.
  TextStyle titleStyle = const TextStyle(fontSize: 17);

  /// The text scaler row titles are measured with.
  TextScaler textScaler = TextScaler.noScaling;

  final Map<Object, List<GlassMenuEntry>> _cached = {};
  final Map<Object, List<GlassMenuEntry>> _session = {};
  final Set<Object> _loading = {};
  final Map<Object, double> _heights = {};
  int _sessionId = 0;
  bool _disposed = false;

  /// Starts a new opening: uncached deferred groups load again.
  void beginSession() {
    _sessionId++;
    _session.clear();
  }

  /// Stops reporting changes.
  void dispose() {
    _disposed = true;
  }

  /// The root list, reversed for a menu that opens upward unless the
  /// order is fixed.
  MenuLayout root({required bool reversed}) => MenuLayout.build(
    entries,
    metrics: metrics,
    reversed: reversed && order != GlassMenuOrder.fixed,
    rtl: rtl,
    resolve: _resolve,
    widgetHeight: (Object key) => _heights[key],
    titleLines: _lines,
  );

  /// The card of the submenu behind [target], or null.
  MenuLayout? submenu(MenuTarget target) {
    final entry = target.entry;
    if (entry is! GlassSubmenu) return null;
    return MenuLayout.build(
      entry.children,
      metrics: metrics,
      rtl: rtl,
      header: entry,
      singleSelection: entry.singleSelection,
      elementSize: entry.elementSize,
      resolve: _resolve,
      widgetHeight: (Object key) => _heights[key],
      titleLines: _lines,
    );
  }

  /// Runs the action behind [target].
  void activate(MenuTarget target) {
    final entry = target.entry;
    if (entry is GlassMenuItem) entry.onPressed?.call();
  }

  /// Tells the items behind [from] and [to] that the highlight moved.
  void highlight(MenuTarget? from, MenuTarget? to) {
    final left = from?.entry;
    final entered = to?.entry;
    if (identical(left, entered)) return;
    if (left is GlassMenuItem) left.onHighlightChanged?.call(false);
    if (entered is GlassMenuItem) entered.onHighlightChanged?.call(true);
  }

  /// Records the laid out height of the free-form row [key].
  void reportHeight(Object key, double height) {
    final known = _heights[key];
    if (known != null && (known - height).abs() < 0.5) return;
    _heights[key] = height;
    if (!_disposed) onChanged(animate: known != null);
  }

  int _lines(String title, double width, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: maxLines,
      textScaler: textScaler,
    );
    painter.layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines < 1 ? 1 : lines;
  }

  List<GlassMenuEntry>? _resolve(GlassMenuDeferred deferred) {
    final key = deferred.cacheKey;
    final answer = deferred.cache ? _cached[key] : _session[key];
    if (answer != null) return answer;
    final session = _sessionId;
    final loading = deferred.cache ? key : (key, session);
    if (_loading.contains(loading)) return null;
    _loading.add(loading);
    void store(List<GlassMenuEntry> entries) {
      _loading.remove(loading);
      if (deferred.cache) {
        _cached[key] = entries;
      } else if (session == _sessionId) {
        _session[key] = entries;
      } else {
        return;
      }
      if (!_disposed) onChanged(animate: true);
    }

    Future<List<GlassMenuEntry>>.sync(deferred.load).then(
      store,
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'morph',
            context: ErrorDescription('while loading a deferred menu group'),
          ),
        );
        store(const []);
      },
    );
    return null;
  }
}
