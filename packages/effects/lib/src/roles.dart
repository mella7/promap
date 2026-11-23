import 'package:scene_core/scene_core.dart';

/// What part a surface plays in a scene. Themes pick effects by role.
enum SurfaceRole {
  /// Walls, floors, big flat areas behind things.
  background,

  /// Boxes, furniture, anything standing in front.
  object,
}

const _backgroundLabels = {'wall', 'floor', 'ceiling', 'background', 'facade'};

/// Surfaces covering more than this share of the projector image count as
/// background when their label doesn't say otherwise.
const backgroundAreaShare = 0.2;

/// The role of [surface]: its label decides when it names a known kind of
/// thing, otherwise its size does.
SurfaceRole roleOf(Surface surface, Scene scene) {
  final label = surface.label?.toLowerCase();
  if (label != null) {
    if (_backgroundLabels.contains(label)) return SurfaceRole.background;
    if (label.isNotEmpty) return SurfaceRole.object;
  }
  final share = surface.area / (scene.projectorWidth * scene.projectorHeight);
  return share > backgroundAreaShare ? SurfaceRole.background : SurfaceRole.object;
}
