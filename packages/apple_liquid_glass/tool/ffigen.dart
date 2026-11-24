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
  Logger.root
    ..level = Level.SEVERE
    ..onRecord.listen((record) => stderr.writeln(record.message));
  await _generate(
    root,
    entryPoint: Uri.file(
      '$iosSdkPath/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h',
    ),
    bindings: 'lib/src/foundation/uikit.g.dart',
    objectiveCFile: 'src/ios/uikit.g.m',
    visitor: Visitor(
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
  );
  await _generate(
    root,
    entryPoint: root.resolve('src/glass_platform.h'),
    bindings: 'lib/src/foundation/platform.g.dart',
    objectiveCFile: 'src/platform.g.m',
    visitor: Visitor(
      func: (node) {
        if (node.originalName.startsWith('glass_')) node.isIncluded = true;
      },
    ),
  );
}

Future<void> _generate(
  Uri root, {
  required Uri entryPoint,
  required String bindings,
  required String objectiveCFile,
  required Visitor visitor,
}) async {
  await FfiGenerator(
    input: Input(
      entryPoints: [entryPoint],
      compilerOptions: [
        '-isysroot',
        iosSdkPath,
        '-target',
        'arm64-apple-ios13.0',
      ],
    ),
    objectiveC: const ObjectiveC(),
    visitors: [visitor],
    output: Output(
      dart: DartOutput(path: root.resolve(bindings)),
      objectiveCFile: root.resolve(objectiveCFile),
      commentType: const CommentType.none(),
      style: const NativeExternalBindings(
        assetId: 'package:apple_liquid_glass/apple_liquid_glass.dylib',
      ),
    ),
  ).generate(logger: Logger.root);
  // analysis_options.yaml excludes the bindings, so ffigen's line that turns
  // the lints off goes.
  final file = File.fromUri(root.resolve(bindings));
  final lines = file.readAsLinesSync().where(
    (line) => !line.startsWith('// ignore_for_file:'),
  );
  file.writeAsStringSync('${lines.join('\n')}\n');
}
