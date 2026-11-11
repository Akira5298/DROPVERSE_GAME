import CoreGraphics

/// Consistent scene coordinate system across iPhone screen sizes.
///
/// The scene is always `designHeight` points tall. Width follows the device aspect
/// ratio (clamped), so the scene fills the screen exactly with `.aspectFit` and no
/// letterboxing on any current iPhone. Vertical gameplay geometry is identical on
/// every device; wider phones simply see further ahead. Because hazards are timed
/// on the music clock, not spawned by screen edge, look-ahead does not change difficulty.
struct SceneMetrics: Equatable {
    static let designHeight: CGFloat = 720
    static let minAspect: CGFloat = 4.0 / 3.0
    static let maxAspect: CGFloat = 2.2

    let sceneSize: CGSize
    /// Top surface of the ground, in scene points.
    let groundY: CGFloat
    /// Fixed horizontal position of the player (and the musical playhead).
    let playerX: CGFloat

    init(viewSize: CGSize) {
        let aspect: CGFloat
        if viewSize.width > 0, viewSize.height > 0 {
            aspect = viewSize.width / viewSize.height
        } else {
            aspect = 16.0 / 9.0
        }
        let clamped = min(max(aspect, Self.minAspect), Self.maxAspect)
        sceneSize = CGSize(width: (Self.designHeight * clamped).rounded(), height: Self.designHeight)
        groundY = 150
        playerX = 300
    }

    /// Distance from the playhead to the right edge of the screen.
    var lookAhead: CGFloat { sceneSize.width - playerX }
}
