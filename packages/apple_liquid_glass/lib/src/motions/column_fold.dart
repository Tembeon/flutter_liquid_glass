import 'package:meta/meta.dart';

/// A form a column takes as a hand drags its edge: a width of its own, such
/// as a hidden column's 0 or a rail of icons, or any width between [min]
/// and [max].
@immutable
final class ColumnForm {
  /// Creates a form [width] wide that a drag moves between [min] and [max];
  /// without them the form keeps its width.
  const ColumnForm({required this.width, double? min, double? max})
    : min = min ?? width,
      max = max ?? width;

  /// The width the column takes when a hand folds it into this form.
  final double width;

  /// The narrowest a drag makes the form.
  final double min;

  /// The widest a drag makes the form.
  final double max;

  /// The form's [width] within its limits.
  double get entry => width.clamp(min, max);

  @override
  bool operator ==(Object other) =>
      other is ColumnForm &&
      other.width == width &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(width, min, max);

  @override
  String toString() =>
      min == max ? 'ColumnForm($width)' : 'ColumnForm($width, $min - $max)';
}

/// A hand dragging the edge of a column through its [forms], narrowest
/// first, as Sonatide's rail folds into its icons: the column follows the
/// hand within its form, sticks at the form's limit while the hand goes on,
/// and [distance] past it folds into the next form, from where the same drag
/// goes on.
///
/// A fold puts the column at the new form's [ColumnForm.width], so a column
/// that folds and unfolds in one drag comes back at the width it had, not at
/// the limit it stuck at.
final class ColumnFold {
  /// Starts a drag of a column in the form at [form], [width] wide, the hand
  /// at [position] along the drag's axis.
  ColumnFold(
    this.forms, {
    required int form,
    required double width,
    double position = 0,
    this.distance = defaultDistance,
  }) : assert(forms.isNotEmpty, 'a column has a form'),
       assert(form >= 0 && form < forms.length, 'one of the forms'),
       _form = form,
       _width = width,
       _anchor = position,
       _anchorWidth = width;

  /// How far past a form's limit a hand goes before the column folds:
  /// Sonatide's rail's, the package's own.
  static const double defaultDistance = 50;

  /// The column's forms, narrowest first.
  final List<ColumnForm> forms;

  /// How far past a form's limit the hand folds the column.
  final double distance;

  int _form;
  double _width;
  double _anchor;
  double _anchorWidth;

  /// The form the column is in.
  int get form => _form;

  /// The column's width.
  double get width => _width;

  /// Moves the hand to [position]; true when the column folded into
  /// another form.
  bool update(double position) {
    final shape = forms[_form];
    final asked = _anchorWidth + position - _anchor;
    if (asked < shape.min) {
      if (_form > 0 && shape.min - asked >= distance) {
        _fold(_form - 1, position);
        return true;
      }
      _width = shape.min;
    } else if (asked > shape.max) {
      if (_form < forms.length - 1 && asked - shape.max >= distance) {
        _fold(_form + 1, position);
        return true;
      }
      _width = shape.max;
    } else {
      _width = asked;
    }
    return false;
  }

  void _fold(int form, double position) {
    _form = form;
    _width = forms[form].entry;
    _anchor = position;
    _anchorWidth = _width;
  }

  /// Where a step of [by] points from the keyboard or a screen reader takes
  /// a column in the form at [form], [width] wide: within the form while it
  /// has room, into the narrower form from its minimum, into the wider one
  /// from its maximum. Returns the form and the width.
  static (int, double) step(
    List<ColumnForm> forms, {
    required int form,
    required double width,
    required double by,
  }) {
    final shape = forms[form];
    if (by < 0 && width <= shape.min && form > 0) {
      return (form - 1, forms[form - 1].entry);
    }
    if (by > 0 && width >= shape.max && form < forms.length - 1) {
      return (form + 1, forms[form + 1].entry);
    }
    return (form, (width + by).clamp(shape.min, shape.max));
  }
}
