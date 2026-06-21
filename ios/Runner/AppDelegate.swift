import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 👇 【追加】 .env ファイルからAPIキーを読み込む処理
    var apiKey = ""
    if let envPath = Bundle.main.path(forResource: ".env", ofType: nil) {
        do {
            let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
            let lines = envContent.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("GOOGLE_MAPS_API_KEY=") {
                    apiKey = line.replacingOccurrences(of: "GOOGLE_MAPS_API_KEY=", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        } catch {
            print("Error loading .env file")
        }
    }

    // 👇 抽出したAPIキーをGoogle Mapsに渡す（直書きを排除！）
    GMSServices.provideAPIKey(apiKey)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
