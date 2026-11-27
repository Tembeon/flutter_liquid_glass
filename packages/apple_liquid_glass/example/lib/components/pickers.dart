import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum _DateForm { compact, inline, wheels, timer, month }

class DatePickerPage extends StatefulWidget {
  const DatePickerPage({super.key});

  @override
  State<DatePickerPage> createState() => _DatePickerPageState();
}

class _DatePickerPageState extends State<DatePickerPage> {
  var _date = DateTime(2026, 6, 12, 8, 30);
  var _mode = GlassDatePickerMode.date;
  var _form = _DateForm.compact;
  var _fives = false;
  var _brand = Brand.system;
  var _repot = DateTime(2026, 8, 3);
  var _timer = const Duration(hours: 1, minutes: 30);
  var _alarm = DateTime(2026, 1, 1, 7, 15);

  @override
  Widget build(BuildContext context) {
    final style = _brand.color == null
        ? null
        : GlassDatePickerStyle(accentColor: _brand.color);
    void changed(DateTime date) => setState(() => _date = date);
    return ComponentPage(
      name: 'GlassCompactDatePicker',
      summary:
          'A date, a time or both: a compact field that opens its calendar '
          'or its wheels out of itself, GlassDatePicker, the calendar in '
          'place, or GlassTimePicker, the time wheels in place.',
      stageHeight: switch (_form) {
        _DateForm.compact => 120,
        _DateForm.inline => 360,
        _DateForm.wheels => 240,
        _DateForm.timer || _DateForm.month => 256,
      },
      stage: FittedBox(
        fit: BoxFit.scaleDown,
        child: switch (_form) {
          _DateForm.inline => GlassDatePicker(
            value: _date,
            style: style,
            onChanged: changed,
          ),
          _DateForm.wheels => GlassTimePicker(
            value: _date,
            minuteInterval: _fives ? 5 : 1,
            style: style,
            onChanged: changed,
          ),
          _DateForm.timer => GlassCountDownPicker(
            value: _timer,
            minuteInterval: _fives ? 5 : 1,
            style: style,
            onChanged: (timer) => setState(() => _timer = timer),
          ),
          _DateForm.month => GlassMonthYearPicker(
            value: _date,
            style: style,
            onChanged: changed,
          ),
          _DateForm.compact => GlassCompactDatePicker(
            value: _date,
            mode: _mode,
            minuteInterval: _fives ? 5 : 1,
            style: style,
            onChanged: changed,
          ),
        },
      ),
      knobs: [
        ChoiceKnob<_DateForm>(
          'Form',
          value: _form,
          options: const {
            _DateForm.compact: 'Compact',
            _DateForm.inline: 'Calendar',
            _DateForm.wheels: 'Wheels',
            _DateForm.timer: 'Timer',
            _DateForm.month: 'Month',
          },
          onChanged: (form) => setState(() => _form = form),
        ),
        ChoiceKnob<GlassDatePickerMode>(
          'Mode',
          value: _mode,
          options: const {
            GlassDatePickerMode.date: 'Date',
            GlassDatePickerMode.time: 'Time',
            GlassDatePickerMode.dateAndTime: 'Both',
          },
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        ToggleKnob(
          'Minutes by five',
          value: _fives,
          onChanged: (on) => setState(() => _fives = on),
        ),
        ChoiceKnob<Brand>(
          'Colors',
          value: _brand,
          options: Brand.names,
          onChanged: (brand) => setState(() => _brand = brand),
        ),
      ],
      ideas: [
        Idea(
          'In a list',
          'The compact field at the end of a row.',
          flush: true,
          child: GlassListSection(
            children: [
              GlassListRow(
                title: const Text('Repot'),
                trailing: GlassCompactDatePicker(
                  value: _repot,
                  onChanged: (date) => setState(() => _repot = date),
                ),
              ),
              GlassListRow(
                title: const Text('Morning mist'),
                trailing: GlassCompactDatePicker(
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
}

class SearchFieldPage extends StatefulWidget {
  const SearchFieldPage({super.key});

  @override
  State<SearchFieldPage> createState() => _SearchFieldPageState();
}

class _SearchFieldPageState extends State<SearchFieldPage> {
  static const _plants = [
    'Boston fern',
    'Calathea',
    'Fiddle-leaf fig',
    'Jade plant',
    'Monstera',
    'Peace lily',
    'Pothos',
    'Snake plant',
    'String of pearls',
  ];

  final _stage = TextEditingController();
  final _filter = TextEditingController();
  var _enabled = true;

  @override
  void dispose() {
    _stage.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassSearchField',
    summary:
        'A capsule of glass to type a search into, with a button that '
        'clears it.',
    backdrop: Wallpaper.dunes,
    stageHeight: 120,
    stage: GlassSearchField(
      controller: _stage,
      placeholder: const Text('Search plants'),
      enabled: _enabled,
    ),
    knobs: [
      ToggleKnob(
        'Enabled',
        value: _enabled,
        onChanged: (on) => setState(() => _enabled = on),
      ),
    ],
    ideas: [
      Idea(
        'A list that narrows as you type',
        'onChanged gives every keystroke; the list keeps what matches.',
        child: Stage(
          height: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSearchField(
                controller: _filter,
                placeholder: const Text('Filter'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              for (final plant in _plants)
                if (plant.toLowerCase().contains(_filter.text.toLowerCase()))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.tree, size: 18),
                        const SizedBox(width: 10),
                        Text(plant),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    ],
  );
}

class TextFieldPage extends StatefulWidget {
  const TextFieldPage({super.key});

  @override
  State<TextFieldPage> createState() => _TextFieldPageState();
}

class _TextFieldPageState extends State<TextFieldPage> {
  final _email = TextEditingController();
  final _quote = TextEditingController(
    text: 'A fern needs shade, damp soil and patience.',
  );
  var _enabled = true;
  var _error = false;
  var _hidden = true;
  var _labelled = false;
  var _readOnly = false;
  var _centered = false;
  var _limited = false;
  var _looked = 'Select a word and choose Look Up';

  @override
  void dispose() {
    _email.dispose();
    _quote.dispose();
    super.dispose();
  }

  String? get _emailError {
    final email = _email.text;
    if (email.isEmpty || email.contains('@')) return null;
    return 'An email has an @ in it.';
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassTextField',
    summary:
        'A field to type into on a plain rounded fill, with a placeholder '
        'and an error under it.',
    stageHeight: 140,
    stage: GlassTextField(
      placeholder: 'Name',
      enabled: _enabled,
      readOnly: _readOnly,
      textAlign: _centered ? TextAlign.center : TextAlign.start,
      maxLength: _limited ? 12 : null,
      labelText: _labelled ? 'Name' : null,
      helperText: _labelled ? 'As it shows on your profile' : null,
      errorText: _error ? 'Enter your name.' : null,
    ),
    knobs: [
      ToggleKnob(
        'Enabled',
        value: _enabled,
        onChanged: (on) => setState(() => _enabled = on),
      ),
      ToggleKnob(
        'Error',
        value: _error,
        onChanged: (on) => setState(() => _error = on),
      ),
      ToggleKnob(
        'Label and helper',
        value: _labelled,
        onChanged: (on) => setState(() => _labelled = on),
      ),
      ToggleKnob(
        'Read only',
        value: _readOnly,
        onChanged: (on) => setState(() => _readOnly = on),
      ),
      ToggleKnob(
        'Centered',
        value: _centered,
        onChanged: (on) => setState(() => _centered = on),
      ),
      ToggleKnob(
        'At most 12 letters',
        value: _limited,
        onChanged: (on) => setState(() => _limited = on),
      ),
    ],
    ideas: [
      Idea(
        'Sign in',
        'The email says what is wrong under it as you type; the password '
            'shows its text from a plain button at its end.',
        child: Stage(
          height: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassTextField(
                controller: _email,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                errorText: _emailError,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              GlassTextField(
                placeholder: 'Password',
                obscureText: _hidden,
                autofillHints: const [AutofillHints.password],
                suffix: GlassButton.plain(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  semanticLabel: _hidden ? 'Show password' : 'Hide password',
                  child: Icon(
                    _hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Idea(
        'An action of its own in the menu',
        "The glass edit menu over a selection, with the field's own "
            'actions and one more; on a touch screen the handles are '
            "UIKit's lollipops.",
        child: Stage(
          height: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassTextField(
                controller: _quote,
                maxLines: 2,
                contextMenuBuilder: (context, editable) => GlassEditMenu(
                  anchorAbove: editable.contextMenuAnchors.primaryAnchor,
                  anchorBelow:
                      editable.contextMenuAnchors.secondaryAnchor ??
                      editable.contextMenuAnchors.primaryAnchor,
                  buttonItems: [
                    ...editable.contextMenuButtonItems,
                    ContextMenuButtonItem(
                      label: 'Look Up',
                      onPressed: () {
                        final value = editable.textEditingValue;
                        final word = value.selection.textInside(value.text);
                        editable.hideToolbar();
                        setState(
                          () => _looked = word.trim().isEmpty
                              ? 'Nothing selected'
                              : 'Looked up "${word.trim()}"',
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _looked,
                style: TextStyle(
                  color: GlassDynamicColor.resolve(
                    GlassColors.secondaryLabel,
                    context,
                  ),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
      const Idea(
        'A note',
        'Three lines tall, growing to six before it scrolls.',
        child: Stage(
          height: null,
          child: GlassTextField(
            placeholder: 'What happened?',
            minLines: 3,
            maxLines: 6,
          ),
        ),
      ),
    ],
  );
}

enum _BadgeKind { count, text, dot }

class BadgePage extends StatefulWidget {
  const BadgePage({super.key});

  @override
  State<BadgePage> createState() => _BadgePageState();
}

class _BadgePageState extends State<BadgePage> {
  var _kind = _BadgeKind.count;
  var _count = 3.0;
  var _brand = Brand.system;

  Widget _badge(GlassBadgeStyle? style) => switch (_kind) {
    _BadgeKind.count => GlassBadge.count(_count.round(), style: style),
    _BadgeKind.text => GlassBadge.text('New', style: style),
    _BadgeKind.dot => GlassBadge.indicator(style: style),
  };

  @override
  Widget build(BuildContext context) {
    final style = _brand.color == null
        ? null
        : GlassBadgeStyle(backgroundColor: _brand.color);
    return ComponentPage(
      name: 'GlassBadge',
      summary: 'A count, a word or a dot that asks for a look.',
      stageHeight: 120,
      stage: _badge(style),
      knobs: [
        ChoiceKnob<_BadgeKind>(
          'Kind',
          value: _kind,
          options: const {
            _BadgeKind.count: 'Count',
            _BadgeKind.text: 'Text',
            _BadgeKind.dot: 'Dot',
          },
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        AmountKnob(
          'Count',
          value: _count,
          min: 1,
          max: 120,
          onChanged: (count) => setState(() => _count = count),
        ),
        ChoiceKnob<Brand>(
          'Colors',
          value: _brand,
          options: Brand.names,
          onChanged: (brand) => setState(() => _brand = brand),
        ),
      ],
      ideas: [
        Idea(
          'On an icon',
          'Laid over the corner of whatever it counts. A tab of a '
              'GlassTabBar takes one as its badge.',
          child: Stage(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final icon in const [
                  CupertinoIcons.tray_fill,
                  CupertinoIcons.bell_fill,
                  CupertinoIcons.cart_fill,
                ])
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 40),
                      Positioned(left: 24, top: -8, child: _badge(style)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
