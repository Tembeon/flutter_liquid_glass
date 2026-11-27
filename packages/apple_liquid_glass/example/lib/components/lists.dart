import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

enum _Accessory { none, disclosure, checkmark, detail }

enum _Edit { off, delete, insert, select }

class ListPage extends StatefulWidget {
  const ListPage({super.key});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  static const _more = ['Mist the fern', 'Turn the fig', 'Feed the lily'];

  var _accessory = _Accessory.disclosure;
  var _leading = true;
  var _subtitle = true;
  var _detail = false;
  var _headers = true;
  var _separators = true;
  var _layout = GlassListLayout.insetGrouped;
  var _edgeToEdge = false;
  var _roomy = false;
  final _tasks = ['Water the monstera', 'Repot the jade', 'Wipe the leaves'];
  var _next = 0;
  var _size = 1;
  var _edit = _Edit.off;
  var _picked = <Object>{};

  void _change(VoidCallback change) =>
      withSpring(Spring.smooth, () => setState(change));

  @override
  Widget build(BuildContext context) {
    const add = #add;
    final ids = <Object>[..._tasks, add];
    return ComponentPage(
      name: 'GlassListSection',
      summary:
          'Grouped rows, as a settings page has them: a GlassListSection '
          'of GlassListRows that highlight under a press.',
      knobs: [
        ChoiceKnob<GlassListLayout>(
          'Layout',
          value: _layout,
          options: const {
            GlassListLayout.insetGrouped: 'Inset',
            GlassListLayout.grouped: 'Grouped',
            GlassListLayout.plain: 'Plain',
          },
          onChanged: (layout) => setState(() => _layout = layout),
        ),
        ChoiceKnob<_Accessory>(
          'Accessory',
          value: _accessory,
          options: const {
            _Accessory.none: 'None',
            _Accessory.disclosure: 'Chevron',
            _Accessory.checkmark: 'Check',
            _Accessory.detail: 'Info',
          },
          onChanged: (accessory) => setState(() => _accessory = accessory),
        ),
        ChoiceKnob<_Edit>(
          'Editing',
          value: _edit,
          options: const {
            _Edit.off: 'Off',
            _Edit.delete: 'Delete',
            _Edit.insert: 'Insert',
            _Edit.select: 'Select',
          },
          onChanged: (edit) => setState(() => _edit = edit),
        ),
        ToggleKnob(
          'Leading icon',
          value: _leading,
          onChanged: (on) => setState(() => _leading = on),
        ),
        ToggleKnob(
          'Subtitle',
          value: _subtitle,
          onChanged: (on) => setState(() => _subtitle = on),
        ),
        ToggleKnob(
          'Detail',
          value: _detail,
          onChanged: (on) => setState(() => _detail = on),
        ),
        ToggleKnob(
          'Header and footer',
          value: _headers,
          onChanged: (on) => setState(() => _headers = on),
        ),
        ToggleKnob(
          'Separators',
          value: _separators,
          onChanged: (on) => setState(() => _separators = on),
        ),
        ToggleKnob(
          'Separators edge to edge',
          value: _edgeToEdge,
          onChanged: (on) => setState(() => _edgeToEdge = on),
        ),
        ToggleKnob(
          'Roomy rows',
          value: _roomy,
          onChanged: (on) => setState(() => _roomy = on),
        ),
      ],
      ideas: [
        Idea(
          'The rows the knobs make',
          'Every row here is one GlassListRow with the parts turned on '
              'above. In editing a GlassListEditing above the section '
              'gives each row its minus, plus or selection ring.',
          flush: true,
          child: _editing(
            GlassListSection(
              layout: _layout,
              showsSeparators: _separators,
              style: GlassListStyle(
                separatorIndent: _edgeToEdge ? 0 : null,
                separatorEndIndent: _edgeToEdge ? 0 : null,
                contentPadding: _roomy
                    ? const EdgeInsetsDirectional.fromSTEB(24, 22, 24, 22)
                    : null,
              ),
              header: _headers ? const Text('Living room') : null,
              footer: _headers
                  ? const Text('Three plants by the east window.')
                  : null,
              children: [
                for (final (name, kind, icon) in const [
                  ('Monstera', 'Every 7 days', CupertinoIcons.tree),
                  ('Jade plant', 'Every 14 days', CupertinoIcons.circle_fill),
                  ('Peace lily', 'Every 5 days', CupertinoIcons.drop_fill),
                ])
                  GlassListRow(
                    leading: _leading
                        ? SettingsIcon(
                            icon: icon,
                            color: GlassColors.systemGreen,
                          )
                        : null,
                    title: Text(name),
                    subtitle: _subtitle ? Text(kind) : null,
                    detail: _detail ? const Text('Today') : null,
                    accessory: switch (_accessory) {
                      _Accessory.none => null,
                      _Accessory.disclosure =>
                        GlassListAccessory.disclosureIndicator,
                      _Accessory.checkmark => GlassListAccessory.checkmark,
                      _Accessory.detail =>
                        GlassListAccessory.detailDisclosureButton,
                    },
                    onAccessoryPressed: () {},
                    onPressed: () {},
                    onDelete: _edit == _Edit.delete ? () {} : null,
                    onInsert: _edit == _Edit.insert ? () {} : null,
                    value: name,
                  ),
              ],
            ),
          ),
        ),
        Idea(
          'Pick one',
          'A checkmark on the row last pressed.',
          flush: true,
          child: GlassListSection(
            children: [
              for (final (index, name) in const [
                'Small pot',
                'Medium pot',
                'Large pot',
              ].indexed)
                GlassListRow(
                  title: Text(name),
                  accessory: _size == index
                      ? GlassListAccessory.checkmark
                      : null,
                  onPressed: () => setState(() => _size = index),
                ),
            ],
          ),
        ),
        const Idea(
          'Rows that come and go',
          'A GlassSliverListSection with ids moves its rows on a spring '
              'as the list changes. GlassSwipeActions puts actions behind a '
              'row; a full swipe takes the first. Editing set to Delete '
              'deletes a task from its minus.',
          flush: true,
          child: SizedBox.shrink(),
        ),
      ],
      slivers: [
        _editing(
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
                  title: const Text('Add a task'),
                  onPressed: () => _change(() {
                    final round = _next ~/ _more.length;
                    final name = _more[_next++ % _more.length];
                    _tasks.add(round == 0 ? name : '$name ${round + 1}');
                  }),
                );
              }
              final task = id as String;
              if (_edit != _Edit.off) {
                return GlassListRow(
                  title: Text(task),
                  value: task,
                  onDelete: () => _change(() => _tasks.remove(task)),
                );
              }
              return GlassSwipeActions(
                trailing: [
                  GlassSwipeAction(
                    title: 'Done',
                    destructive: true,
                    onPressed: () => _change(() => _tasks.remove(task)),
                  ),
                  GlassSwipeAction(
                    title: 'First',
                    backgroundColor: GlassColors.systemOrange,
                    onPressed: () => _change(() {
                      _tasks
                        ..remove(task)
                        ..insert(0, task);
                    }),
                  ),
                ],
                child: GlassListRow(title: Text(task)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _editing(Widget list) => GlassListEditing(
    editing: _edit != _Edit.off,
    selection: _picked,
    onSelectionChanged: _edit == _Edit.select
        ? (picked) => setState(() => _picked = picked)
        : null,
    child: list,
  );
}
