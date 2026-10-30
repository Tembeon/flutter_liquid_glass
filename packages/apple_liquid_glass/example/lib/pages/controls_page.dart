import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Every control of the package in grouped lists, as an iOS Settings page.
class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

enum _Range { day, week, month, year }

enum _Layout { list, grid, gallery }

class _ControlsPageState extends State<ControlsPage> {
  final _query = GlassSearchController();
  final _pages = PageController();
  var _page = 0;
  var _airplane = false;
  var _wifi = true;
  var _focus = true;
  var _volume = 0.6;
  var _warmth = 2.0;
  var _guests = 2.0;
  var _tip = 15.0;
  var _range = _Range.week;
  var _layout = _Layout.grid;
  var _date = DateTime(2026, 11, 14, 19, 30);
  var _trip = DateTime(2026, 12, 20);
  var _alarm = DateTime(2026, 11, 15, 7, 15);
  var _checked = 1;

  @override
  void initState() {
    super.initState();
    _query.addListener(_search);
  }

  @override
  void dispose() {
    _query.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _search() => setState(() {});

  bool _shows(String section) => section.toLowerCase().contains(
    _query.text.trim().toLowerCase(),
  );

  @override
  Widget build(BuildContext context) {
    final sections = <(String, Widget)>[
      ('Page control', _carousel()),
      ('Switches', _switches()),
      ('Sliders', _sliders()),
      ('Steppers', _steppers()),
      ('Segmented controls', _segments()),
      ('Buttons', _buttons()),
      ('Date pickers', _dates()),
      ('Lists', _lists()),
    ];
    return GlassPageScaffold(
      backgroundColor: GlassColors.systemGroupedBackground,
      navigationBar: GlassNavigationBar(
        largeTitle: const Text('Controls'),
        trailing: [settingsItem(context)],
        searchField: GlassSearchField(
          controller: _query,
          placeholder: const Text('Search controls'),
        ),
      ),
      child: GlassContentScroll(
        child: ListView(
          children: [
            for (final (title, section) in sections)
              if (_shows(title)) section,
          ],
        ),
      ),
    );
  }

  Widget _carousel() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: ClipRSuperellipse(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 240,
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: ListenableBuilder(
                  listenable: _pages,
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
            ),
            Positioned(
              left: 20,
              top: 16,
              child: PhotoText(
                Wallpaper.values[_page].title,
                size: 22,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _switches() => GlassListSection(
    header: const Text('Switches'),
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
      GlassListRow(
        leading: const SettingsIcon(
          icon: CupertinoIcons.moon_fill,
          color: GlassDynamicColor.withBrightness(
            color: Color(0xFF5856D6),
            darkColor: Color(0xFF5E5CE6),
          ),
        ),
        title: const Text('Focus'),
        subtitle: Text(_focus ? 'Do Not Disturb' : 'Off'),
        trailing: GlassSwitch(
          value: _focus,
          onChanged: (on) => setState(() => _focus = on),
        ),
      ),
    ],
  );

  Widget _sliders() => GlassListSection(
    header: const Text('Sliders'),
    footer: const Text('The second slider snaps to its five ticks.'),
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
  );

  Widget _steppers() => GlassListSection(
    header: const Text('Steppers'),
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
  );

  Widget _segments() => GlassListSection(
    header: const Text('Segmented controls'),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: GlassSegmentedControl<_Range>(
          segments: const [
            GlassSegment(value: _Range.day, label: Text('Day')),
            GlassSegment(value: _Range.week, label: Text('Week')),
            GlassSegment(value: _Range.month, label: Text('Month')),
            GlassSegment(value: _Range.year, label: Text('Year')),
          ],
          groupValue: _range,
          onChanged: (range) => setState(() => _range = range),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: GlassSegmentedControl<_Layout>(
            segments: const [
              GlassSegment(
                value: _Layout.list,
                label: Icon(CupertinoIcons.list_bullet),
                semanticLabel: 'List',
              ),
              GlassSegment(
                value: _Layout.grid,
                label: Icon(CupertinoIcons.square_grid_2x2),
                semanticLabel: 'Grid',
              ),
              GlassSegment(
                value: _Layout.gallery,
                label: Icon(CupertinoIcons.rectangle_stack),
                semanticLabel: 'Gallery',
              ),
            ],
            groupValue: _layout,
            onChanged: (layout) => setState(() => _layout = layout),
          ),
        ),
      ),
    ],
  );

  Widget _buttons() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: ClipRSuperellipse(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image(image: Wallpaper.coast.image, fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PhotoText('Buttons', size: 22, weight: FontWeight.w700),
                const SizedBox(height: 16),
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
                    const GlassButton(
                      onPressed: null,
                      child: Text('Disabled'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final icon in const [
                      CupertinoIcons.backward_fill,
                      CupertinoIcons.play_fill,
                      CupertinoIcons.forward_fill,
                    ]) ...[
                      GlassButton(onPressed: () {}, child: Icon(icon)),
                      const SizedBox(width: 12),
                    ],
                    const Spacer(),
                    GlassButton.prominent(
                      onPressed: () {},
                      child: const Icon(CupertinoIcons.plus),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dates() => GlassListSection(
    header: const Text('Date pickers'),
    footer: const Text('Tap a date or a time: its calendar or wheels open.'),
    children: [
      GlassListRow(
        title: const Text('Dinner'),
        trailing: GlassDatePicker(
          value: _date,
          mode: GlassDatePickerMode.dateAndTime,
          minuteInterval: 5,
          onChanged: (date) => setState(() => _date = date),
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
  );

  Widget _lists() => GlassListSection(
    header: const Text('Lists'),
    footer: const Text('Rows highlight on press and carry UIKit accessories.'),
    children: [
      GlassListRow(
        leading: const SettingsIcon(
          icon: CupertinoIcons.person_crop_circle_fill,
          color: GlassColors.systemGray,
        ),
        title: const Text('Account'),
        subtitle: const Text('Apple ID, iCloud, Media'),
        accessory: GlassListAccessory.disclosureIndicator,
        onPressed: () {},
      ),
      for (final (index, name) in const ['Small', 'Medium', 'Large'].indexed)
        GlassListRow(
          title: Text(name),
          accessory: _checked == index ? GlassListAccessory.checkmark : null,
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
  );
}
