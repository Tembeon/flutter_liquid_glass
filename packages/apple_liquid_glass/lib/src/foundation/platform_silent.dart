import 'package:apple_liquid_glass/src/foundation/platform.dart';

/// The reader where `dart:ffi` is missing: the web.
GlassPlatformReader createGlassPlatformReader() =>
    const GlassSilentPlatformReader();
