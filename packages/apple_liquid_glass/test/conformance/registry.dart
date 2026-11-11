import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'reference.dart';

/// Every public interactive widget of the package, and the reference
/// controls that calibrate the checks.
final List<Entry> registry = [
  Entry(
    'GlassButton',
    covers: const ['GlassButton'],
    kind: Kind.pressable,
    build: (probe, {required enabled}) => GlassButton(
      onPressed: enabled ? () => probe.add('pressed') : null,
      child: const Text('Save'),
    ),
  ),
  Entry(
    'GlassButton.prominent',
    covers: const [],
    kind: Kind.pressable,
    build: (probe, {required enabled}) => GlassButton.prominent(
      onPressed: enabled ? () => probe.add('pressed') : null,
      child: const Text('Save'),
    ),
  ),
  Entry(
    'GlassPressable',
    covers: const ['GlassPressable'],
    look: Look.builder,
    kind: Kind.pressable,
    build: (probe, {required enabled}) => GlassPressable(
      onPressed: enabled ? () => probe.add('pressed') : null,
      builder: (context, details) {
        probe.states = details.states;
        return GlassSurface.live(frame: details.body, child: details.label);
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: GlassDefaultTextStyle(
          role: GlassTextRole.body,
          child: Text('Press'),
        ),
      ),
    ),
  ),
  Entry(
    'GlassButton.menu',
    covers: const [
      'GlassMenuController',
      'GlassMenuDeferred',
      'GlassMenuDivider',
      'GlassMenuItem',
      'GlassMenuSection',
      'GlassMenuWidget',
      'GlassSubmenu',
    ],
    kind: Kind.opener,
    canDisable: false,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => GlassButton(
      onPressed: null,
      semanticLabel: 'More',
      menuChildren: _menu(probe),
      child: const Text('More'),
    ),
  ),
  Entry(
    'RawGlassMenu',
    covers: const ['RawGlassMenu'],
    kind: Kind.opener,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => RawGlassMenu(
      enabled: enabled,
      entries: _menu(probe),
      label: const Text('Menu'),
      child: const SizedBox(
        width: 120,
        height: 44,
        child: Center(child: Text('Menu')),
      ),
    ),
  ),
  Entry(
    'GlassContextMenu',
    covers: const ['GlassContextMenu'],
    kind: Kind.opener,
    openGesture: OpenGesture.longPress,
    contextMenu: true,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => GlassContextMenu(
      enabled: enabled,
      menuChildren: _menu(probe),
      child: const SizedBox(
        width: 120,
        height: 80,
        child: ColoredBox(
          color: Color(0xFF3478F6),
          child: Center(child: Text('Photo')),
        ),
      ),
    ),
  ),
  Entry(
    'GlassSwitch',
    covers: const ['GlassSwitch'],
    kind: Kind.toggle,
    build: (probe, {required enabled}) => Held<bool>(
      probe: probe,
      initial: false,
      builder: (context, value, set) => GlassSwitch(
        value: value,
        semanticLabel: 'Wi-Fi',
        onChanged: enabled ? set : null,
      ),
    ),
  ),
  Entry(
    'RawGlassSwitch',
    covers: const ['RawGlassSwitch'],
    look: Look.builder,
    kind: Kind.toggle,
    build: (probe, {required enabled}) => Held<bool>(
      probe: probe,
      initial: false,
      builder: (context, value, set) => RawGlassSwitch(
        value: value,
        semanticLabel: 'Wi-Fi',
        onChanged: enabled ? set : null,
        builder: (context, details) {
          probe.states = details.states;
          return GlassSurface.live(
            frame: details.thumb,
            child: const SizedBox.expand(),
          );
        },
      ),
    ),
  ),
  Entry(
    'GlassSlider',
    covers: const ['GlassSlider'],
    kind: Kind.value,
    build: (probe, {required enabled}) => SizedBox(
      width: 300,
      child: Held<double>(
        probe: probe,
        initial: 0.5,
        builder: (context, value, set) => GlassSlider(
          value: value,
          semanticLabel: 'Volume',
          onChanged: enabled ? set : null,
        ),
      ),
    ),
  ),
  Entry(
    'RawGlassSlider',
    covers: const ['RawGlassSlider'],
    look: Look.builder,
    kind: Kind.value,
    build: (probe, {required enabled}) => SizedBox(
      width: 300,
      child: Held<double>(
        probe: probe,
        initial: 0.5,
        builder: (context, value, set) => RawGlassSlider(
          value: value,
          semanticLabel: 'Volume',
          onChanged: enabled ? set : null,
          builder: (context, details) {
            probe.states = details.states;
            return GlassSurface.live(
              frame: details.thumb,
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    ),
  ),
  Entry(
    'GlassStepper',
    covers: const ['GlassStepper'],
    kind: Kind.value,
    mirrors: false,
    build: (probe, {required enabled}) => Held<double>(
      probe: probe,
      initial: 5,
      builder: (context, value, set) => GlassStepper(
        value: value,
        max: 10,
        onChanged: enabled ? set : null,
      ),
    ),
  ),
  Entry(
    'RawGlassStepper',
    covers: const ['RawGlassStepper'],
    look: Look.builder,
    kind: Kind.value,
    mirrors: false,
    build: (probe, {required enabled}) => Held<double>(
      probe: probe,
      initial: 5,
      builder: (context, value, set) => RawGlassStepper(
        value: value,
        max: 10,
        onChanged: enabled ? set : null,
        builder: (context, details) {
          probe.states = details.states;
          return const ColoredBox(color: Color(0xFFE5E5EA));
        },
      ),
    ),
  ),
  Entry(
    'GlassPageControl',
    covers: const ['GlassPageControl'],
    kind: Kind.value,
    build: (probe, {required enabled}) => Held<int>(
      probe: probe,
      initial: 2,
      builder: (context, value, set) => GlassPageControl(
        count: 5,
        page: value,
        semanticLabel: 'Page',
        onChanged: enabled ? set : null,
      ),
    ),
  ),
  Entry(
    'RawGlassPageControl',
    covers: const ['RawGlassPageControl'],
    look: Look.builder,
    kind: Kind.value,
    build: (probe, {required enabled}) => Held<int>(
      probe: probe,
      initial: 2,
      builder: (context, value, set) => RawGlassPageControl(
        count: 5,
        page: value,
        semanticLabel: 'Page',
        onChanged: enabled ? set : null,
        builder: (context, details) {
          probe.states = details.states;
          return const ColoredBox(color: Color(0xFF8E8E93));
        },
      ),
    ),
  ),
  Entry(
    'GlassSegmentedControl',
    covers: const ['GlassSegmentedControl', 'GlassSegment'],
    kind: Kind.selection,
    build: (probe, {required enabled}) => SizedBox(
      width: 300,
      child: Held<int>(
        probe: probe,
        initial: 0,
        builder: (context, value, set) => GlassSegmentedControl<int>(
          groupValue: value,
          semanticLabel: 'View',
          onChanged: enabled ? set : null,
          segments: const [
            GlassSegment(value: 0, label: Text('Day')),
            GlassSegment(value: 1, label: Text('Week')),
            GlassSegment(value: 2, label: Text('Month')),
          ],
        ),
      ),
    ),
  ),
  Entry(
    'RawGlassSelector',
    covers: const ['RawGlassSelector'],
    look: Look.builder,
    kind: Kind.selection,
    build: (probe, {required enabled}) => SizedBox(
      width: 300,
      height: 36,
      child: Held<int>(
        probe: probe,
        initial: 0,
        builder: (context, value, set) => RawGlassSelector(
          itemCount: 3,
          selectedIndex: value,
          semanticLabel: 'View',
          itemLabels: const ['Day', 'Week', 'Month'],
          onChanged: enabled ? set : null,
          itemBuilder: (context, index, states) => Center(
            child: GlassDefaultTextStyle(
              role: GlassTextRole.body,
              child: Text(const ['Day', 'Week', 'Month'][index]),
            ),
          ),
          builder: (context, details) {
            probe.states = details.states;
            return details.items();
          },
        ),
      ),
    ),
  ),
  Entry(
    'GlassTabBar',
    covers: const ['GlassTabBar', 'GlassTabDestination'],
    kind: Kind.selection,
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      child: Held<int>(
        probe: probe,
        initial: 0,
        builder: (context, value, set) => GlassTabBar(
          selectedIndex: value,
          onDestinationSelected: enabled ? set : null,
          destinations: _tabs,
        ),
      ),
    ),
  ),
  Entry(
    'GlassTabBar.search',
    covers: const ['GlassSearchController'],
    kind: Kind.selection,
    canDisable: false,
    focusStops: 2,
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      child: _Owned<GlassSearchController>(
        create: GlassSearchController.new,
        dispose: (controller) => controller.dispose(),
        builder: (context, controller) => Held<int>(
          probe: probe,
          initial: 0,
          builder: (context, value, set) => GlassTabBar(
            selectedIndex: value,
            searchController: controller,
            onDestinationSelected: enabled ? set : null,
            destinations: _tabs,
          ),
        ),
      ),
    ),
  ),
  Entry(
    'GlassSearchField',
    covers: const ['GlassSearchField'],
    kind: Kind.textInput,
    build: (probe, {required enabled}) => SizedBox(
      width: 340,
      child: GlassSearchField(
        enabled: enabled,
        onChanged: (text) => probe.add('text $text'),
      ),
    ),
  ),
  Entry(
    'GlassSearchField.clear',
    covers: const [],
    kind: Kind.pressable,
    canDisable: false,
    focusStops: 2,
    part: find.byWidgetPredicate(
      (widget) => widget is InputRegion && widget.semanticLabel == 'Clear text',
    ),
    build: (probe, {required enabled}) => SizedBox(
      width: 340,
      child: _Owned<TextEditingController>(
        create: () => TextEditingController(text: 'glass'),
        dispose: (controller) => controller.dispose(),
        builder: (context, controller) => GlassSearchField(
          controller: controller,
          onChanged: (text) => probe.add('text $text'),
        ),
      ),
    ),
  ),
  Entry(
    'RawGlassSearchField',
    covers: const ['RawGlassSearchField'],
    look: Look.builder,
    kind: Kind.textInput,
    build: (probe, {required enabled}) => SizedBox(
      width: 340,
      height: 44,
      child: RawGlassSearchField(
        enabled: enabled,
        semanticLabel: 'Search',
        onChanged: (text) => probe.add('text $text'),
        builder: (context, details) {
          probe.states = details.states;
          return details.text(
            style: const TextStyle(fontSize: 17, color: Color(0xFF000000)),
            cursorColor: const Color(0xFF0000FF),
            backgroundCursorColor: const Color(0xFF808080),
          );
        },
      ),
    ),
  ),
  Entry(
    'GlassListRow',
    covers: const ['GlassListRow'],
    kind: Kind.pressable,
    part: find.text('General'),
    header: 'Settings',
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      child: GlassListSection(
        header: const Text('Settings'),
        children: [
          GlassListRow(
            title: const Text('General'),
            accessory: GlassListAccessory.disclosureIndicator,
            enabled: enabled,
            onPressed: () => probe.add('pressed'),
          ),
        ],
      ),
    ),
  ),
  Entry(
    'GlassListRow.detail',
    covers: const ['GlassListAccessory'],
    kind: Kind.pressable,
    part: semanticsWidget('More info'),
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      child: GlassListSection(
        children: [
          GlassListRow(
            title: const Text('Network'),
            accessory: GlassListAccessory.detailButton,
            enabled: enabled,
            onAccessoryPressed: () => probe.add('pressed'),
          ),
        ],
      ),
    ),
  ),
  Entry(
    'GlassSwipeActions',
    covers: const ['GlassSwipeActions', 'GlassSwipeAction'],
    kind: Kind.actions,
    canDisable: false,
    focusStops: 2,
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      child: GlassSwipeActions(
        trailing: [
          GlassSwipeAction(
            title: 'Flag',
            onPressed: () => probe.add('Flag'),
          ),
          GlassSwipeAction(
            title: 'Delete',
            destructive: true,
            onPressed: () => probe.add('Delete'),
          ),
        ],
        child: const GlassListRow(title: Text('Message')),
      ),
    ),
  ),
  Entry(
    'GlassDatePicker.compact',
    covers: const [
      'GlassDatePicker',
      'GlassDatePickerMode',
      'GlassDatePickerVariant',
    ],
    kind: Kind.opener,
    marker: find.text('October 2026'),
    inside: find.text('15'),
    build: (probe, {required enabled}) => Held<DateTime>(
      probe: probe,
      initial: DateTime(2026, 10, 3, 9, 41),
      builder: (context, value, set) => GlassDatePicker(
        value: value,
        today: DateTime(2026, 10, 3),
        semanticLabel: 'Date',
        onChanged: enabled ? set : null,
      ),
    ),
  ),
  Entry(
    'GlassNavigationBar',
    covers: const ['GlassNavigationBar', 'GlassBarItem'],
    kind: Kind.pressable,
    focusStops: 2,
    header: 'Inbox',
    part: find.text('Edit'),
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      height: 200,
      child: GlassPageScaffold(
        navigationBar: GlassNavigationBar(
          title: const Text('Inbox'),
          leading: [
            GlassBarItem(
              label: const Text('Edit'),
              onPressed: enabled ? () => probe.add('pressed') : null,
            ),
          ],
          trailing: [
            GlassBarItem(
              icon: const SizedBox.square(dimension: 22),
              semanticLabel: 'Compose',
              onPressed: enabled ? () => probe.add('compose') : null,
            ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    ),
  ),
  Entry(
    'GlassToolbar',
    covers: const ['GlassToolbar', 'GlassBarSpacer'],
    kind: Kind.pressable,
    focusStops: 2,
    part: find.text('Edit'),
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      height: 200,
      child: GlassPageScaffold(
        toolbar: GlassToolbar(
          items: [
            GlassBarItem(
              label: const Text('Edit'),
              onPressed: enabled ? () => probe.add('pressed') : null,
            ),
            const GlassBarSpacer.flexible(),
            GlassBarItem.prominent(
              label: const Text('Done'),
              onPressed: enabled ? () => probe.add('done') : null,
            ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    ),
  ),
  Entry(
    'GlassBarItem.menu',
    covers: const [],
    kind: Kind.opener,
    canDisable: false,
    part: find.text('Sort'),
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => SizedBox(
      width: 402,
      height: 200,
      child: GlassPageScaffold(
        toolbar: GlassToolbar(
          items: [
            GlassBarItem(label: const Text('Sort'), menuChildren: _menu(probe)),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    ),
  ),
  Entry(
    'GlassPageRoute',
    covers: const [
      'GlassPageRoute',
      'GlassBackButtonDisplayMode',
    ],
    kind: Kind.overlay,
    dismissible: false,
    glassRoutes: true,
    marker: find.text(overlayText),
    build: (probe, {required enabled}) => Opener(
      show: (context) => Navigator.of(context).push(
        GlassPageRoute<void>(
          builder: (context) => const GlassPageScaffold(
            navigationBar: GlassNavigationBar(
              title: Text(overlayText),
              previousPageTitle: 'Home',
            ),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  ),
  Entry(
    'showGlassAlert',
    covers: const ['showGlassAlert', 'GlassAlertAction'],
    kind: Kind.overlay,
    dismissible: false,
    marker: find.text(overlayText),
    inside: find.text('OK'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => showGlassAlert(
        context,
        title: const Text(overlayText),
        actions: [
          const GlassAlertAction.cancel(child: Text('Cancel')),
          GlassAlertAction(
            onPressed: () => probe.add('inside'),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  ),
  Entry(
    'showGlassActionSheet',
    covers: const ['showGlassActionSheet'],
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Share'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => showGlassActionSheet(
        context,
        title: const Text(overlayText),
        actions: [
          GlassAlertAction(
            onPressed: () => probe.add('inside'),
            child: const Text('Share'),
          ),
          const GlassAlertAction.cancel(child: Text('Cancel')),
        ],
      ),
    ),
  ),
  Entry(
    'showGlassSheet',
    covers: const ['showGlassSheet', 'GlassSheet', 'GlassSheetDetent'],
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Inside'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => showGlassSheet<void>(
        context,
        semanticLabel: 'Sheet',
        detents: const [GlassSheetDetent.medium, GlassSheetDetent.large],
        builder: (context) => _content(probe),
      ),
    ),
  ),
  Entry(
    'showGlassPopover',
    covers: const ['showGlassPopover'],
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Inside'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => showGlassPopover<void>(
        context,
        anchor: context,
        semanticLabel: 'Popover',
        builder: (context) => _content(probe),
      ),
    ),
  ),
  ...references,
];

/// Public widgets that take no input, each with the reason.
const Map<String, String> nonInteractive = {
  'GlassBadge': 'a label drawn on another control; announces its text only',
  'GlassBarEntry': 'the sealed base of GlassBarItem and GlassBarSpacer',
  'GlassClip': 'clips its child to a glass shape',
  'GlassContentScroll':
      'reports scroll edges to the bars; the scrollable '
      'inside it takes the input',
  'GlassDefaultTextStyle': 'provides a text style to its subtree',
  'GlassGroup': 'merges the glass of its children',
  'GlassListBackground': 'paints the grouped background behind sections',
  'GlassListSection': 'lays out rows and a header; its rows are entries',
  'GlassMenuEntry': 'the sealed base of the menu entries',
  'GlassPageScaffold': 'lays out bars around content; its bars are entries',
  'GlassRendererScope': 'provides the renderer to its subtree',
  'GlassScope': 'the root widget: theme and renderer',
  'GlassSliverListSection': 'the sliver form of GlassListSection',
  'GlassSolidBackdrop': 'tells glass what is behind it',
  'GlassSurface': 'draws glass behind a child',
  'GlassTabScaffold': 'switches tab pages; its tab bar is an entry',
  'GlassTheme': 'provides the theme to its subtree',
  'GlassTraitsOverride': 'overrides accessibility traits for its subtree',
  'GlassZoomSource': 'marks a child as the source of a zoom transition',
  'RawGlassList': 'animates the layout of keyed children',
};

const _tabs = [
  GlassTabDestination(
    icon: SizedBox.square(dimension: 24),
    label: Text('Home'),
  ),
  GlassTabDestination(
    icon: SizedBox.square(dimension: 24),
    label: Text('Library'),
  ),
  GlassTabDestination(
    icon: SizedBox.square(dimension: 24),
    label: Text('Settings'),
  ),
];

List<GlassMenuEntry> _menu(Probe probe) => [
  GlassMenuItem(title: 'First item', onPressed: () => probe.add('inside')),
  GlassMenuItem(title: 'Second item', onPressed: () => probe.add('second')),
  const GlassMenuDivider(),
  GlassMenuSection(
    title: 'Section',
    children: [
      GlassMenuItem(
        title: 'Checked',
        state: GlassMenuItemState.on,
        onPressed: () => probe.add('checked'),
      ),
    ],
  ),
  GlassSubmenu(
    title: 'More',
    children: [
      GlassMenuItem(title: 'Nested', onPressed: () => probe.add('nested')),
    ],
  ),
  GlassMenuWidget(
    height: 44,
    builder: (context) => const Center(child: Text('Widget row')),
  ),
  GlassMenuDeferred(
    () async => [GlassMenuItem(title: 'Loaded', onPressed: () {})],
  ),
];

Widget _content(Probe probe) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Padding(
      padding: EdgeInsets.all(16),
      child: Text(overlayText),
    ),
    ProbeButton(label: 'Inside', onPressed: () => probe.add('inside')),
  ],
);

class _Owned<T extends Object> extends StatefulWidget {
  const _Owned({
    required this.create,
    required this.dispose,
    required this.builder,
  });

  final T Function() create;
  final void Function(T value) dispose;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_Owned<T>> createState() => _OwnedState<T>();
}

class _OwnedState<T extends Object> extends State<_Owned<T>> {
  late final T _value = widget.create();

  @override
  void dispose() {
    widget.dispose(_value);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
