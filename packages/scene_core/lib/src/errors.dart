/// Thrown when a scene, surface or operation breaks a rule, for example a
/// duplicate id or a polygon with two corners. Nothing is changed when this
/// is thrown.
class SceneError implements Exception {
  final String message;

  const SceneError(this.message);

  @override
  String toString() => 'SceneError: $message';
}
