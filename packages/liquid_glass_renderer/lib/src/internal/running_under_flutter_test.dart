// `dart:io` does not exist on the web; callers check `kIsWeb` first, so the
// web value is never read.
export 'running_under_flutter_test_io.dart'
    if (dart.library.js_interop) 'running_under_flutter_test_web.dart';
