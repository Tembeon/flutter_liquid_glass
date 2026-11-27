import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';

/// Where a read's backdrop came from in a [GlassFrameReport].
enum GlassReadSource {
  /// Layers under the glass, added again to the scene this frame.
  scene,

  /// An image drawn this frame.
  image,

  /// An image drawn in an earlier frame, which costs one texture read.
  heldImage,

  /// The screen behind the glass, read as a backdrop filter does.
  backdrop,
}

/// One backdrop read of a frame, and the glass that shares it.
@immutable
final class GlassReadReport {
  const GlassReadReport._({
    required this.source,
    required this.nesting,
    required this.glassCount,
    required this.hasBand,
    required this.footprint,
    required this.passes,
    required this.changed,
  });

  /// Where its backdrop came from.
  final GlassReadSource source;

  /// How deep it nests reads: zero over pictures alone, else one more than
  /// the deepest read it nests.
  final int nesting;

  /// How many glass surfaces draw from it.
  final int glassCount;

  /// Whether a scroll edge draws from it too.
  final bool hasBand;

  /// What it holds of what lies under the glass, in logical pixels.
  final Rect footprint;

  /// The passes of the frame it takes, each an offscreen target.
  final int passes;

  /// Whether what it holds differs from the last frame.
  final bool changed;

  @override
  String toString() {
    final who = hasBand ? 'band + $glassCount glass' : '$glassCount glass';
    final size = '${footprint.width.round()}x${footprint.height.round()}';
    return '${source.name}  nesting $nesting  $who  $size  passes $passes'
        '${changed ? '  changed' : ''}';
  }
}

/// What the plan decided for one frame and what the frame cost.
///
/// Nothing here can be tuned: no widget has a field for a layer, a copy or a
/// group. The lines to act on are the ones naming a layer that makes glass
/// read the backdrop, such as a layer type nobody registered with
/// `LiquidGlassUnderlay.registerLayer`.
///
/// Reports exist in debug and profile builds while someone asks for them
/// ([GlassFrameReports.addListener], [debugPrintGlassFrameReports],
/// `LiquidGlassReportOverlay`). The counts of work done ([filtersBuilt],
/// [picturesRecorded], [imagesDrawn], [layersReplayed], [repaintsAsked],
/// [lateRepaints]) are the frame's across every view it draws: with two
/// views, each view's report carries both views' work.
@immutable
final class GlassFrameReport {
  const GlassFrameReport._({
    required this.frame,
    required this.planned,
    required this.reads,
    required this.passBudget,
    required this.passes,
    required this.walkDuration,
    required this.compileDuration,
    required this.emitDuration,
    required this.filtersBuilt,
    required this.picturesRecorded,
    required this.imagesDrawn,
    required this.layersReplayed,
    required this.repaintsAsked,
    required this.lateRepaints,
    required this.notes,
  });

  /// The composer's frame count for its view.
  final int frame;

  /// Whether the frame planned; a frame nothing changed in stands on the last
  /// plan and takes only the [walkDuration].
  final bool planned;

  /// The frame's reads in paint order.
  final List<GlassReadReport> reads;

  /// The passes a frame may issue before reads move to images.
  final int passBudget;

  /// The passes the frame takes, each an offscreen target.
  final int passes;

  /// Time spent comparing the layer tree with the last frame's.
  final Duration walkDuration;

  /// Time spent deciding the plan.
  final Duration compileDuration;

  /// Time spent drawing the plan into layers and images.
  final Duration emitDuration;

  /// Image filters made in the frame.
  final int filtersBuilt;

  /// Pictures recorded for glass in the frame.
  final int picturesRecorded;

  /// Images drawn for reads in the frame.
  final int imagesDrawn;

  /// Layers reads added again to the scene in the frame.
  final int layersReplayed;

  /// Repaints the composer asked for in the frame.
  final int repaintsAsked;

  /// Those of [repaintsAsked] that land in the next frame.
  final int lateRepaints;

  /// Why glass stays apart or reads the backdrop, a line of text for each
  /// decision, for a reader: the wording follows the plan and is no API.
  final List<String> notes;

  /// How many reads take the screen behind the glass.
  int get backdropReads =>
      reads.where((read) => read.source == GlassReadSource.backdrop).length;

  /// How many reads draw from an image.
  int get imageReads => reads
      .where(
        (read) =>
            read.source == GlassReadSource.image ||
            read.source == GlassReadSource.heldImage,
      )
      .length;

  @override
  String toString() {
    final head =
        'frame $frame${planned ? '' : ' (as planned before)'}  '
        'reads ${reads.length}  passes $passes/'
        '$passBudget  images $imageReads  backdrop $backdropReads  '
        'walk ${walkDuration.inMicroseconds}us  '
        'compile ${compileDuration.inMicroseconds}us  '
        'emit ${emitDuration.inMicroseconds}us';
    final made =
        'made: filters $filtersBuilt  pictures $picturesRecorded  '
        'images $imagesDrawn  replayed $layersReplayed  '
        'repaints $repaintsAsked (late $lateRepaints)';
    final lines = <String>[
      head,
      made,
      for (var i = 0; i < reads.length; i++) 'R$i ${reads[i]}',
      if (notes.isNotEmpty) 'why apart:',
      for (final note in notes) '  $note',
    ];
    return lines.join('\n');
  }
}

/// Signature of a callback that takes a frame's [GlassFrameReport].
typedef GlassFrameReportCallback = void Function(GlassFrameReport report);

/// The reports of the frames that draw glass.
abstract final class GlassFrameReports {
  static final _listeners = <GlassFrameReportCallback>[];

  /// Calls [listener] after every frame with glass, in debug and profile
  /// builds. Listening costs the frame the report. The frame's composer
  /// writes the reports, so glass planned without it reports nothing.
  static void addListener(GlassFrameReportCallback listener) {
    if (kReleaseMode) return;
    if (!glassFrameReportsWanted) GlassWork.clear();
    _listeners.add(listener);
  }

  /// Stops calling [listener].
  static void removeListener(GlassFrameReportCallback listener) {
    _listeners.remove(listener);
  }
}

/// Whether every frame with glass prints its [GlassFrameReport], in debug
/// and profile builds.
bool get debugPrintGlassFrameReports => _printReports;
bool _printReports = false;
set debugPrintGlassFrameReports(bool value) {
  if (value && !glassFrameReportsWanted) GlassWork.clear();
  _printReports = value;
}

/// Whether a frame should report.
@internal
bool get glassFrameReportsWanted =>
    !kReleaseMode && (_printReports || GlassFrameReports._listeners.isNotEmpty);

final _pendingReports = <GlassFrameReport Function()>[];

/// Hands the report of frame [frame], which drew [plan], to the listeners
/// once the frame is over, when [GlassWork] holds what its scene did as
/// well. The frame [planned] or stood on the last plan, took [walk] to
/// compare the layer tree, had its plan [compiled] that long after its start
/// and was [done] at the end, and may issue [passBudget] passes.
@internal
void reportGlassFrame({
  required int frame,
  required GlassPlan plan,
  required bool planned,
  required int passBudget,
  required Duration walk,
  required Duration compiled,
  required Duration done,
}) {
  final reads = [
    for (final read in plan.reads) _readReportOf(read),
  ];
  _pendingReports.add(
    () => GlassFrameReport._(
      frame: frame,
      planned: planned,
      reads: reads,
      passBudget: passBudget,
      passes: plan.issuedPasses,
      walkDuration: walk,
      compileDuration: compiled - walk,
      emitDuration: done - compiled,
      filtersBuilt: GlassWork.filters,
      picturesRecorded: GlassWork.pictures,
      imagesDrawn: GlassWork.images,
      layersReplayed: GlassWork.replayed,
      repaintsAsked: GlassWork.marks,
      lateRepaints: GlassWork.lateMarks,
      notes: plan.notes,
    ),
  );
  if (_pendingReports.length > 1) return;
  // After the frame: a report counts the scene, which is built after paint.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    final reports = [for (final build in _pendingReports) build()];
    _pendingReports.clear();
    GlassWork.clear();
    for (final report in reports) {
      if (_printReports) debugPrint('$report');
      for (final listener in [...GlassFrameReports._listeners]) {
        listener(report);
      }
    }
  });
}

GlassReadReport _readReportOf(GlassRead read) => GlassReadReport._(
  source: switch (read.source) {
    SceneRead() => GlassReadSource.scene,
    ImageRead(:final held) =>
      held ? GlassReadSource.heldImage : GlassReadSource.image,
    BackdropRead() => GlassReadSource.backdrop,
  },
  nesting: read.nesting,
  glassCount: read.glassMembers.length,
  hasBand: read.lead.isBand,
  footprint: read.footprint,
  passes: read.passes,
  changed: read.changed,
);
