import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The words the package's widgets say to assistive technology, such as the
/// label of a sheet's grabber or of the dimming behind a popover.
///
/// UIKit: the system's own localized accessibility strings. Flutter:
/// `CupertinoLocalizations`, `WidgetsLocalizations`.
///
/// Found with [GlassLocalizations.of] through Flutter's [Localizations]. An
/// app that registers no delegate gets the English
/// [DefaultGlassLocalizations]; an app that translates registers its own
/// `LocalizationsDelegate<GlassLocalizations>` in its
/// `localizationsDelegates`, usually a subclass of
/// [DefaultGlassLocalizations] that overrides what it translates.
abstract class GlassLocalizations {
  /// Creates the strings; for a subclass.
  const GlassLocalizations();

  /// The strings of the closest [Localizations] that loaded a
  /// [GlassLocalizations], or the English [DefaultGlassLocalizations] when
  /// none did.
  static GlassLocalizations of(BuildContext context) =>
      Localizations.of<GlassLocalizations>(context, GlassLocalizations) ??
      const DefaultGlassLocalizations();

  /// The name of an alert whose title and message are not plain text, as
  /// `CupertinoLocalizations.alertDialogLabel` names one.
  String get alertLabel;

  /// The label of the dimming behind an action sheet, whose tap dismisses
  /// it.
  String get actionSheetDismissLabel;

  /// The label of the dimming behind a sheet, whose tap dismisses it.
  String get sheetDismissLabel;

  /// The label of the dimming behind a popover, whose tap dismisses it.
  String get popoverDismissLabel;

  /// The label of what lies around a menu, whose tap dismisses it, as
  /// `CupertinoLocalizations.menuDismissLabel`.
  String get menuDismissLabel;

  /// The label of a sheet's grabber, which steps the sheet between its
  /// detents.
  String get sheetGrabberLabel;

  /// The value a sheet's grabber reads at the large detent, the full
  /// height.
  String get sheetLargeDetentValue;

  /// The value a sheet's grabber reads at the medium detent, half the
  /// height.
  String get sheetMediumDetentValue;

  /// The value a sheet's grabber reads at a detent of its own height: the
  /// [position]th smallest of [count], counting from 1.
  String sheetDetentValue(int position, int count);

  /// The label of the button that goes back a page.
  String get backButtonLabel;

  /// The label of a button that closes what it sits in.
  String get closeButtonLabel;

  /// The label of a search field and of the button that opens one.
  String get searchLabel;

  /// The label of the button that clears a text field.
  String get clearTextLabel;

  /// The label of a row's button that shows more about it.
  String get moreInfoLabel;

  /// The value of a page control: [page] of [count], counting from 1.
  String pageValue(int page, int count);

  /// The label of the half of a stepper that raises its value.
  String get incrementLabel;

  /// The label of the half of a stepper that lowers its value.
  String get decrementLabel;

  /// The value of a slider at [fraction] of its range, 0 to 1.
  String percentValue(double fraction);
}

/// The English [GlassLocalizations], used where an app loaded none.
class DefaultGlassLocalizations extends GlassLocalizations {
  /// Creates the English strings.
  const DefaultGlassLocalizations();

  /// A delegate that loads the English strings for every locale, for an
  /// app that lists its delegates and wants the package's English ones.
  static const LocalizationsDelegate<GlassLocalizations> delegate =
      _DefaultGlassLocalizationsDelegate();

  @override
  String get alertLabel => 'Alert';

  @override
  String get actionSheetDismissLabel => 'Dismiss action sheet';

  @override
  String get sheetDismissLabel => 'Dismiss sheet';

  @override
  String get popoverDismissLabel => 'Dismiss popover';

  @override
  String get menuDismissLabel => 'Dismiss menu';

  @override
  String get sheetGrabberLabel => 'Sheet grabber';

  @override
  String get sheetLargeDetentValue => 'Large';

  @override
  String get sheetMediumDetentValue => 'Medium';

  @override
  String sheetDetentValue(int position, int count) =>
      'Detent $position of $count';

  @override
  String get backButtonLabel => 'Back';

  @override
  String get closeButtonLabel => 'Close';

  @override
  String get searchLabel => 'Search';

  @override
  String get clearTextLabel => 'Clear text';

  @override
  String get moreInfoLabel => 'More info';

  @override
  String pageValue(int page, int count) => 'page $page of $count';

  @override
  String get incrementLabel => 'Increment';

  @override
  String get decrementLabel => 'Decrement';

  @override
  String percentValue(double fraction) => '${(fraction * 100).round()}%';
}

class _DefaultGlassLocalizationsDelegate
    extends LocalizationsDelegate<GlassLocalizations> {
  const _DefaultGlassLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GlassLocalizations> load(Locale locale) =>
      SynchronousFuture<GlassLocalizations>(const DefaultGlassLocalizations());

  @override
  bool shouldReload(_DefaultGlassLocalizationsDelegate old) => false;
}
