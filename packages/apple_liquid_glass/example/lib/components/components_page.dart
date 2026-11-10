import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:apple_liquid_glass_example/components/presentations.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Every widget of the package, a family to a page, each under its class
/// name: what an app is built from, where the showcase shows what can be
/// built.
class ComponentsPage extends StatelessWidget {
  const ComponentsPage({super.key});

  static const families =
      <(IconData, Color, String, String, Widget Function())>[
        (
          CupertinoIcons.capsule_fill,
          GlassColors.systemBlue,
          'Buttons',
          'GlassButton, GlassPressable',
          ButtonsPage.new,
        ),
        (
          CupertinoIcons.slider_horizontal_3,
          GlassColors.systemGreen,
          'Switches, sliders, steppers',
          'GlassSwitch, GlassSlider, GlassStepper',
          TogglesPage.new,
        ),
        (
          CupertinoIcons.rectangle_split_3x1_fill,
          GlassColors.systemOrange,
          'Segments and pages',
          'GlassSegmentedControl, GlassPageControl',
          SelectionPage.new,
        ),
        (
          CupertinoIcons.calendar,
          GlassColors.systemRed,
          'Date pickers',
          'GlassDatePicker',
          PickersPage.new,
        ),
        (
          CupertinoIcons.list_bullet,
          GlassColors.systemGray,
          'Lists',
          'GlassListSection, GlassListRow, GlassSwipeActions',
          ListsPage.new,
        ),
        (
          CupertinoIcons.ellipsis_circle_fill,
          Color(0xFF5E5CE6),
          'Menus',
          'GlassMenuItem, GlassSubmenu, GlassContextMenu',
          MenusPage.new,
        ),
        (
          CupertinoIcons.exclamationmark_bubble_fill,
          Color(0xFFFF375F),
          'Alerts and action sheets',
          'showGlassAlert, showGlassActionSheet',
          AlertsPage.new,
        ),
        (
          CupertinoIcons.rectangle_stack_fill,
          Color(0xFF40C8E0),
          'Sheets and popovers',
          'showGlassSheet, showGlassPopover',
          SheetsPage.new,
        ),
        (
          CupertinoIcons.rectangle_dock,
          Color(0xFFBF5AF2),
          'Bars and pages',
          'GlassNavigationBar, GlassToolbar, GlassTabBar, GlassBadge',
          BarsPage.new,
        ),
      ];

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Components'),
      trailing: [settingsItem(context)],
    ),
    child: GlassContentScroll(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Every widget of the package, under its class name. Each '
              'works with either renderer and follows the theme.',
              style: TextStyle(
                color: GlassDynamicColor.resolve(
                  GlassColors.secondaryLabel,
                  context,
                ),
                fontSize: 16,
                height: 1.3,
              ),
            ),
          ),
          GlassListSection(
            children: [
              for (final (icon, color, title, widgets, page) in families)
                GlassListRow(
                  leading: SettingsIcon(icon: icon, color: color),
                  title: Text(title),
                  subtitle: Text(widgets),
                  accessory: GlassListAccessory.disclosureIndicator,
                  onPressed: () => Navigator.of(
                    context,
                  ).push(GlassPageRoute<void>(builder: (context) => page())),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A page of the catalog: one family of widgets.
class ComponentPage extends StatelessWidget {
  const ComponentPage({required this.title, required this.slivers, super.key});

  final String title;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: GlassNavigationBar(
      title: Text(title),
      previousPageTitle: 'Components',
    ),
    child: GlassContentScroll(
      child: CustomScrollView(
        slivers: [
          SliverSafeArea(
            sliver: SliverMainAxisGroup(
              slivers: [
                ...slivers,
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A widget of the package: its class name, what it is for and the thing
/// itself. A [flush] child brings its own side margins, as a list section
/// does.
class Demo extends StatelessWidget {
  const Demo(
    this.name,
    this.note, {
    required this.child,
    this.flush = false,
    super.key,
  });

  final String name;
  final String note;
  final Widget child;
  final bool flush;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DemoTitle(name, note),
          ),
          SizedBox(height: flush ? 0 : 12),
          if (flush)
            child
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: child,
            ),
        ],
      ),
    ),
  );
}

/// The class name of a demo and its one line.
class DemoTitle extends StatelessWidget {
  const DemoTitle(this.name, this.note, {super.key});

  final String name;
  final String note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        name,
        style: TextStyle(
          color: GlassDynamicColor.resolve(GlassColors.systemBlue, context),
          fontFamily: 'monospace',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        note,
        style: TextStyle(
          color: GlassDynamicColor.resolve(GlassColors.secondaryLabel, context),
          fontSize: 15,
          height: 1.3,
        ),
      ),
    ],
  );
}

/// A card of the page's grouped color for controls that need no photo.
class Panel extends StatelessWidget {
  const Panel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: GlassDynamicColor.resolve(
        GlassColors.secondarySystemGroupedBackground,
        context,
      ),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24)),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

/// A photo for glass to lie on.
class PhotoPanel extends StatelessWidget {
  const PhotoPanel({required this.wallpaper, required this.child, super.key});

  final Wallpaper wallpaper;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: BorderRadius.circular(24),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image(image: wallpaper.image, fit: BoxFit.cover),
        ),
        Padding(padding: const EdgeInsets.all(20), child: child),
      ],
    ),
  );
}
