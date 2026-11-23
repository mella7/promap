import 'package:mapping_core/mapping_core.dart';

/// Decodes a run-length mask from the backend.
///
/// Runs go over the pixels in row order and alternate between "not in the
/// mask" and "in the mask", starting with "not in the mask". See
/// docs/backend-api.md.
BinaryMask decodeRle(List<int> counts, int width, int height) {
  var total = 0;
  for (final run in counts) {
    if (run < 0) throw const FormatException('Mask runs must not be negative');
    total += run;
  }
  if (total != width * height) {
    throw FormatException(
        'Mask runs add up to $total, expected ${width * height}');
  }
  final mask = BinaryMask(width, height);
  var position = 0;
  for (var i = 0; i < counts.length; i++) {
    final run = counts[i];
    if (i.isOdd) mask.data.fillRange(position, position + run, 1);
    position += run;
  }
  return mask;
}
