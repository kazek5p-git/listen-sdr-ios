import Foundation

private let imaAdpcmStepTable: [Int] = [
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
  19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
  50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
  130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
  337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
  876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
  2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
  5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
  15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
]

private let imaAdpcmIndexTable: [Int] = [
  -1, -1, -1, -1,
  2, 4, 6, 8,
  -1, -1, -1, -1,
  2, 4, 6, 8
]

struct KiwiIMAADPCMDecoder {
  private(set) var stepIndex: Int = 0
  private(set) var predictor: Int = 0

  mutating func reset() {
    stepIndex = 0
    predictor = 0
  }

  mutating func decode(_ data: Data) -> [Int16] {
    var output: [Int16] = []
    output.reserveCapacity(data.count * 2)

    for byte in data {
      output.append(decodeNibble(Int(byte & 0x0F)))
      output.append(decodeNibble(Int(byte >> 4)))
    }

    return output
  }

  private mutating func decodeNibble(_ nibble: Int) -> Int16 {
    let boundedNibble = nibble & 0x0F
    let step = imaAdpcmStepTable[stepIndex]

    stepIndex += imaAdpcmIndexTable[boundedNibble]
    stepIndex = min(max(stepIndex, 0), imaAdpcmStepTable.count - 1)

    var diff = step >> 3
    if (boundedNibble & 1) != 0 { diff += step >> 2 }
    if (boundedNibble & 2) != 0 { diff += step >> 1 }
    if (boundedNibble & 4) != 0 { diff += step }
    if (boundedNibble & 8) != 0 { diff = -diff }

    predictor += diff
    predictor = min(max(predictor, -32_768), 32_767)
    return Int16(predictor)
  }
}

struct OpenWebRXSyncADPCMDecoder {
  private enum Phase {
    case syncSearch
    case syncState
    case audio
  }

  private let syncWord: [UInt8] = Array("SYNC".utf8)
  private var phase: Phase = .syncSearch
  private var synchronizedCount = 0
  private var syncCounter = 0
  private var syncBuffer = [UInt8](repeating: 0, count: 4)
  private var syncBufferIndex = 0

  private var stepIndex = 0
  private var predictor = 0
  private var step = 0

  mutating func reset() {
    phase = .syncSearch
    synchronizedCount = 0
    syncCounter = 0
    syncBufferIndex = 0
    stepIndex = 0
    predictor = 0
    step = 0
  }

  mutating func decodeWithSync(_ data: Data) -> [Int16] {
    var output: [Int16] = []
    output.reserveCapacity(data.count * 2)

    for byte in data {
      switch phase {
      case .syncSearch:
        if byte == syncWord[synchronizedCount] {
          synchronizedCount += 1
        } else {
          synchronizedCount = 0
        }

        if synchronizedCount == syncWord.count {
          syncBufferIndex = 0
          phase = .syncState
        }

      case .syncState:
        syncBuffer[syncBufferIndex] = byte
        syncBufferIndex += 1

        if syncBufferIndex == syncBuffer.count {
          let indexRaw = Int16(bitPattern: UInt16(syncBuffer[0]) | (UInt16(syncBuffer[1]) << 8))
          let predictorRaw = Int16(bitPattern: UInt16(syncBuffer[2]) | (UInt16(syncBuffer[3]) << 8))
          stepIndex = min(max(Int(indexRaw), 0), imaAdpcmStepTable.count - 1)
          predictor = Int(predictorRaw)
          syncCounter = 1000
          phase = .audio
        }

      case .audio:
        output.append(decodeNibble(Int(byte & 0x0F)))
        output.append(decodeNibble(Int(byte >> 4)))

        if syncCounter == 0 {
          synchronizedCount = 0
          phase = .syncSearch
        } else {
          syncCounter -= 1
        }
      }
    }

    return output
  }

  private mutating func decodeNibble(_ nibble: Int) -> Int16 {
    let boundedNibble = nibble & 0x0F

    stepIndex += imaAdpcmIndexTable[boundedNibble]
    stepIndex = min(max(stepIndex, 0), imaAdpcmStepTable.count - 1)

    var diff = step >> 3
    if (boundedNibble & 1) != 0 { diff += step >> 2 }
    if (boundedNibble & 2) != 0 { diff += step >> 1 }
    if (boundedNibble & 4) != 0 { diff += step }
    if (boundedNibble & 8) != 0 { diff = -diff }

    predictor += diff
    predictor = min(max(predictor, -32_768), 32_767)
    step = imaAdpcmStepTable[stepIndex]
    return Int16(predictor)
  }
}

func decodeInt16PCM(_ data: Data, littleEndian: Bool) -> [Int16] {
  let bytes = [UInt8](data)
  let sampleCount = bytes.count / 2
  guard sampleCount > 0 else { return [] }

  var output: [Int16] = []
  output.reserveCapacity(sampleCount)

  for index in 0..<sampleCount {
    let byteOffset = index * 2
    let lo = UInt16(bytes[byteOffset])
    let hi = UInt16(bytes[byteOffset + 1])
    let value: UInt16 = littleEndian ? (lo | (hi << 8)) : ((lo << 8) | hi)
    output.append(Int16(bitPattern: value))
  }

  return output
}

func downmixInterleavedStereoPCM(_ data: [Int16]) -> [Int16] {
  guard data.count >= 2 else { return data }

  let frameCount = data.count / 2
  guard frameCount > 0 else { return [] }

  var output: [Int16] = []
  output.reserveCapacity(frameCount)

  for frameIndex in 0..<frameCount {
    let baseIndex = frameIndex * 2
    let left = Int(data[baseIndex])
    let right = Int(data[baseIndex + 1])
    output.append(Int16((left + right) / 2))
  }

  return output
}

func int16ToFloatPCM(_ data: [Int16]) -> [Float] {
  data.map { sample in
    (Float(sample) + 0.5) / 32768.0
  }
}
