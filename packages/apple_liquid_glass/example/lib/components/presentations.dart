import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/stand/music_page.dart';
import 'package:apple_liquid_glass_example/stand/video_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

GlassMenuItemState _on(bool on) =>
    on ? GlassMenuItemState.on : GlassMenuItemState.off;

Widget _row(
  IconData icon,
  Color color,
  String title,
  VoidCallback onPressed, {
  String? subtitle,
}) => GlassListRow(
  leading: SettingsIcon(icon: icon, color: color),
  title: Text(title),
  subtitle: subtitle == null ? null : Text(subtitle),
  accessory: GlassListAccessory.disclosureIndicator,
  onPressed: onPressed,
);

class MenusPage extends StatefulWidget {
  const MenusPage({super.key});

  @override
  State<MenusPage> createState() => _MenusPageState();
}

class _MenusPageState extends State<MenusPage> {
  var _favorite = false;
  var _sort = 'Date';
  var _ascending = true;
  var _more = false;

  List<GlassMenuEntry> _menu() => [
    GlassMenuSection(
      elementSize: GlassMenuElementSize.medium,
      children: [
        GlassMenuItem(
          title: 'Copy',
          icon: const Icon(CupertinoIcons.doc_on_doc),
          onPressed: () {},
        ),
        GlassMenuItem(
          title: 'Share',
          icon: const Icon(CupertinoIcons.share),
          onPressed: () {},
        ),
        GlassMenuItem(
          title: _favorite ? 'Unfavorite' : 'Favorite',
          icon: const Icon(CupertinoIcons.heart),
          selectedIcon: const Icon(CupertinoIcons.heart_fill),
          state: _on(_favorite),
          onPressed: () => setState(() => _favorite = !_favorite),
        ),
      ],
    ),
    GlassMenuItem(
      title: 'New Folder',
      icon: const Icon(CupertinoIcons.folder_badge_plus),
      onPressed: () {},
    ),
    if (_more)
      GlassMenuItem(
        title: 'Rename',
        icon: const Icon(CupertinoIcons.pencil),
        onPressed: () {},
      ),
    GlassMenuItem(
      title: _more ? 'Show Less' : 'Show More',
      icon: Icon(
        _more ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
      ),
      keepsMenuOpen: true,
      onPressed: () => setState(() => _more = !_more),
    ),
    GlassSubmenu(
      title: 'Sort By',
      subtitle: _sort,
      icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
      children: [
        GlassMenuSection(
          singleSelection: true,
          children: [
            for (final sort in const ['Date', 'Name', 'Size'])
              GlassMenuItem(
                title: sort,
                state: _on(sort == _sort),
                onPressed: () => setState(() => _sort = sort),
              ),
          ],
        ),
        GlassMenuSection(
          singleSelection: true,
          children: [
            GlassMenuItem(
              title: 'Ascending',
              state: _on(_ascending),
              onPressed: () => setState(() => _ascending = true),
            ),
            GlassMenuItem(
              title: 'Descending',
              state: _on(!_ascending),
              onPressed: () => setState(() => _ascending = false),
            ),
          ],
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Menus',
    slivers: [
      Demo(
        'GlassMenuItem, GlassMenuSection, GlassSubmenu',
        'A menu grows out of the glass of its button. A finger that '
            'opened it can slide on to an item; a row can change the menu '
            'while it stays open, and a submenu unfolds in place.',
        child: PhotoPanel(
          wallpaper: Wallpaper.city,
          child: Row(
            children: [
              GlassButton(
                menuChildren: _menu(),
                onPressed: null,
                child: const Text('Options'),
              ),
              const Spacer(),
              GlassButton.prominent(
                semanticLabel: 'Add',
                menuChildren: [
                  for (final (title, icon) in const [
                    ('Photo', CupertinoIcons.photo),
                    ('Note', CupertinoIcons.square_pencil),
                    ('Reminder', CupertinoIcons.checkmark_circle),
                  ])
                    GlassMenuItem(
                      title: title,
                      icon: Icon(icon),
                      onPressed: () {},
                    ),
                ],
                onPressed: null,
                child: const Icon(CupertinoIcons.plus),
              ),
            ],
          ),
        ),
      ),
      Demo(
        'GlassContextMenu',
        'Hold a photo: it lifts out of the page and its menu grows beside '
            'it.',
        child: Panel(
          child: Row(
            children: [
              for (final wallpaper in const [
                Wallpaper.bloom,
                Wallpaper.dunes,
                Wallpaper.alpine,
              ]) ...[
                Expanded(
                  child: GlassContextMenu(
                    menuChildren: [
                      GlassMenuItem(
                        title: 'Share ${wallpaper.title}',
                        icon: const Icon(CupertinoIcons.share),
                        onPressed: () {},
                      ),
                      GlassMenuItem(
                        title: 'Favorite',
                        icon: const Icon(CupertinoIcons.heart),
                        onPressed: () {},
                      ),
                      GlassMenuItem(
                        title: 'Delete',
                        icon: const Icon(CupertinoIcons.trash),
                        destructive: true,
                        onPressed: () {},
                      ),
                    ],
                    child: ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image(image: wallpaper.image, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
                if (wallpaper != Wallpaper.alpine) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Alerts and action sheets',
    slivers: [
      Demo(
        'showGlassAlert',
        'A panel of glass in the middle of the screen, with a default, a '
            'cancel or a destructive action, in the system look or yours.',
        flush: true,
        child: GlassListSection(
          children: [
            _row(
              CupertinoIcons.bell_fill,
              GlassColors.systemBlue,
              'Two actions',
              () => unawaited(
                showGlassAlert(
                  context,
                  title: const Text('Allow notifications?'),
                  message: const Text(
                    'Alerts, sounds and badges about your library.',
                  ),
                  actions: const [
                    GlassAlertAction(child: Text("Don't Allow")),
                    GlassAlertAction(
                      isDefaultAction: true,
                      child: Text('Allow'),
                    ),
                  ],
                ),
              ),
            ),
            _row(
              CupertinoIcons.trash_fill,
              GlassColors.systemRed,
              'Destructive',
              () => unawaited(
                showGlassAlert(
                  context,
                  title: const Text('Delete 24 photos?'),
                  message: const Text(
                    'They move to Recently Deleted and stay there for 30 '
                    'days.',
                  ),
                  actions: const [
                    GlassAlertAction.cancel(child: Text('Cancel')),
                    GlassAlertAction.destructive(child: Text('Delete')),
                  ],
                ),
              ),
            ),
            _row(
              CupertinoIcons.paintbrush_fill,
              GlassColors.systemOrange,
              'Styled',
              () => unawaited(
                showGlassAlert(
                  context,
                  title: const Text('Join the beta?'),
                  message: const Text(
                    'New features arrive a few weeks early.',
                  ),
                  style: const GlassAlertStyle(
                    titleTextStyle: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    actionColor: Color(0xFFFF9500),
                    defaultActionFillColor: Color(0xFFFF9500),
                  ),
                  actions: const [
                    GlassAlertAction(child: Text('Not Now')),
                    GlassAlertAction(
                      isDefaultAction: true,
                      child: Text('Join'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      Demo(
        'showGlassActionSheet',
        'Choices that rise from the bottom edge, the cancel apart from '
            'the rest.',
        flush: true,
        child: GlassListSection(
          children: [
            _row(
              CupertinoIcons.square_arrow_up_fill,
              GlassColors.systemGreen,
              'Action sheet',
              () => unawaited(
                showGlassActionSheet(
                  context,
                  title: const Text('Save the edited photo?'),
                  actions: const [
                    GlassAlertAction(child: Text('Save as New')),
                    GlassAlertAction(child: Text('Replace Original')),
                    GlassAlertAction.destructive(
                      child: Text('Discard Changes'),
                    ),
                    GlassAlertAction.cancel(child: Text('Cancel')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class SheetsPage extends StatelessWidget {
  const SheetsPage({super.key});

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Sheets and popovers',
    slivers: [
      Demo(
        'showGlassSheet',
        'A sheet that rests at detents, follows the finger between them '
            'and hands a scroll over to its list at the top one.',
        flush: true,
        child: GlassListSection(
          children: [
            _row(
              CupertinoIcons.map_fill,
              GlassColors.systemBlue,
              'Sheet with detents',
              subtitle: 'Medium and large; the page stays live at medium',
              () => unawaited(
                showGlassSheet<void>(
                  context,
                  detents: const [
                    GlassSheetDetent.medium,
                    GlassSheetDetent.large,
                  ],
                  largestUndimmedDetent: GlassSheetDetent.medium,
                  showDragHandle: true,
                  builder: (context) => const _Places(),
                ),
              ),
            ),
            _row(
              CupertinoIcons.paintbrush_fill,
              GlassColors.systemOrange,
              'Fitted and styled',
              subtitle: 'As tall as what it holds, in its own colors',
              () => unawaited(
                showGlassSheet<void>(
                  context,
                  detents: const [GlassSheetDetent.fitted],
                  showDragHandle: true,
                  style: const GlassSheetStyle(
                    backgroundColor: GlassDynamicColor.withBrightness(
                      color: Color(0xFFFFF4E5),
                      darkColor: Color(0xFF3A2A12),
                    ),
                    dragHandleColor: Color(0xFFFF9500),
                  ),
                  builder: (context) => const _Recipe(),
                ),
              ),
            ),
          ],
        ),
      ),
      Demo(
        'showGlassPopover',
        'A bubble that points at what it came from and fits its arrow to '
            'the room it has.',
        child: PhotoPanel(
          wallpaper: Wallpaper.bloom,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final name in const ['Here', 'Or here'])
                Builder(
                  builder: (anchor) => GlassButton(
                    onPressed: () => unawaited(
                      showGlassPopover<void>(
                        context,
                        anchor: anchor,
                        adaptsToSheet: false,
                        builder: (context) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(
                            width: 230,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const GlassDefaultTextStyle(
                                  role: GlassTextRole.headline,
                                  child: Text('Popover'),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'It grew out of the button and goes back '
                                  'into it.',
                                ),
                                const SizedBox(height: 14),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GlassButton.prominent(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Done'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: Text(name),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Places extends StatelessWidget {
  const _Places();

  static const _places = [
    ('Golden Gate Park', 'Park', CupertinoIcons.tree),
    ('Ferry Building', 'Market', CupertinoIcons.cart_fill),
    ('Coit Tower', 'Landmark', CupertinoIcons.building_2_fill),
    ('Lands End', 'Trail', CupertinoIcons.map),
    ('Ocean Beach', 'Beach', CupertinoIcons.sun_max_fill),
    ('Twin Peaks', 'Viewpoint', CupertinoIcons.eye_fill),
    ('Palace of Fine Arts', 'Landmark', CupertinoIcons.building_2_fill),
    ('Baker Beach', 'Beach', CupertinoIcons.sun_max_fill),
    ('Presidio', 'Park', CupertinoIcons.tree),
    ('Chinatown', 'Neighborhood', CupertinoIcons.house_fill),
    ('Alcatraz', 'Island', CupertinoIcons.location_solid),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    controller: GlassSheet.scrollControllerOf(context),
    padding: const EdgeInsets.only(top: 24, bottom: 40),
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: GlassDefaultTextStyle(
          role: GlassTextRole.title2,
          child: Text('Places', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      GlassListSection(
        children: [
          for (final (name, kind, icon) in _places)
            GlassListRow(
              leading: SettingsIcon(icon: icon, color: GlassColors.systemBlue),
              title: Text(name),
              subtitle: Text(kind),
              accessory: GlassListAccessory.disclosureIndicator,
              onPressed: () {},
            ),
        ],
      ),
    ],
  );
}

class _Recipe extends StatelessWidget {
  const _Recipe();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GlassDefaultTextStyle(
          role: GlassTextRole.title2,
          child: Text(
            'Lemon cake',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Three lemons, two eggs, a cup of sugar and forty minutes. The '
          'sheet is as tall as these lines and no taller.',
        ),
        const SizedBox(height: 18),
        GlassButton.prominent(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class BarsPage extends StatelessWidget {
  const BarsPage({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => unawaited(
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(GlassPageRoute<void>(builder: (context) => page)),
    );
    return ComponentPage(
      title: 'Bars and pages',
      slivers: [
        Demo(
          'GlassNavigationBar, GlassToolbar',
          'A large title that folds into the bar as the page scrolls, bar '
              'items of glass, a toolbar at the bottom and the frost where '
              'content passes under either.',
          flush: true,
          child: GlassListSection(
            children: [
              _row(
                CupertinoIcons.tray_full_fill,
                GlassColors.systemBlue,
                'A mailbox',
                subtitle: 'Large title, bar items, toolbar',
                () => open(const _Mailbox()),
              ),
            ],
          ),
        ),
        Demo(
          'GlassTabBar, GlassTabScaffold',
          'The bar at the bottom of this app: a lens that slides between '
              'tabs, a search button beside it. In an app of its own it '
              'tucks away on scroll and carries an accessory.',
          flush: true,
          child: GlassListSection(
            children: [
              _row(
                CupertinoIcons.music_note_2,
                GlassColors.systemRed,
                'A music app',
                subtitle: 'A tab bar that minimizes, with a mini player',
                () => open(const MusicPage()),
              ),
              _row(
                CupertinoIcons.play_rectangle_fill,
                GlassColors.systemGray,
                'A video player',
                subtitle: 'Bars and buttons over a playing video',
                () => open(const VideoPage()),
              ),
            ],
          ),
        ),
        const Demo(
          'GlassBadge',
          'A count, a word or a dot, on a tab or anywhere.',
          child: Panel(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GlassBadge.count(3),
                GlassBadge.count(128),
                GlassBadge.text('New'),
                GlassBadge.indicator(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A page with every bar: a large title, items and a toolbar.
class _Mailbox extends StatelessWidget {
  const _Mailbox();

  static const _senders = [
    'Tim',
    'Design review',
    'Flutter',
    'Weather',
    'The bank',
    'Nora',
    'Receipts',
    'Photos',
    'Calendar',
    'Travel',
    'Newsletter',
    'Support',
    'Billing',
    'Sam',
  ];

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemBackground,
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Inbox'),
      previousPageTitle: 'Bars',
      trailing: [
        GlassBarItem(
          icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
          semanticLabel: 'Filter',
          onPressed: () {},
        ),
        GlassBarItem(label: const Text('Edit'), onPressed: () {}),
      ],
    ),
    toolbar: GlassToolbar(
      items: [
        GlassBarItem(
          icon: const Icon(CupertinoIcons.archivebox),
          semanticLabel: 'Archive',
          onPressed: () {},
        ),
        const GlassBarSpacer.flexible(),
        const GlassBarItem.custom(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Updated just now',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const GlassBarSpacer.flexible(),
        GlassBarItem(
          icon: const Icon(CupertinoIcons.square_pencil),
          semanticLabel: 'Compose',
          onPressed: () {},
        ),
      ],
    ),
    child: GlassContentScroll(
      child: ListView(
        children: [
          for (final (index, sender) in _senders.indexed)
            GlassListRow(
              title: Text(sender),
              subtitle: Text(
                index.isEven
                    ? 'The pages are in: one pass a frame.'
                    : 'See you at ten, in the glass room.',
              ),
              detail: Text('${9 + index % 3}:${10 + index * 3}'),
              onPressed: () {},
            ),
        ],
      ),
    ),
  );
}
