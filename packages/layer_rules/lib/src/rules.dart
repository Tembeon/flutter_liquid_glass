/// The key of [LayerRules.forbidden] that applies to every library.
const everyLibrary = '*';

/// How a file reaches another file of its own library.
enum SameLibraryImports {
  /// Through `package:<package>/src/<library>/...`.
  package,

  /// Through a relative path.
  relative,
}

/// A pattern that must not occur in `lib/`.
final class Ban {
  /// Bans [pattern], a regular expression, outside the files [allowedIn].
  ///
  /// With [code] true the pattern is matched against the source with its
  /// comments and string literals blanked out; with [code] false against
  /// the raw text, so it can ban a comment.
  const Ban(
    this.name,
    this.pattern, {
    this.code = true,
    this.allowedIn = const {},
  });

  /// The name the debt file and failures show.
  final String name;

  /// The regular expression, as its source text.
  final String pattern;

  /// Whether comments and string literals are blanked before matching.
  final bool code;

  /// Paths relative to the package root, such as `lib/src/a/b.dart`, where
  /// the pattern may occur. A path that ends in `/`, such as `lib/src/a/`,
  /// allows every file under it.
  final Set<String> allowedIn;
}

/// The library layout of one package, as plain data.
///
/// Each library is a folder `lib/src/<name>/` opened by one file
/// `lib/<name>.dart`. [libraries] names each library with the libraries it
/// may import; the table must have no cycle.
final class LayerRules {
  /// The rules for the package [package].
  const LayerRules({
    required this.package,
    required this.libraries,
    this.umbrella,
    this.umbrellaReexports = const {},
    this.unchecked = const {},
    this.sameLibraryImports = SameLibraryImports.package,
    this.packages = const {},
    this.forbidden = const {},
    this.bans = const [],
  });

  /// The package name, as in `package:<package>/`.
  final String package;

  /// Each library, by folder name, with the libraries it may import.
  final Map<String, Set<String>> libraries;

  /// The library file, without `.dart`, that exports every library and
  /// nothing else, or null when the package has none.
  final String? umbrella;

  /// Libraries of other packages, as `package:` URIs, that the umbrella
  /// exports besides this package's libraries, such as the umbrella of a
  /// package this one builds on.
  final Set<String> umbrellaReexports;

  /// Library files, without `.dart`, that rule 1 leaves alone, such as a
  /// `testing` library that picks names from several libraries. A library
  /// file of `src` may not import them.
  final Set<String> unchecked;

  /// How a file reaches another file of its own library.
  final SameLibraryImports sameLibraryImports;

  /// The packages besides this one that `lib/` may import. `dart:` libraries
  /// are always allowed unless [forbidden] names them.
  final Set<String> packages;

  /// Import URI prefixes each library may not import, by library name or
  /// [everyLibrary].
  final Map<String, List<String>> forbidden;

  /// Patterns that must not occur in `lib/`.
  final List<Ban> bans;
}
