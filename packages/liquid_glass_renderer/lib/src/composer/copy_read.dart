part of 'backdrop_underlay.dart';

/// The pixel grid a copy is drawn on: one, two or four device pixels of
/// the screen along each side of each of its pixels, on a grid anchored at
/// the screen's origin.
///
/// A copy's grid is the one it is drawn on, which a band holding glass that
/// a filter draws takes at the screen's pixels whatever was asked: that
/// glass takes its fragments for the screen's pixels. Only the copies make
/// grids, so a reader meets no other ratio than the one drawn.
@internal
@immutable
final class CopyGrid {
  const CopyGrid._(this._devicePixelRatio, this._share)
    : assert(
        _share == 1 || _share == 2 || _share == 4,
        'A copy holds one, two or four device pixels along each side.',
      );

  final double _devicePixelRatio;

  // How many device pixels along each side one pixel of the copy holds.
  final int _share;

  // The copy's pixels per logical pixel.
  double get _pixels => _devicePixelRatio / _share;

  // The same grid at the screen's pixels.
  CopyGrid get _screen => _share == 1 ? this : CopyGrid._(_devicePixelRatio, 1);

  // [rect] (logical pixels) grown to whole pixels of the copy.
  Rect _snapOut(Rect rect) => BackdropUnderlay._snapOut(rect, _pixels);

  @override
  bool operator ==(Object other) =>
      other is CopyGrid &&
      other._devicePixelRatio == _devicePixelRatio &&
      other._share == _share;

  @override
  int get hashCode => Object.hash(_devicePixelRatio, _share);
}
