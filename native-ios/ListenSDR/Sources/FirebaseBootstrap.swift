import Foundation
import FirebaseCore
import FirebaseCrashlytics
import FirebaseRemoteConfig

enum FirebaseBootstrap {
  static func configure() {
    guard FirebaseApp.app() == nil else {
      return
    }

    guard let configPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
      Diagnostics.log(
        severity: .warning,
        category: "Firebase",
        message: "GoogleService-Info.plist is not bundled; Firebase is disabled."
      )
      return
    }

    guard let options = FirebaseOptions(contentsOfFile: configPath) else {
      Diagnostics.log(
        severity: .error,
        category: "Firebase",
        message: "GoogleService-Info.plist could not be parsed; Firebase is disabled."
      )
      return
    }

    FirebaseApp.configure(options: options)

    let crashlyticsEnabled = infoBoolean("ListenSDRFirebaseCrashlyticsEnabled")
    Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(crashlyticsEnabled)
    Crashlytics.crashlytics().setCustomValue(
      Bundle.main.bundleIdentifier ?? "unknown",
      forKey: "bundleIdentifier"
    )
    Crashlytics.crashlytics().setCustomValue(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      forKey: "appVersion"
    )
    Crashlytics.crashlytics().setCustomValue(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      forKey: "buildNumber"
    )

    if infoBoolean("ListenSDRFirebaseRemoteConfigEnabled") {
      configureRemoteConfig()
    }

    Diagnostics.log(
      category: "Firebase",
      message: "Firebase configured. Crashlytics collection: \(crashlyticsEnabled ? "enabled" : "disabled")."
    )
  }

  private static func configureRemoteConfig() {
    let remoteConfig = RemoteConfig.remoteConfig()
    let settings = RemoteConfigSettings()
    settings.minimumFetchInterval = 3600
    remoteConfig.configSettings = settings
    remoteConfig.setDefaults([
      "listen_sdr_firebase_configured": NSNumber(value: true),
      "listen_sdr_ios_update_enabled": NSNumber(value: false),
      "listen_sdr_ios_latest_build_number": NSNumber(value: 0),
      "listen_sdr_ios_latest_version_name": "" as NSString,
      "listen_sdr_ios_update_url": "" as NSString,
      "listen_sdr_ios_release_page_url": "" as NSString,
      "listen_sdr_ios_update_message_en": "" as NSString,
      "listen_sdr_ios_update_message_pl": "" as NSString,
      "listen_sdr_ios_update_severity": "none" as NSString
    ])
  }

  private static func infoBoolean(_ key: String) -> Bool {
    if let value = Bundle.main.object(forInfoDictionaryKey: key) as? Bool {
      return value
    }
    if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
      return ["1", "true", "yes"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    return false
  }
}
