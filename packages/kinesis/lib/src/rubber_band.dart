/// Resistance past an edge: how far a value drawn [overshoot] beyond it
/// shows, `x * d * c / (d + c * x)`.
///
/// UIKit's rubber band: monotonic, approaching [dimension] asymptotically,
/// with slope [coefficient] at the edge. 0.55 is the classic iOS
/// coefficient. An overshoot of 0 or less shows nothing.
double rubberBand(
  double overshoot, {
  required double dimension,
  double coefficient = 0.55,
}) {
  if (overshoot <= 0) return 0;
  return overshoot *
      dimension *
      coefficient /
      (dimension + coefficient * overshoot);
}
