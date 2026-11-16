/// Binary-reflected Gray code helpers.
///
/// Neighbouring numbers differ in exactly one bit, so a pixel sitting on a
/// stripe edge can only be wrong by one step.
library;

int toGray(int n) => n ^ (n >> 1);

int fromGray(int g) {
  var n = g;
  var shift = g >> 1;
  while (shift != 0) {
    n ^= shift;
    shift >>= 1;
  }
  return n;
}

/// Number of bits needed to tell [count] values apart (at least 1).
int bitsFor(int count) {
  var bits = 1;
  while ((1 << bits) < count) {
    bits++;
  }
  return bits;
}
