import AVFoundation
import CoreMedia

final class ReplayKitAudioTrackMixer {
    private var micQueue: [CMSampleBuffer] = []

    func handleMic(_ sampleBuffer: CMSampleBuffer) -> [CMSampleBuffer] {
        micQueue.append(sampleBuffer)
        return []
    }

    func handleApp(_ sampleBuffer: CMSampleBuffer) -> [CMSampleBuffer] {
        var outputs: [CMSampleBuffer] = []
        let appRange = Self.timeRange(of: sampleBuffer)

        while let firstMic = micQueue.first {
            let micRange = Self.timeRange(of: firstMic)
            if CMTimeCompare(CMTimeRangeGetEnd(micRange), appRange.start) <= 0 {
                outputs.append(micQueue.removeFirst())
                continue
            }
            if Self.rangesOverlap(micRange, appRange) {
                let mic = micQueue.removeFirst()
                outputs.append(ReplayKitAudioMixer.mix(app: sampleBuffer, mic: mic) ?? sampleBuffer)
                return outputs
            }
            break
        }

        outputs.append(sampleBuffer)
        return outputs
    }

    func drain() -> [CMSampleBuffer] {
        defer { micQueue.removeAll() }
        return micQueue
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

    private static func rangesOverlap(_ lhs: CMTimeRange, _ rhs: CMTimeRange) -> Bool {
        let intersection = CMTimeRangeGetIntersection(lhs, otherRange: rhs)
        return intersection.duration.isValid && intersection.duration > .zero
    }
}

enum ReplayKitAudioMixer {
    /// Mixes ReplayKit app audio with a microphone sample into one PCM buffer.
    /// Returns the app buffer unchanged when mic data is unavailable or formats are incompatible.
    static func mix(app: CMSampleBuffer, mic: CMSampleBuffer?) -> CMSampleBuffer? {
        guard let mic = mic else { return app }
        guard CMSampleBufferDataIsReady(app), CMSampleBufferDataIsReady(mic) else { return app }

        guard let appFormat = CMSampleBufferGetFormatDescription(app),
              let micFormat = CMSampleBufferGetFormatDescription(mic),
              let appAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(appFormat)?.pointee,
              let micAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(micFormat)?.pointee,
              appAsbd.mFormatID == kAudioFormatLinearPCM,
              micAsbd.mFormatID == kAudioFormatLinearPCM,
              (appAsbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0,
              (micAsbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0,
              appAsbd.mBitsPerChannel == 16,
              micAsbd.mBitsPerChannel == 16,
              appAsbd.mSampleRate == micAsbd.mSampleRate else {
            return app
        }

        let appFrames = CMSampleBufferGetNumSamples(app)
        let micFrames = CMSampleBufferGetNumSamples(mic)
        let frames = min(appFrames, micFrames)
        guard frames > 0 else { return app }

        guard let appBlock = CMSampleBufferGetDataBuffer(app),
              let micBlock = CMSampleBufferGetDataBuffer(mic) else {
            return app
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
            return app
        }

        let appChannels = Int(appAsbd.mChannelsPerFrame)
        let micChannels = Int(micAsbd.mChannelsPerFrame)
        let appBytesPerFrame = Int(appAsbd.mBytesPerFrame)
        let micBytesPerFrame = Int(micAsbd.mBytesPerFrame)
        let outputBytes = frames * appBytesPerFrame
        let micBytes = frames * micBytesPerFrame

        var appSamples = [Int16](repeating: 0, count: outputBytes / MemoryLayout<Int16>.size)
        var micSamples = [Int16](repeating: 0, count: micBytes / MemoryLayout<Int16>.size)

        let appCopyStatus = appSamples.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                appBlock,
                atOffset: 0,
                dataLength: outputBytes,
                destination: destination.baseAddress!
            )
        }
        let micCopyStatus = micSamples.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                micBlock,
                atOffset: 0,
                dataLength: micBytes,
                destination: destination.baseAddress!
            )
        }
        guard appCopyStatus == noErr, micCopyStatus == noErr else { return app }

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
            CMBlockBufferReplaceDataBytes(source.baseAddress, outputBlock, 0, outputBytes)
        }
        guard replaceStatus == noErr else { return app }

        return output
    }
}
