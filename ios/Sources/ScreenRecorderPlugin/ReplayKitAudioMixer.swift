import AVFoundation
import CoreMedia

final class ReplayKitAudioTrackMixer {
    private var micQueue: [CMSampleBuffer] = []
    private var pendingAppQueue: [CMSampleBuffer] = []
    private var referenceAppBuffer: CMSampleBuffer?
    private let maxMicQueueSize = 128

    func handleMic(_ sampleBuffer: CMSampleBuffer) -> [CMSampleBuffer] {
        micQueue.append(sampleBuffer)
        var outputs: [CMSampleBuffer] = []
        while micQueue.count > maxMicQueueSize {
            let micOnly = micQueue.removeFirst()
            if let normalized = Self.normalizeForWriter(micOnly, reference: referenceAppBuffer) {
                outputs.append(normalized)
            }
        }
        outputs.append(contentsOf: emitReadySamples())
        return outputs
    }

    func handleApp(_ sampleBuffer: CMSampleBuffer) -> [CMSampleBuffer] {
        if referenceAppBuffer == nil {
            referenceAppBuffer = sampleBuffer
        }
        pendingAppQueue.append(sampleBuffer)
        return emitReadySamples()
    }

    func drain() -> [CMSampleBuffer] {
        var outputs = emitReadySamples()
        for mic in micQueue {
            if let normalized = Self.normalizeForWriter(mic, reference: referenceAppBuffer) {
                outputs.append(normalized)
            }
        }
        for app in pendingAppQueue {
            outputs.append(app)
        }
        micQueue.removeAll()
        pendingAppQueue.removeAll()
        return outputs
    }

    private func emitReadySamples() -> [CMSampleBuffer] {
        var outputs: [CMSampleBuffer] = []

        while let mic = micQueue.first {
            let nextAppStart = pendingAppQueue.first.map { Self.startTime(of: $0) }
            guard let appStart = nextAppStart else { break }
            if CMTimeCompare(Self.endTime(of: mic), appStart) <= 0 {
                micQueue.removeFirst()
                if let normalized = Self.normalizeForWriter(mic, reference: referenceAppBuffer) {
                    outputs.append(normalized)
                }
            } else {
                break
            }
        }

        while let app = pendingAppQueue.first,
              let mic = micQueue.first,
              Self.rangesOverlap(mic, app) {
            pendingAppQueue.removeFirst()
            micQueue.removeFirst()
            if let mixed = ReplayKitAudioMixer.mix(app: app, mic: mic) {
                outputs.append(mixed)
            } else {
                outputs.append(app)
                micQueue.insert(mic, at: 0)
                break
            }
        }

        while let app = pendingAppQueue.first {
            if let mic = micQueue.first {
                if CMTimeCompare(Self.startTime(of: mic), Self.endTime(of: app)) > 0 {
                    pendingAppQueue.removeFirst()
                    outputs.append(app)
                } else {
                    break
                }
            } else {
                pendingAppQueue.removeFirst()
                outputs.append(app)
            }
        }

        return outputs
    }

    private static func startTime(of buffer: CMSampleBuffer) -> CMTime {
        CMSampleBufferGetPresentationTimeStamp(buffer)
    }

    private static func endTime(of buffer: CMSampleBuffer) -> CMTime {
        CMTimeRangeGetEnd(timeRange(of: buffer))
    }

    private static func sampleRate(of buffer: CMSampleBuffer) -> Double {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            return 48_000
        }
        return asbd.mSampleRate
    }

    private static func timeRange(of buffer: CMSampleBuffer) -> CMTimeRange {
        let start = CMSampleBufferGetPresentationTimeStamp(buffer)
        let duration = CMSampleBufferGetDuration(buffer)
        if duration.isValid, duration > .zero {
            return CMTimeRange(start: start, duration: duration)
        }

        let frames = CMSampleBufferGetNumSamples(buffer)
        let timescale = CMTimeScale(sampleRate(of: buffer))
        return CMTimeRange(start: start, duration: CMTime(value: CMTimeValue(frames), timescale: timescale))
    }

    private static func rangesOverlap(_ lhs: CMSampleBuffer, _ rhs: CMSampleBuffer) -> Bool {
        let intersection = CMTimeRangeGetIntersection(timeRange(of: lhs), otherRange: timeRange(of: rhs))
        return intersection.duration.isValid && intersection.duration > .zero
    }

    private static func normalizeForWriter(_ buffer: CMSampleBuffer, reference: CMSampleBuffer?) -> CMSampleBuffer? {
        guard let reference = reference else { return buffer }
        return ReplayKitAudioMixer.matchFormat(buffer, to: reference) ?? buffer
    }
}

enum ReplayKitAudioMixer {
    static func mix(app: CMSampleBuffer, mic: CMSampleBuffer) -> CMSampleBuffer? {
        guard CMSampleBufferDataIsReady(app), CMSampleBufferDataIsReady(mic) else { return nil }

        guard let appFormat = CMSampleBufferGetFormatDescription(app),
              let micFormat = CMSampleBufferGetFormatDescription(mic),
              let appAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(appFormat)?.pointee,
              let micAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(micFormat)?.pointee,
              appAsbd.mFormatID == kAudioFormatLinearPCM,
              micAsbd.mFormatID == kAudioFormatLinearPCM,
              (appAsbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0,
              (micAsbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0,
              (appAsbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              (micAsbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              appAsbd.mBitsPerChannel == 16,
              micAsbd.mBitsPerChannel == 16,
              appAsbd.mSampleRate == micAsbd.mSampleRate else {
            return nil
        }

        let appRange = timeRange(of: app)
        let micRange = timeRange(of: mic)
        let intersection = CMTimeRangeGetIntersection(appRange, otherRange: micRange)
        guard intersection.duration.isValid, intersection.duration > .zero else { return nil }

        let sampleRate = appAsbd.mSampleRate
        let appStartFrame = frameOffset(for: intersection.start, relativeTo: appRange.start, sampleRate: sampleRate)
        let micStartFrame = frameOffset(for: intersection.start, relativeTo: micRange.start, sampleRate: sampleRate)
        let mixFrames = frameCount(for: intersection.duration, sampleRate: sampleRate)
        guard mixFrames > 0 else { return nil }

        let appFrames = CMSampleBufferGetNumSamples(app)
        let micFrames = CMSampleBufferGetNumSamples(mic)
        let appAvailable = appFrames - appStartFrame
        let micAvailable = micFrames - micStartFrame
        let frames = min(mixFrames, appAvailable, micAvailable)
        guard frames > 0 else { return nil }

        guard let appBlock = CMSampleBufferGetDataBuffer(app),
              let micBlock = CMSampleBufferGetDataBuffer(mic) else {
            return nil
        }

        var mixedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: app,
            sampleBufferOut: &mixedBuffer
        )
        guard copyStatus == noErr,
              let output = mixedBuffer,
              let outputBlock = CMSampleBufferGetDataBuffer(output) else {
            return nil
        }

        let appChannels = Int(appAsbd.mChannelsPerFrame)
        let micChannels = Int(micAsbd.mChannelsPerFrame)
        let appBytesPerFrame = Int(appAsbd.mBytesPerFrame)
        let micBytesPerFrame = Int(micAsbd.mBytesPerFrame)
        let outputBytes = frames * appBytesPerFrame
        let appByteOffset = appStartFrame * appBytesPerFrame
        let micByteOffset = micStartFrame * micBytesPerFrame
        let micBytes = frames * micBytesPerFrame

        var appSamples = [Int16](repeating: 0, count: outputBytes / MemoryLayout<Int16>.size)
        var micSamples = [Int16](repeating: 0, count: micBytes / MemoryLayout<Int16>.size)

        let appCopyStatus = appSamples.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                appBlock,
                atOffset: appByteOffset,
                dataLength: outputBytes,
                destination: destination.baseAddress!
            )
        }
        let micCopyStatus = micSamples.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                micBlock,
                atOffset: micByteOffset,
                dataLength: micBytes,
                destination: destination.baseAddress!
            )
        }
        guard appCopyStatus == noErr, micCopyStatus == noErr else { return nil }

        for frame in 0..<frames {
            let micSample = micChannels == 1
                ? Int32(micSamples[frame])
                : Int32(micSamples[frame * micChannels])
            for channel in 0..<appChannels {
                let index = frame * appChannels + channel
                let mixed = max(Int32(Int16.min), min(Int32(Int16.max), Int32(appSamples[index]) + micSample))
                appSamples[index] = Int16(mixed)
            }
        }

        let replaceStatus = appSamples.withUnsafeMutableBytes { source in
            CMBlockBufferReplaceDataBytes(source.baseAddress, outputBlock, appByteOffset, outputBytes)
        }
        guard replaceStatus == noErr else { return nil }

        return output
    }

    static func matchFormat(_ buffer: CMSampleBuffer, to reference: CMSampleBuffer) -> CMSampleBuffer? {
        guard CMSampleBufferDataIsReady(buffer), CMSampleBufferDataIsReady(reference) else { return nil }
        guard let bufferFormat = CMSampleBufferGetFormatDescription(buffer),
              let referenceFormat = CMSampleBufferGetFormatDescription(reference),
              let bufferAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(bufferFormat)?.pointee,
              let referenceAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(referenceFormat)?.pointee,
              bufferAsbd.mFormatID == kAudioFormatLinearPCM,
              referenceAsbd.mFormatID == kAudioFormatLinearPCM,
              (bufferAsbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              (referenceAsbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              bufferAsbd.mBitsPerChannel == 16,
              referenceAsbd.mBitsPerChannel == 16,
              bufferAsbd.mSampleRate == referenceAsbd.mSampleRate else {
            return nil
        }

        let bufferChannels = Int(bufferAsbd.mChannelsPerFrame)
        let referenceChannels = Int(referenceAsbd.mChannelsPerFrame)
        if bufferChannels == referenceChannels {
            return buffer
        }

        guard bufferChannels == 1, referenceChannels > 1,
              let block = CMSampleBufferGetDataBuffer(buffer) else {
            return nil
        }

        let frames = CMSampleBufferGetNumSamples(buffer)
        let inputBytes = frames * Int(bufferAsbd.mBytesPerFrame)
        let outputBytes = frames * referenceChannels * MemoryLayout<Int16>.size
        var monoSamples = [Int16](repeating: 0, count: inputBytes / MemoryLayout<Int16>.size)
        let copyStatus = monoSamples.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: inputBytes, destination: destination.baseAddress!)
        }
        guard copyStatus == noErr else { return nil }

        var stereoSamples = [Int16]()
        stereoSamples.reserveCapacity(frames * referenceChannels)
        for frame in 0..<frames {
            let sample = monoSamples[frame]
            for _ in 0..<referenceChannels {
                stereoSamples.append(sample)
            }
        }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: outputBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: outputBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let outputBlock = blockBuffer else { return nil }

        let replaceStatus = stereoSamples.withUnsafeMutableBytes { source in
            CMBlockBufferReplaceDataBytes(source.baseAddress, outputBlock, 0, outputBytes)
        }
        guard replaceStatus == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(buffer),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(buffer)
        )
        var outputBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: outputBlock,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: referenceFormat,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outputBuffer
        )
        guard createStatus == noErr else { return nil }
        return outputBuffer
    }

    private static func timeRange(of buffer: CMSampleBuffer) -> CMTimeRange {
        let start = CMSampleBufferGetPresentationTimeStamp(buffer)
        let duration = CMSampleBufferGetDuration(buffer)
        if duration.isValid, duration > .zero {
            return CMTimeRange(start: start, duration: duration)
        }

        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            return CMTimeRange(start: start, duration: .zero)
        }

        let frames = CMSampleBufferGetNumSamples(buffer)
        let timescale = CMTimeScale(asbd.mSampleRate)
        return CMTimeRange(start: start, duration: CMTime(value: CMTimeValue(frames), timescale: timescale))
    }

    private static func frameOffset(for time: CMTime, relativeTo start: CMTime, sampleRate: Double) -> Int {
        let delta = CMTimeSubtract(time, start)
        return max(0, Int((CMTimeGetSeconds(delta) * sampleRate).rounded()))
    }

    private static func frameCount(for duration: CMTime, sampleRate: Double) -> Int {
        max(0, Int((CMTimeGetSeconds(duration) * sampleRate).rounded()))
    }
}
