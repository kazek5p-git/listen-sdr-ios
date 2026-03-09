import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingMetadataController {
  static let shared = NowPlayingMetadataController()

  private var defaultArtwork: MPMediaItemArtwork?
  private var activeSource = "Live SDR stream"
  private var activeReceiverName: String?
  private var activeTitle: String?
  private var playbackMuted = false

  private init() {}

  func startPlayback(source: String) {
    activeSource = source
    refreshNowPlayingInfo()
  }

  func stopPlayback() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  func setReceiverName(_ name: String?) {
    activeReceiverName = normalized(name)
    refreshNowPlayingInfoIfVisible()
  }

  func setTitle(_ title: String?) {
    activeTitle = normalized(title)
    refreshNowPlayingInfoIfVisible()
  }

  func setMuted(_ muted: Bool) {
    playbackMuted = muted
    refreshNowPlayingInfoIfVisible()
  }

  private func artwork() -> MPMediaItemArtwork? {
    if let defaultArtwork {
      return defaultArtwork
    }

    guard let image = UIImage(named: "NowPlayingArtwork") else {
      return nil
    }

    let generated = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    defaultArtwork = generated
    return generated
  }

  private func refreshNowPlayingInfoIfVisible() {
    guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
    refreshNowPlayingInfo()
  }

  private func refreshNowPlayingInfo() {
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Listen SDR"
    let displayTitle = activeTitle ?? activeReceiverName ?? appName
    let displayArtist = activeTitle != nil
      ? (activeReceiverName ?? activeSource)
      : activeSource

    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: displayTitle,
      MPMediaItemPropertyArtist: displayArtist,
      MPNowPlayingInfoPropertyIsLiveStream: true,
      MPNowPlayingInfoPropertyPlaybackRate: playbackMuted ? 0.0 : 1.0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
    ]

    if let artwork = artwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    MPNowPlayingInfoCenter.default().playbackState = playbackMuted ? .paused : .playing
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
