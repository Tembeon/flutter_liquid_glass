// `dart:io` does not exist on the web; callers ask whether the engine draws
// shader filters first, which the web does not, so the web value is never
// read.
export 'package:liquid_glass_renderer/src/rendering/running_under_flutter_test_io.dart'
    if (dart.library.js_interop) 'package:liquid_glass_renderer/src/rendering/running_under_flutter_test_web.dart';
