// The work registers each shader takes on a Mali-G78, as Arm's offline
// compiler counts them, against test/shader_registers.txt.
//
// A shader that needs more than 32 runs half as many fragments at once on
// that GPU, and an edit to a file several shaders include can take one over
// without any picture changing. The numbers are reviewed like an API: a
// change shows up here as a diff of the file. After reading it:
// flutter test --dart-define=UPDATE_SHADER_REGISTERS=true
//   test/src/shader_registers_test.dart
//
// Needs `malioc` (Arm Performance Studio) on the path, and skips without it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _update = bool.fromEnvironment('UPDATE_SHADER_REGISTERS');
const _reviewed = 'test/shader_registers.txt';
const _shaders = 'lib/assets/shaders';

// The engine's shader compiler lies beside the tester that runs this.
final _engine = File(Platform.resolvedExecutable).parent;
final _impellerc = File('${_engine.path}/impellerc');

bool get _hasMalioc {
  try {
    return Process.runSync('malioc', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void _compile(List<String> arguments) {
  final result = Process.runSync(_impellerc.path, [
    ...arguments,
    '--include=${_engine.path}/shader_lib',
    '--include=$_shaders',
    '--include=$_shaders/gpu',
  ]);
  if (result.exitCode != 0) {
    fail('impellerc ${arguments.join(' ')}:\n${result.stderr}');
  }
}

// The SPIR-V a runtime-effect library holds for Vulkan: the module begins at
// its magic number, and its byte length is the word before it. Some
// versions of the compiler write the module alone.
Uint8List _spirvOf(Uint8List library) {
  const magic = [0x03, 0x02, 0x23, 0x07];
  for (var i = 0; i + 4 <= library.length; i++) {
    if (library[i] == magic[0] &&
        library[i + 1] == magic[1] &&
        library[i + 2] == magic[2] &&
        library[i + 3] == magic[3]) {
      if (i < 4) return library;
      final length = ByteData.sublistView(
        library,
        i - 4,
        i,
      ).getUint32(0, Endian.little);
      return Uint8List.sublistView(library, i, i + length);
    }
  }
  fail('No SPIR-V in the library.');
}

int _registersOf(String spirv) {
  final result = Process.runSync('malioc', [
    '--core',
    'Mali-G78',
    '--fragment',
    '--vulkan',
    '--format',
    'json',
    spirv,
  ]);
  final report = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final shader = (report['shaders']! as List<Object?>).first! as Map;
  final variant = (shader['variants'] as List<Object?>).first! as Map;
  for (final property in variant['properties'] as List<Object?>) {
    if (property case {
      'name': 'work_registers_used',
      'value': final int value,
    }) {
      return value;
    }
  }
  fail('malioc reported no work registers for $spirv:\n${result.stdout}');
}

void main() {
  test(
    'the shaders take the work registers that were reviewed',
    () {
      final out = Directory.systemTemp.createTempSync('shader_registers');
      addTearDown(() => out.deleteSync(recursive: true));
      final lines = <String>[];

      // The runtime effects: what a glass filter or a frost runs.
      final effects = [
        for (final file in Directory(_shaders).listSync())
          if (file.path.endsWith('.frag')) file.uri.pathSegments.last,
      ]..sort();
      for (final name in effects) {
        final library = '${out.path}/$name.iplr';
        _compile([
          '--runtime-stage-vulkan',
          '--input=$_shaders/$name',
          '--sl=$library',
          '--spirv=${out.path}/$name.spv',
        ]);
        final spirv = File('${out.path}/$name.vulkan.spv')
          ..writeAsBytesSync(_spirvOf(File(library).readAsBytesSync()));
        lines.add('$name ${_registersOf(spirv.path)}');
      }

      // The passes that draw a geometry atlas.
      final passes = [
        for (final file in Directory('$_shaders/gpu').listSync())
          if (file.path.endsWith('_fragment.glsl')) file.uri.pathSegments.last,
      ]..sort();
      for (final name in passes) {
        final spirv = '${out.path}/$name.spv';
        _compile([
          '--vulkan',
          '--input-type=frag',
          '--input=$_shaders/gpu/$name',
          '--sl=${out.path}/$name.sl',
          '--spirv=$spirv',
        ]);
        lines.add('gpu/$name ${_registersOf(spirv)}');
      }

      final measured = '${lines.join('\n')}\n';
      final reviewed = File(_reviewed);
      if (_update) {
        reviewed.writeAsStringSync(measured);
        return;
      }
      expect(
        measured,
        reviewed.readAsStringSync(),
        reason:
            'A shader takes other work registers on the Mali-G78 than were '
            'reviewed. Read the diff, then run with '
            '--dart-define=UPDATE_SHADER_REGISTERS=true.',
      );
    },
    skip: !_impellerc.existsSync()
        ? 'no impellerc beside the tester'
        : !_hasMalioc
        ? 'malioc is not on the path'
        : false,
  );
}
