import 'dart:io';

import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';

const _members = <String, Set<String>>{
  'UIViewController': {'view'},
  'UIView': {
    'bounds',
    'safeAreaInsets',
    'traitCollection',
    'effectiveUserInterfaceLayoutDirection',
    'reservedRegionsOfKind:options:',
  },
  'UITraitCollection': {
    'userInterfaceIdiom',
    'horizontalSizeClass',
    'verticalSizeClass',
    'verticalBarEdge',
  },
  'UIHingeInteraction': {'alloc', 'initWithUpdateHandler:'},
  'UIHingeInteractionUpdate': {'hinge'},
  'UIHinge': {'status'},
  'UIViewReservedRegion': {'frame', 'isActive'},
  'UIViewReservedRegionKind': {'occlusionRegionKind', 'divisionRegionKind'},
};

String? _classOf(Object parent) => switch (parent) {
  ObjCInterface(:final name) => name,
  ObjCCategory(:final interface) => interface.name,
  _ => null,
};

Future<void> main() async {
  final root = Platform.script.resolve('../');
  final headers =
      '$iosSdkPath/System/Library/Frameworks/UIKit.framework/Headers';
  Logger.root
    ..level = Level.SEVERE
    ..onRecord.listen((record) => stderr.writeln(record.message));
  await FfiGenerator(
    input: Input(
      entryPoints: [Uri.file('$headers/UIKit.h')],
      compilerOptions: [
        '-isysroot',
        iosSdkPath,
        '-target',
        'arm64-apple-ios13.0',
      ],
    ),
    objectiveC: const ObjectiveC(),
    visitors: [
      Visitor(
        objCInterface: (node) {
          node.includeCategories = false;
          if (_members.containsKey(node.name)) node.isIncluded = true;
        },
        objCCategory: (node) {
          final members = _members[node.interface.name];
          node.isIncluded =
              members != null &&
              node.methods.any((method) => members.contains(method.selector));
        },
        objCMethod: (node) {
          final members = _members[_classOf(node.parent)];
          if (members == null || !members.contains(node.selector)) {
            node.isIncluded = false;
          }
        },
        enumClass: (node) {
          node.style = EnumStyle.intConstants;
          node.silenceWarning = true;
        },
      ),
    ],
    output: Output(
      dart: DartOutput(path: root.resolve(_bindings)),
      objectiveCFile: root.resolve('src/ios/uikit.g.m'),
      commentType: const CommentType.none(),
      style: const NativeExternalBindings(
        assetId: 'package:apple_liquid_glass/apple_liquid_glass.dylib',
      ),
    ),
  ).generate(logger: Logger.root);
  final bindings = File.fromUri(root.resolve(_bindings));
  final lines = bindings.readAsLinesSync().where(
    (line) => !line.startsWith('// ignore_for_file:'),
  );
  bindings.writeAsStringSync('${lines.join('\n')}\n');
}

// analysis_options.yaml excludes the bindings, so ffigen's line that turns
// the lints off goes.
const _bindings = 'lib/src/foundation/uikit.g.dart';
