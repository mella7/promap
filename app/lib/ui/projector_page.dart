import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../devices/output_controller.dart';
import 'output_view.dart';

/// The projector output alone, full screen, on black. With screen mirroring
/// the phone's own screen is what the projector shows, so this is the view
/// to leave open while scanning and while the mapping plays. Double-tap to
/// go back.
class ProjectorPage extends StatefulWidget {
  final OutputController controller;

  const ProjectorPage({super.key, required this.controller});

  @override
  State<ProjectorPage> createState() => _ProjectorPageState();
}

class _ProjectorPageState extends State<ProjectorPage> {
  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    // Hide the status and navigation bars so they don't end up on the wall.
    if (_mobile) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    if (_mobile) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final output = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => Navigator.of(context).pop(),
        child: Center(
          child: AspectRatio(
            aspectRatio: output.width / output.height,
            child: OutputView(controller: output, showFps: false),
          ),
        ),
      ),
    );
  }
}
