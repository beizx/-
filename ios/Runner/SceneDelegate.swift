import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// With `UIApplicationSceneManifest` enabled, iOS delivers document URLs to
  /// the scene rather than the app delegate. Forward them so "用其他应用打开"
  /// works the same as on Android.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      for context in URLContexts {
        appDelegate.handleIncomingFile(context.url)
      }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
