import 'package:apple_liquid_glass/src/widgets/controls/list.dart';

/// The standard accessory of a [GlassListRow].
///
/// UIKit: `UITableViewCell.AccessoryType`. SwiftUI: a `NavigationLink`'s
/// chevron. Flutter: `CupertinoListTile.trailing` with
/// `CupertinoListTileChevron`.
///
/// The checkmark and the info button are drawn in the row's icon color,
/// with the ink and strokes of UIKit's `checkmark` and `info.circle`
/// symbols (list passport).
enum GlassListAccessory {
  /// The disclosure chevron of a row that pushes a screen.
  disclosureIndicator,

  /// A checkmark: the row is the chosen one of a list of options.
  checkmark,

  /// An info button; a tap on it calls [GlassListRow.onAccessoryPressed]
  /// instead of the row's [GlassListRow.onPressed].
  detailButton,

  /// An info button followed by the disclosure chevron.
  detailDisclosureButton,

  /// The chevron of an outline row whose children it shows and hides
  /// (UIKit `UICellAccessory.outlineDisclosure`): in a 44 point button 5
  /// points from the row's end, in the secondary color, pointing forward
  /// and turning down while [GlassListRow.expanded] (list passport, iOS
  /// 27.2 simulator). A tap on it calls [GlassListRow.onAccessoryPressed],
  /// which usually turns [GlassListRow.expanded] and adds or removes the
  /// child rows.
  outlineDisclosure,
}
