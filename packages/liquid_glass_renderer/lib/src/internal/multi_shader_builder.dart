// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A callback used by [MultiShaderBuilder].
typedef MultiShaderBuilderCallback = Widget Function(
  BuildContext,
  List<ui.FragmentShader>,
  Widget?,
);

/// Loads and caches [ui.FragmentProgram]s by asset key and builds with one
/// shader per key, in [assetKeys] order, once all have loaded; until then it
/// shows [child], or nothing. Programs precached with [precacheShaders] are
/// there on the first build.
class MultiShaderBuilder extends StatefulWidget {
  /// Create a new [MultiShaderBuilder].
  const MultiShaderBuilder(
    this.builder, {
    required this.assetKeys,
    super.key,
    this.child,
  });

  /// The asset keys used to lookup shaders.
  final List<String> assetKeys;

  /// The child widget to pass through to the [builder], optional.
  final Widget? child;

  /// The builder that provides access to [ui.FragmentShader]s.
  final MultiShaderBuilderCallback builder;

  @override
  State<StatefulWidget> createState() {
    return _MultiShaderBuilderState();
  }

  /// Precache a [ui.FragmentProgram] based on its [assetKey].
  ///
  /// Once the returned future completes, a new builder for [assetKey] has its
  /// shader on its first build, unless loading failed (reported through
  /// [FlutterError]).
  static Future<void> precacheShader(String assetKey) {
    if (_MultiShaderBuilderState._shaderCache.containsKey(assetKey)) {
      return Future<void>.value();
    }
    return ui.FragmentProgram.fromAsset(assetKey).then(
      (ui.FragmentProgram program) {
        _MultiShaderBuilderState._shaderCache[assetKey] = program;
      },
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      },
    );
  }

  /// Whether the program of [assetKey] has loaded.
  static bool isCached(String assetKey) =>
      _MultiShaderBuilderState._shaderCache.containsKey(assetKey);

  /// The program of [assetKey], once it has loaded.
  static ui.FragmentProgram? cached(String assetKey) =>
      _MultiShaderBuilderState._shaderCache[assetKey];

  /// Precache multiple [ui.FragmentProgram]s based on their [assetKeys].
  ///
  /// Once the returned future completes, a new builder for [assetKeys] has
  /// its shaders on its first build, unless loading failed.
  static Future<void> precacheShaders(List<String> assetKeys) {
    return Future.wait(
      assetKeys.map(precacheShader),
    );
  }
}

class _MultiShaderBuilderState extends State<MultiShaderBuilder> {
  final Map<String, ui.FragmentShader> _shaders = {};

  static final Map<String, ui.FragmentProgram> _shaderCache =
      <String, ui.FragmentProgram>{};

  @override
  void initState() {
    super.initState();
    _loadShaders(widget.assetKeys);
  }

  @override
  void didUpdateWidget(covariant MultiShaderBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.assetKeys, widget.assetKeys)) {
      _loadShaders(widget.assetKeys);
    }
  }

  void _loadShaders(List<String> assetKeys) {
    _disposeShaders();
    for (final assetKey in assetKeys) {
      if (_shaderCache[assetKey] case final program?) {
        _shaders[assetKey] = program.fragmentShader();
        continue;
      }
      MultiShaderBuilder.precacheShader(assetKey).then((_) {
        final program = _shaderCache[assetKey];
        if (!mounted || program == null) return;
        setState(() => _shaders[assetKey] = program.fragmentShader());
      });
    }
  }

  void _disposeShaders() {
    for (final shader in _shaders.values) {
      shader.dispose();
    }
    _shaders.clear();
  }

  @override
  void dispose() {
    _disposeShaders();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shaders.length != widget.assetKeys.length) {
      return widget.child ?? const SizedBox.shrink();
    }
    final shaders = widget.assetKeys.map((key) => _shaders[key]!).toList();
    return widget.builder(context, shaders, widget.child);
  }
}
