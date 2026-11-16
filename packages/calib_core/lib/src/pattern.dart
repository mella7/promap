import 'gray_code.dart';
import 'gray_image.dart';

enum PatternKind { white, black, stripes }

/// [columns] stripes encode the projector x coordinate, [rows] encode y.
enum StripeAxis { columns, rows }

/// One image to project during a scan.
class PatternSpec {
  final PatternKind kind;
  final StripeAxis? axis;

  /// Gray-code bit this pattern shows. 0 is the finest stripe.
  final int bit;

  /// True for the black/white swapped twin of a stripe pattern.
  final bool inverted;

  const PatternSpec.white()
      : kind = PatternKind.white,
        axis = null,
        bit = 0,
        inverted = false;

  const PatternSpec.black()
      : kind = PatternKind.black,
        axis = null,
        bit = 0,
        inverted = false;

  const PatternSpec.stripes(StripeAxis this.axis, this.bit,
      {this.inverted = false})
      : kind = PatternKind.stripes;

  @override
  String toString() => kind == PatternKind.stripes
      ? 'stripes(${axis!.name}, bit $bit${inverted ? ', inverted' : ''})'
      : kind.name;
}

/// The full list of patterns for one scan of a projector.
///
/// Order: white, black, then every x bit from coarse to fine (each followed
/// by its inverse), then every y bit the same way. The decoder expects the
/// captured frames in this order.
class PatternSet {
  final int projectorWidth;
  final int projectorHeight;

  /// Projector pixels are grouped into cells of `1 << coarseShift` pixels and
  /// only the cell index is encoded. The finest stripe is two cells wide, so
  /// the default of 1 gives 4-pixel stripes, which survive a soft lens.
  final int coarseShift;

  late final int cellsX;
  late final int cellsY;
  late final int bitsX;
  late final int bitsY;
  late final List<PatternSpec> specs;

  PatternSet(this.projectorWidth, this.projectorHeight, {this.coarseShift = 1}) {
    if (projectorWidth <= 0 || projectorHeight <= 0) {
      throw ArgumentError('Projector size must be positive');
    }
    if (coarseShift < 0 || coarseShift > 6) {
      throw ArgumentError('coarseShift must be between 0 and 6');
    }
    cellsX = (projectorWidth + cellSize - 1) >> coarseShift;
    cellsY = (projectorHeight + cellSize - 1) >> coarseShift;
    bitsX = bitsFor(cellsX);
    bitsY = bitsFor(cellsY);

    final list = <PatternSpec>[
      const PatternSpec.white(),
      const PatternSpec.black(),
    ];
    for (var bit = bitsX - 1; bit >= 0; bit--) {
      list.add(PatternSpec.stripes(StripeAxis.columns, bit));
      list.add(PatternSpec.stripes(StripeAxis.columns, bit, inverted: true));
    }
    for (var bit = bitsY - 1; bit >= 0; bit--) {
      list.add(PatternSpec.stripes(StripeAxis.rows, bit));
      list.add(PatternSpec.stripes(StripeAxis.rows, bit, inverted: true));
    }
    specs = List.unmodifiable(list);
  }

  int get cellSize => 1 << coarseShift;

  /// Width in projector pixels of the narrowest stripe in the set.
  int get minStripeWidth => 2 << coarseShift;

  /// Draws [spec] at projector resolution. 255 is lit, 0 is dark.
  GrayImage render(PatternSpec spec) {
    final image = GrayImage(projectorWidth, projectorHeight);
    switch (spec.kind) {
      case PatternKind.black:
        return image;
      case PatternKind.white:
        image.data.fillRange(0, image.data.length, 255);
        return image;
      case PatternKind.stripes:
        final byColumn = spec.axis == StripeAxis.columns;
        final length = byColumn ? projectorWidth : projectorHeight;
        final line = List<int>.filled(length, 0);
        for (var i = 0; i < length; i++) {
          final on = ((toGray(i >> coarseShift) >> spec.bit) & 1) == 1;
          line[i] = (on != spec.inverted) ? 255 : 0;
        }
        for (var y = 0; y < projectorHeight; y++) {
          final row = y * projectorWidth;
          for (var x = 0; x < projectorWidth; x++) {
            image.data[row + x] = byColumn ? line[x] : line[y];
          }
        }
        return image;
    }
  }
}
