import 'package:calib_core/calib_core.dart';
import 'package:flutter/material.dart';

import 'gray_image_view.dart';

/// The camera picture. Tapping it reports the camera pixel under the finger.
class CameraView extends StatelessWidget {
  final GrayImage? frame;
  final void Function(int x, int y) onTap;

  const CameraView({super.key, required this.frame, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = frame;
    if (image == null) {
      return const Center(child: Text('No camera frame yet'));
    }
    return AspectRatio(
      aspectRatio: image.width / image.height,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapDown: (details) {
            final x = _cell(details.localPosition.dx, constraints.maxWidth,
                image.width);
            final y = _cell(details.localPosition.dy, constraints.maxHeight,
                image.height);
            onTap(x, y);
          },
          child: GrayImageView(image),
        ),
      ),
    );
  }
}

/// The pixel index under [position] when [extent] screen pixels show
/// [count] image pixels.
int _cell(double position, double extent, int count) {
  final index = (position / extent * count).floor();
  if (index < 0) return 0;
  if (index >= count) return count - 1;
  return index;
}
