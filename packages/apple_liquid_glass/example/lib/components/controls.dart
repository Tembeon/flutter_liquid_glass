import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);

class ButtonsPage extends StatefulWidget {
  const ButtonsPage({super.key});

  @override
  State<ButtonsPage> createState() => _ButtonsPageState();
}

class _ButtonsPageState extends State<ButtonsPage> {
  var _sort = 'Date';
  final _lit = <int>{1};

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Buttons',
    slivers: [
      Demo(
        'GlassButton',
        'A capsule of glass that sinks and glows under the finger: '
            'regular, prominent, clear, tinted clear and disabled.',
        child: PhotoPanel(
          wallpaper: Wallpaper.coast,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  GlassButton(onPressed: () {}, child: const Text('Glass')),
                  GlassButton.prominent(
                    onPressed: () {},
                    child: const Text('Prominent'),
                  ),
                  GlassButton.clear(
                    onPressed: () {},
                    child: const Text('Clear'),
                  ),
                  GlassButton.prominentClear(
                    onPressed: () {},
                    child: const Text('Tinted clear'),
                  ),
                  const GlassButton(onPressed: null, child: Text('Disabled')),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (name, icon) in const [
                    ('Back', CupertinoIcons.backward_fill),
                    ('Play', CupertinoIcons.play_fill),
                    ('Forward', CupertinoIcons.forward_fill),
                  ]) ...[
                    GlassButton(
                      onPressed: () {},
                      semanticLabel: name,
                      child: Icon(icon),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Spacer(),
                  GlassButton.prominent(
                    onPressed: () {},
                    semanticLabel: 'Add',
                    child: const Icon(CupertinoIcons.plus),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      Demo(
        'GlassButton(menuChildren:)',
        'A button that grows into its menu and takes it back.',
        child: PhotoPanel(
          wallpaper: Wallpaper.dunes,
          child: Row(
            children: [
              GlassButton(
                menuChildren: [
                  GlassMenuSection(
                    singleSelection: true,
                    children: [
                      for (final sort in const ['Date', 'Name', 'Size'])
                        GlassMenuItem(
                          title: sort,
                          state: sort == _sort
                              ? GlassMenuItemState.on
                              : GlassMenuItemState.off,
                          onPressed: () => setState(() => _sort = sort),
                        ),
                    ],
                  ),
                ],
                onPressed: null,
                child: Text('Sort by $_sort'),
              ),
              const Spacer(),
              GlassButton(
                semanticLabel: 'More',
                menuChildren: [
                  GlassMenuItem(
                    title: 'Share',
                    icon: const Icon(CupertinoIcons.share),
                    onPressed: () {},
                  ),
                  GlassMenuItem(
                    title: 'Duplicate',
                    icon: const Icon(CupertinoIcons.plus_square_on_square),
                    onPressed: () {},
                  ),
                ],
                onPressed: null,
                child: const Icon(CupertinoIcons.ellipsis),
              ),
            ],
          ),
        ),
      ),
      Demo(
        'GlassPressable',
        'The press, the glow and the semantics of a button around a look '
            'of your own: here round glass that fills with a color.',
        child: PhotoPanel(
          wallpaper: Wallpaper.aurora,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (index, (name, icon, color)) in const [
                ('Flashlight', CupertinoIcons.lightbulb_fill, 0xFFFFD60A),
                ('Favorite', CupertinoIcons.heart_fill, 0xFFFF375F),
                ('Bookmark', CupertinoIcons.bookmark_fill, 0xFF0A84FF),
                ('Mute', CupertinoIcons.bell_slash_fill, 0xFFFF9F0A),
              ].indexed)
                SizedBox.square(
                  dimension: 62,
                  child: GlassPressable(
                    onPressed: () => setState(() {
                      if (!_lit.remove(index)) _lit.add(index);
                    }),
                    shape: const GlassShape.oval(),
                    semanticLabel: name,
                    builder: (context, details) => GlassSurface.live(
                      frame: details.body,
                      glass: Glass.clear(
                        tint: _lit.contains(index) ? Color(color) : null,
                      ),
                      child: Center(child: details.label),
                    ),
                    child: Icon(icon, color: _white, size: 26),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class TogglesPage extends StatefulWidget {
  const TogglesPage({super.key});

  @override
  State<TogglesPage> createState() => _TogglesPageState();
}

class _TogglesPageState extends State<TogglesPage> {
  var _airplane = false;
  var _wifi = true;
  var _volume = 0.6;
  var _warmth = 2.0;
  var _guests = 2.0;
  var _tip = 15.0;

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Switches, sliders, steppers',
    slivers: [
      Demo(
        'GlassSwitch',
        'A knob that lifts into a lens of glass while a finger holds it, '
            'and can be dragged across.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              leading: const SettingsIcon(
                icon: CupertinoIcons.airplane,
                color: GlassColors.systemOrange,
              ),
              title: const Text('Airplane Mode'),
              trailing: GlassSwitch(
                value: _airplane,
                onChanged: (on) => setState(() => _airplane = on),
              ),
            ),
            GlassListRow(
              leading: const SettingsIcon(
                icon: CupertinoIcons.wifi,
                color: GlassColors.systemBlue,
              ),
              title: const Text('Wi-Fi'),
              trailing: GlassSwitch(
                value: _wifi,
                onChanged: (on) => setState(() => _wifi = on),
              ),
            ),
            const GlassListRow(
              title: Text('Unavailable'),
              trailing: GlassSwitch(value: false, onChanged: null),
            ),
          ],
        ),
      ),
      Demo(
        'GlassSlider',
        'Continuous, or snapping to ticks. Its knob is a lens too, and the '
            'track stretches when it is pulled past an end.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              child: Row(
                children: [
                  const Icon(CupertinoIcons.speaker_fill, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassSlider(
                      value: _volume,
                      semanticLabel: 'Volume',
                      onChanged: (value) => setState(() => _volume = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(CupertinoIcons.speaker_3_fill, size: 18),
                ],
              ),
            ),
            GlassListRow(
              child: Row(
                children: [
                  const Icon(CupertinoIcons.snow, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassSlider(
                      value: _warmth,
                      max: 4,
                      ticks: 5,
                      semanticLabel: 'Warmth',
                      onChanged: (value) => setState(() => _warmth = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(CupertinoIcons.flame_fill, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
      Demo(
        'GlassStepper',
        'Two halves that count up and down, and repeat while held.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Guests'),
              detail: Text('${_guests.round()}'),
              trailing: GlassStepper(
                value: _guests,
                min: 1,
                max: 12,
                onChanged: (value) => setState(() => _guests = value),
              ),
            ),
            GlassListRow(
              title: const Text('Tip'),
              detail: Text('${_tip.round()}%'),
              trailing: GlassStepper(
                value: _tip,
                max: 30,
                step: 5,
                onChanged: (value) => setState(() => _tip = value),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class SelectionPage extends StatefulWidget {
  const SelectionPage({super.key});

  @override
  State<SelectionPage> createState() => _SelectionPageState();
}

class _SelectionPageState extends State<SelectionPage> {
  final _pages = PageController();
  var _range = 'Week';
  var _layout = 0;
  var _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Segments and pages',
    slivers: [
      Demo(
        'GlassSegmentedControl',
        'A lens that slides between segments of text or icons, under a '
            'tap or a dragging finger.',
        child: Panel(
          child: Column(
            children: [
              GlassSegmentedControl<String>(
                segments: const [
                  GlassSegment(value: 'Day', label: Text('Day')),
                  GlassSegment(value: 'Week', label: Text('Week')),
                  GlassSegment(value: 'Month', label: Text('Month')),
                  GlassSegment(value: 'Year', label: Text('Year')),
                ],
                groupValue: _range,
                onChanged: (range) => setState(() => _range = range),
              ),
              const SizedBox(height: 16),
              GlassSegmentedControl<int>(
                segments: const [
                  GlassSegment(
                    value: 0,
                    label: Icon(CupertinoIcons.list_bullet),
                    semanticLabel: 'List',
                  ),
                  GlassSegment(
                    value: 1,
                    label: Icon(CupertinoIcons.square_grid_2x2),
                    semanticLabel: 'Grid',
                  ),
                  GlassSegment(
                    value: 2,
                    label: Icon(CupertinoIcons.rectangle_stack),
                    semanticLabel: 'Gallery',
                  ),
                ],
                groupValue: _layout,
                onChanged: (layout) => setState(() => _layout = layout),
              ),
            ],
          ),
        ),
      ),
      Demo(
        'GlassPageControl',
        'Dots that follow a pager as it turns, and scrub it under a '
            'finger.',
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView(
                  controller: _pages,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    for (final wallpaper in Wallpaper.values)
                      Image(image: wallpaper.image, fit: BoxFit.cover),
                  ],
                ),
                Align(
                  alignment: const Alignment(0, 0.86),
                  child: AnimatedBuilder(
                    animation: _pages,
                    builder: (context, _) => GlassPageControl(
                      count: Wallpaper.values.length,
                      page: _page,
                      progress: _pages.hasClients ? _pages.page : null,
                      backgroundStyle: GlassPageControlBackground.prominent,
                      onChanged: (page) => _pages.animateToPage(
                        page,
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class PickersPage extends StatefulWidget {
  const PickersPage({super.key});

  @override
  State<PickersPage> createState() => _PickersPageState();
}

class _PickersPageState extends State<PickersPage> {
  var _dinner = DateTime(2026, 6, 12, 19, 30);
  var _trip = DateTime(2026, 8, 3);
  var _alarm = DateTime(2026, 1, 1, 7, 15);

  @override
  Widget build(BuildContext context) => ComponentPage(
    title: 'Date pickers',
    slivers: [
      Demo(
        'GlassDatePicker',
        'A date, a time or both in a compact field. A tap opens its '
            'calendar or its wheels out of the field.',
        flush: true,
        child: GlassListSection(
          children: [
            // A date and a time take a line of their own at large text.
            GlassListRow(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dinner'),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: GlassDatePicker(
                      value: _dinner,
                      mode: GlassDatePickerMode.dateAndTime,
                      minuteInterval: 5,
                      onChanged: (date) => setState(() => _dinner = date),
                    ),
                  ),
                ],
              ),
            ),
            GlassListRow(
              title: const Text('Trip'),
              trailing: GlassDatePicker(
                value: _trip,
                onChanged: (date) => setState(() => _trip = date),
              ),
            ),
            GlassListRow(
              title: const Text('Alarm'),
              trailing: GlassDatePicker(
                value: _alarm,
                mode: GlassDatePickerMode.time,
                onChanged: (date) => setState(() => _alarm = date),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class ListsPage extends StatefulWidget {
  const ListsPage({super.key});

  @override
  State<ListsPage> createState() => _ListsPageState();
}

class _ListsPageState extends State<ListsPage> {
  static const _more = ['Call the bank', 'Water the plants', 'Book a table'];

  final _reminders = ['Buy milk', 'Send the invoice', 'Pick up the keys'];
  var _next = 0;
  var _checked = 1;

  void _change(VoidCallback change) =>
      withSpring(Spring.smooth, () => setState(change));

  @override
  Widget build(BuildContext context) {
    const add = #add;
    final ids = <Object>[..._reminders, add];
    return ComponentPage(
      title: 'Lists',
      slivers: [
        Demo(
          'GlassListSection, GlassListRow',
          'Grouped rows that highlight under a press and carry icons, '
              'details and the accessories of a settings list.',
          flush: true,
          child: GlassListSection(
            children: [
              GlassListRow(
                leading: const SettingsIcon(
                  icon: CupertinoIcons.person_crop_circle_fill,
                  color: GlassColors.systemGray,
                ),
                title: const Text('Account'),
                subtitle: const Text('Name, phone, email'),
                accessory: GlassListAccessory.disclosureIndicator,
                onPressed: () {},
              ),
              for (final (index, name) in const [
                'Small',
                'Medium',
                'Large',
              ].indexed)
                GlassListRow(
                  title: Text(name),
                  accessory: _checked == index
                      ? GlassListAccessory.checkmark
                      : null,
                  onPressed: () => setState(() => _checked = index),
                ),
              GlassListRow(
                title: const Text('Storage'),
                detail: const Text('42 GB'),
                accessory: GlassListAccessory.detailDisclosureButton,
                onAccessoryPressed: () {},
                onPressed: () {},
              ),
              const GlassListRow(title: Text('Unavailable'), enabled: false),
            ],
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 26, 20, 0),
            child: DemoTitle(
              'GlassSwipeActions, GlassSliverListSection',
              'Rows that come and go on a spring. Swipe a row for its '
                  'actions; a full swipe takes the first.',
            ),
          ),
        ),
        GlassSliverListSection(
          ids: ids,
          itemCount: ids.length,
          itemBuilder: (context, i) {
            final id = ids[i];
            if (id == add) {
              return GlassListRow(
                leading: const SettingsIcon(
                  icon: CupertinoIcons.plus,
                  color: GlassColors.systemBlue,
                ),
                title: const Text('Add Reminder'),
                onPressed: () => _change(() {
                  final round = _next ~/ _more.length;
                  final name = _more[_next++ % _more.length];
                  _reminders.add(round == 0 ? name : '$name ${round + 1}');
                }),
              );
            }
            final reminder = id as String;
            return GlassSwipeActions(
              trailing: [
                GlassSwipeAction(
                  title: 'Delete',
                  destructive: true,
                  onPressed: () => _change(() => _reminders.remove(reminder)),
                ),
                GlassSwipeAction(
                  title: 'Top',
                  backgroundColor: GlassColors.systemOrange,
                  onPressed: () => _change(() {
                    _reminders
                      ..remove(reminder)
                      ..insert(0, reminder);
                  }),
                ),
              ],
              child: GlassListRow(title: Text(reminder)),
            );
          },
        ),
      ],
    );
  }
}
