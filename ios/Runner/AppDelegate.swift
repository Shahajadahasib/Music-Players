import Flutter
import UIKit

/// Uses classic `GeneratedPluginRegistrant` registration in `didFinishLaunching`.
///
/// **Why:** On iOS 26 + ProMotion devices, the default *implicit engine* template
/// (`FlutterImplicitEngineDelegate`) can crash at launch with
/// `-[VSyncClient initWithTaskRunner:callback:]` (race: `viewDidLoad` before the
/// implicit engine’s task runner exists). See flutter/flutter#183900.
/// Revert to the implicit-engine pattern after Flutter ships an engine fix if you prefer it.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
