import AudioToolbox
import AVFAudio
import Foundation

final class FMDXMP3RecognitionDecoder {
  private let defaultOutputFrameCapacity: AVAudioFrameCount = 4096

  private var inputFormat: AVAudioFormat?
  private var outputFormat: AVAudioFormat?
  private var converter: AVAudioConverter?

  func reset() {
    converter?.reset()
    converter = nil
    inputFormat = nil
    outputFormat = nil
  }

  func updateStreamDescription(_ description: AudioStreamBasicDescription) {
    var mutableDescription = description
    guard let inputFormat = AVAudioFormat(streamDescription: &mutableDescription) else {
      reset()
      return
    }

    let channelCount = AVAudioChannelCount(max(Int(description.mChannelsPerFrame), 1))
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: description.mSampleRate,
      channels: channelCount,
      interleaved: false
    ) else {
      reset()
      return
    }

    self.inputFormat = inputFormat
    self.outputFormat = outputFormat
    converter = AVAudioConverter(from: inputFormat, to: outputFormat)
  }

  func decodePacket(
    packetData: UnsafeRawPointer,
    packetSize: Int,
    packetDescription: AudioStreamPacketDescription
  ) -> (samples: [Float], sampleRate: Double)? {
    guard packetSize > 0 else { return nil }
    guard let inputFormat, let outputFormat, let converter else { return nil }

    let compressedBuffer = AVAudioCompressedBuffer(
      format: inputFormat,
      packetCapacity: 1,
      maximumPacketSize: max(packetSize, 1)
    )
    compressedBuffer.packetCount = 1
    compressedBuffer.byteLength = UInt32(packetSize)
    memcpy(compressedBuffer.data, packetData, packetSize)
    if let packetDescriptions = compressedBuffer.packetDescriptions {
      packetDescriptions[0] = AudioStreamPacketDescription(
        mStartOffset: 0,
        mVariableFramesInPacket: packetDescription.mVariableFramesInPacket,
        mDataByteSize: UInt32(packetSize)
      )
    }

    let outputFrameCapacity = max(
      defaultOutputFrameCapacity,
      AVAudioFrameCount(max(Int(packetDescription.mVariableFramesInPacket), 1))
    )
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: outputFrameCapacity
    ) else {
      return nil
    }

    var providedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
      if providedInput {
        outStatus.pointee = .endOfStream
        return nil
      }

      providedInput = true
      outStatus.pointee = .haveData
      return compressedBuffer
    }

    if conversionError != nil {
      return nil
    }

    switch status {
    case .haveData, .inputRanDry, .endOfStream:
      break
    case .error:
      return nil
    @unknown default:
      return nil
    }

    guard outputBuffer.frameLength > 0 else { return nil }
    let samples = floatSamples(from: outputBuffer)
    guard !samples.isEmpty else { return nil }
    return (samples, outputFormat.sampleRate)
  }

  private func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channels = buffer.int16ChannelData else { return [] }

    let channelCount = Int(buffer.format.channelCount)
    let frameCount = Int(buffer.frameLength)
    guard channelCount > 0, frameCount > 0 else { return [] }

    var output: [Float] = []
    output.reserveCapacity(frameCount)

    if channelCount == 1 {
      let channel = channels[0]
      for frame in 0..<frameCount {
        output.append((Float(channel[frame]) + 0.5) / 32768.0)
      }
      return output
    }

    for frame in 0..<frameCount {
      var accumulator = 0
      for channelIndex in 0..<channelCount {
        accumulator += Int(channels[channelIndex][frame])
      }
      let averagedSample = Float(accumulator) / Float(channelCount)
      output.append((averagedSample + 0.5) / 32768.0)
    }

    return output
  }
}
