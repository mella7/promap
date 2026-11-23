import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:calib_core/calib_core.dart';
import 'package:flutter/widgets.dart';

/// Turns a grey image into something Flutter can draw.
Future<ui.Image> grayToUiImage(GrayImage gray) {
  final rgba = Uint8List(gray.width * gray.height * 4);
  for (var i = 0; i < gray.data.length; i++) {
    final v = gray.data[i];
    final o = i * 4;
    rgba[o] = v;
    rgba[o + 1] = v;
    rgba[o + 2] = v;
    rgba[o + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, gray.width, gray.height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// Shows a [GrayImage], stretched to fill its box. Wrap it in an
/// [AspectRatio] to keep the shape.
class GrayImageView extends StatefulWidget {
  final GrayImage image;
  final FilterQuality filterQuality;

  const GrayImageView(this.image,
      {super.key, this.filterQuality = FilterQuality.low});

  @override
  State<GrayImageView> createState() => _GrayImageViewState();
}

class _GrayImageViewState extends State<GrayImageView> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _convert(widget.image);
  }

  @override
  void didUpdateWidget(GrayImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) _convert(widget.image);
  }

  Future<void> _convert(GrayImage gray) async {
    final image = await grayToUiImage(gray);
    if (!mounted || !identical(gray, widget.image)) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const ColoredBox(color: Color(0xFF000000));
    return RawImage(
      image: image,
      fit: BoxFit.fill,
      filterQuality: widget.filterQuality,
    );
  }
}
