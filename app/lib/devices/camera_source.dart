import 'package:calib_core/calib_core.dart';

/// Anything that can take a grey camera frame: the simulator now, the phone
/// camera in step 0.
abstract interface class CameraSource {
  int get width;
  int get height;

  /// Takes one frame with the current, locked camera settings.
  Future<GrayImage> capture();
}
