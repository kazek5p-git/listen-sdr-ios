import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingMetadataController {
  static let shared = NowPlayingMetadataController()

  private var defaultArtwork: MPMediaItemArtwork?

  private init() {}

  func startPlayback(source: String) {
    let nowPlayingTitle = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Listen SDR"
    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: nowPlayingTitle,
      MPMediaItemPropertyArtist: source,
      MPNowPlayingInfoPropertyIsLiveStream: true,
      MPNowPlayingInfoPropertyPlaybackRate: 1.0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
    ]

    if let artwork = artwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    MPNowPlayingInfoCenter.default().playbackState = .playing
  }

  func stopPlayback() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
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
