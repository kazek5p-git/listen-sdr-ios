import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingMetadataController {
  static let shared = NowPlayingMetadataController()

  private var defaultArtwork: MPMediaItemArtwork?
  private var activeSource = "Live SDR stream"
  private var playbackMuted = false

  private init() {}

  func startPlayback(source: String) {
    activeSource = source
    let nowPlayingTitle = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Listen SDR"
    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: nowPlayingTitle,
      MPMediaItemPropertyArtist: activeSource,
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

  func stopPlayback() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  func setMuted(_ muted: Bool) {
    playbackMuted = muted
    guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
    info[MPNowPlayingInfoPropertyPlaybackRate] = muted ? 0.0 : 1.0
    info[MPMediaItemPropertyArtist] = activeSource
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = muted ? .paused : .playing
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
}
