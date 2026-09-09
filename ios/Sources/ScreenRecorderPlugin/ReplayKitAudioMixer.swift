import AVFoundation
import CoreMedia
import os

private struct QueuedMic {
    let buffer: CMSampleBuffer
    var consumedFrames: Int
}

final class ReplayKitAudioTrackMixer {
    private var micQueue: [QueuedMic] = []
    private var pendingAppQueue: [CMSampleBuffer] = []
    private var referenceAppBuffer: CMSampleBuffer?
    private let maxMicQueueSize = 128
    private let maxPendingAppQueueSize = 128

    // Satisfies SwiftLint required_deinit without custom teardown logic.
    deinit {
        // No teardown required; this deinit exists only for SwiftLint compliance.
    }

    func handleMic(_ sampleBuffer: CMSampleBuffer) -> [CMSampleBuffer] {
        micQueue.append(QueuedMic(buffer: sampleBuffer, consumedFrames: 0))
        var outputs: [CMSampleBuffer] = []
        while micQueue.count > maxMicQueueSize {
            let queuedMic = micQueue.removeFirst()
            if let normalized = Self.micTailForWriter(queuedMic, reference: referenceAppBuffer) {
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
        var outputs: [CMSampleBuffer] = []
        while pendingAppQueue.count > maxPendingAppQueueSize {
            _ = pendingAppQueue.removeFirst()
        }
        outputs.append(contentsOf: emitReadySamples())
        return outputs
    }

    func drain() -> [CMSampleBuffer] {
        var outputs: [CMSampleBuffer] = []
        while !micQueue.isEmpty || !pendingAppQueue.isEmpty {
            let remainingCount = micQueue.count + pendingAppQueue.count
            outputs.append(contentsOf: emitReadySamples())
            if micQueue.count + pendingAppQueue.count == remainingCount {
                break
            }
        }

        var remaining: [(CMTime, CMSampleBuffer)] = []
        for queuedMic in micQueue {
            if let normalized = Self.micTailForWriter(queuedMic, reference: referenceAppBuffer) {
                remaining.append((Self.startTime(of: normalized), normalized))
            }
        }
        for app in pendingAppQueue {
            remaining.append((Self.startTime(of: app), app))
        }
        remaining.sort { CMTimeCompare($0.0, $1.0) < 0 }
        outputs.append(contentsOf: remaining.map(\.1))

        micQueue.removeAll()
        pendingAppQueue.removeAll()
        return outputs
    }

    private func emitReadySamples() -> [CMSampleBuffer] {
        var outputs: [CMSampleBuffer] = []

        while let queuedMic = micQueue.first {
            let nextAppStart = pendingAppQueue.first.map { Self.startTime(of: $0) }
            guard let appStart = nextAppStart else { break }
            if CMTimeCompare(Self.endTime(of: queuedMic.buffer, consumedFrames: queuedMic.consumedFrames), appStart) <= 0 {
                micQueue.removeFirst()
                if let normalized = Self.micTailForWriter(queuedMic, reference: referenceAppBuffer) {
                    outputs.append(normalized)
                }
            } else {
                break
            }
        }

        while let app = pendingAppQueue.first,
              let queuedMic = micQueue.first,
              Self.rangesOverlap(queuedMic, app) {
            if let leadingMic = Self.flushLeadingMicOnly(queuedMic: &micQueue[0], app: app, reference: referenceAppBuffer) {
                outputs.append(leadingMic)
                continue
            }
            if let result = ReplayKitAudioMixer.mix(
                app: app,
                mic: queuedMic.buffer,
                micFrameOffset: queuedMic.consumedFrames
            ) {
                pendingAppQueue.removeFirst()
                outputs.append(result.sample)
                if result.micFramesConsumed >= CMSampleBufferGetNumSamples(queuedMic.buffer) {
                    micQueue.removeFirst()
                } else {
                    micQueue[0].consumedFrames = result.micFramesConsumed
                }
            } else {
                pendingAppQueue.removeFirst()
                var fallbackSamples: [(CMTime, CMSampleBuffer)] = [
                    (Self.startTime(of: app), app)
                ]
                if let micOverlap = Self.micOverlapSlice(
                    queuedMic: micQueue[0],
                    app: app,
                    reference: referenceAppBuffer
                ) {
                    fallbackSamples.append((Self.startTime(of: micOverlap), micOverlap))
                }
                fallbackSamples.sort { CMTimeCompare($0.0, $1.0) < 0 }
                outputs.append(contentsOf: fallbackSamples.map(\.1))
                Self.advanceMicPastOverlap(queuedMic: &micQueue[0], app: app)
                if micQueue[0].consumedFrames >= CMSampleBufferGetNumSamples(micQueue[0].buffer) {
                    micQueue.removeFirst()
                }
            }
        }

        while let app = pendingAppQueue.first {
            if let queuedMic = micQueue.first {
                if CMTimeCompare(Self.startTime(of: queuedMic.buffer, consumedFrames: queuedMic.consumedFrames),
                                Self.endTime(of: app)) > 0 {
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

    private static func startTime(of buffer: CMSampleBuffer, consumedFrames: Int = 0) -> CMTime {
        guard consumedFrames > 0 else {
            return CMSampleBufferGetPresentationTimeStamp(buffer)
        }
        let sampleRate = sampleRate(of: buffer)
        let consumedDuration = CMTime(value: CMTimeValue(consumedFrames), timescale: CMTimeScale(sampleRate))
        return CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(buffer), consumedDuration)
    }

    private static func endTime(of buffer: CMSampleBuffer, consumedFrames: Int = 0) -> CMTime {
        CMTimeRangeGetEnd(timeRange(of: buffer, consumedFrames: consumedFrames))
    }

    private static func sampleRate(of buffer: CMSampleBuffer) -> Double {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            return 48_000
        }
        return asbd.mSampleRate
    }

    private static func timeRange(of buffer: CMSampleBuffer, consumedFrames: Int = 0) -> CMTimeRange {
        let start = startTime(of: buffer, consumedFrames: consumedFrames)
        let totalFrames = CMSampleBufferGetNumSamples(buffer)
        let remainingFrames = max(0, totalFrames - consumedFrames)
        let timescale = CMTimeScale(sampleRate(of: buffer))
        return CMTimeRange(start: start, duration: CMTime(value: CMTimeValue(remainingFrames), timescale: timescale))
    }

    private static func rangesOverlap(_ queuedMic: QueuedMic, _ app: CMSampleBuffer) -> Bool {
        let intersection = CMTimeRangeGetIntersection(
            timeRange(of: queuedMic.buffer, consumedFrames: queuedMic.consumedFrames),
            otherRange: timeRange(of: app)
        )
        return intersection.duration.isValid && intersection.duration > .zero
    }

    private static func flushLeadingMicOnly(
        queuedMic: inout QueuedMic,
        app: CMSampleBuffer,
        reference: CMSampleBuffer?
    ) -> CMSampleBuffer? {
        let micRange = timeRange(of: queuedMic.buffer, consumedFrames: queuedMic.consumedFrames)
        let intersection = CMTimeRangeGetIntersection(micRange, otherRange: timeRange(of: app))
        guard intersection.duration.isValid, intersection.duration > .zero else { return nil }
        guard CMTimeCompare(micRange.start, intersection.start) < 0 else { return nil }

        let sampleRate = sampleRate(of: queuedMic.buffer)
        let bufferStart = CMSampleBufferGetPresentationTimeStamp(queuedMic.buffer)
        let leadingEndFrame = frameOffset(
            for: intersection.start,
            relativeTo: bufferStart,
            sampleRate: sampleRate
        )
        let leadingFrameCount = leadingEndFrame - queuedMic.consumedFrames
        guard leadingFrameCount > 0 else { return nil }

        guard let leadingSlice = ReplayKitAudioMixer.slice(
            queuedMic.buffer,
            fromFrame: queuedMic.consumedFrames,
            frameCount: leadingFrameCount
        ) else {
            return nil
        }

        queuedMic.consumedFrames = leadingEndFrame
        return normalizeForWriter(leadingSlice, reference: reference)
    }

    private static func frameOffset(for time: CMTime, relativeTo start: CMTime, sampleRate: Double) -> Int {
        let delta = CMTimeSubtract(time, start)
        return max(0, Int((CMTimeGetSeconds(delta) * sampleRate).rounded()))
    }

    private static func advanceMicPastOverlap(queuedMic: inout QueuedMic, app: CMSampleBuffer) {
        let intersection = CMTimeRangeGetIntersection(
            timeRange(of: queuedMic.buffer, consumedFrames: queuedMic.consumedFrames),
            otherRange: timeRange(of: app)
        )
        guard intersection.duration.isValid, intersection.duration > .zero else { return }

        let sampleRate = sampleRate(of: queuedMic.buffer)
        let bufferStart = CMSampleBufferGetPresentationTimeStamp(queuedMic.buffer)
        let endFrame = frameOffset(
            for: CMTimeRangeGetEnd(intersection),
            relativeTo: bufferStart,
            sampleRate: sampleRate
        )
        queuedMic.consumedFrames = max(queuedMic.consumedFrames, endFrame)
    }

    private static func micOverlapSlice(
        queuedMic: QueuedMic,
        app: CMSampleBuffer,
        reference: CMSampleBuffer?
    ) -> CMSampleBuffer? {
        let intersection = CMTimeRangeGetIntersection(
            timeRange(of: queuedMic.buffer, consumedFrames: queuedMic.consumedFrames),
            otherRange: timeRange(of: app)
        )
        guard intersection.duration.isValid, intersection.duration > .zero else { return nil }

        let sampleRate = sampleRate(of: queuedMic.buffer)
        let bufferStart = CMSampleBufferGetPresentationTimeStamp(queuedMic.buffer)
        let startFrame = max(
            queuedMic.consumedFrames,
            frameOffset(for: intersection.start, relativeTo: bufferStart, sampleRate: sampleRate)
        )
        let endFrame = frameOffset(
            for: CMTimeRangeGetEnd(intersection),
            relativeTo: bufferStart,
            sampleRate: sampleRate
        )
        let frameCount = endFrame - startFrame
        guard frameCount > 0 else { return nil }

        guard let overlap = ReplayKitAudioMixer.slice(
            queuedMic.buffer,
            fromFrame: startFrame,
            frameCount: frameCount
        ) else {
            return nil
        }
        return normalizeForWriter(overlap, reference: reference)
    }

    private static func micTailForWriter(_ queuedMic: QueuedMic, reference: CMSampleBuffer?) -> CMSampleBuffer? {
        guard let tail = ReplayKitAudioMixer.slice(queuedMic.buffer, fromFrame: queuedMic.consumedFrames) else {
            return nil
        }
        return normalizeForWriter(tail, reference: reference)
    }

    private static func normalizeForWriter(_ buffer: CMSampleBuffer, reference: CMSampleBuffer?) -> CMSampleBuffer? {
        guard let reference = reference else { return buffer }
        return ReplayKitAudioMixer.matchFormat(buffer, to: reference) ?? buffer
    }
}

enum ReplayKitAudioMixer {
    private static let logger = Logger(subsystem: "CapgoScreenRecorder", category: "ReplayKitAudioMixer")

    struct MixResult {
        let sample: CMSampleBuffer
        let micFramesConsumed: Int
    }

    static func mix(app: CMSampleBuffer, mic: CMSampleBuffer, micFrameOffset: Int = 0) -> MixResult? {
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
              micAsbd.mBitsPerChannel == 16 else {
            return nil
        }

        var micBuffer = mic
        var effectiveMicOffset = micFrameOffset
        if micAsbd.mSampleRate != appAsbd.mSampleRate {
            guard let resampled = resampleMicBuffer(mic, toAppSampleRate: appAsbd.mSampleRate) else {
                logger.error("Failed to resample microphone audio from \(micAsbd.mSampleRate) Hz to \(appAsbd.mSampleRate) Hz")
                return nil
            }
            micBuffer = resampled
            effectiveMicOffset = Int(
                (Double(micFrameOffset) * appAsbd.mSampleRate / micAsbd.mSampleRate).rounded()
            )
        }

        guard let micFormat = CMSampleBufferGetFormatDescription(micBuffer),
              let resampledMicAsbd = CMAudioFormatDescriptionGetStreamBasicDescription(micFormat)?.pointee else {
            return nil
        }

        let appRange = timeRange(of: app)
        let micRange = timeRange(of: micBuffer)
        let intersection = CMTimeRangeGetIntersection(appRange, otherRange: micRange)
        guard intersection.duration.isValid, intersection.duration > .zero else { return nil }

        let sampleRate = appAsbd.mSampleRate
        let micStartFrame = max(
            effectiveMicOffset,
            frameOffset(for: intersection.start, relativeTo: micRange.start, sampleRate: sampleRate)
        )
        let appStartFrame = frameOffset(for: intersection.start, relativeTo: appRange.start, sampleRate: sampleRate)
        let mixFrames = frameCount(for: intersection.duration, sampleRate: sampleRate)
        guard mixFrames > 0 else { return nil }

        let appFrames = CMSampleBufferGetNumSamples(app)
        let micFrames = CMSampleBufferGetNumSamples(micBuffer)
        let appAvailable = appFrames - appStartFrame
        let micAvailable = micFrames - micStartFrame
        let frames = min(mixFrames, appAvailable, micAvailable)
        guard frames > 0 else { return nil }

        guard let appBlock = CMSampleBufferGetDataBuffer(app),
              let micBlock = CMSampleBufferGetDataBuffer(micBuffer) else {
            return nil
        }

        guard let output = copyPCMBuffer(app),
              let outputBlock = CMSampleBufferGetDataBuffer(output) else {
            return nil
        }

        let appChannels = Int(appAsbd.mChannelsPerFrame)
        let micChannels = Int(resampledMicAsbd.mChannelsPerFrame)
        let appBytesPerFrame = Int(appAsbd.mBytesPerFrame)
        let micBytesPerFrame = Int(resampledMicAsbd.mBytesPerFrame)
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
            var micAccumulator: Int32 = 0
            for micChannel in 0..<micChannels {
                micAccumulator += Int32(micSamples[frame * micChannels + micChannel])
            }
            let micSample = micAccumulator / Int32(micChannels)
            for channel in 0..<appChannels {
                let index = frame * appChannels + channel
                let mixed = max(Int32(Int16.min), min(Int32(Int16.max), Int32(appSamples[index]) + micSample))
                appSamples[index] = Int16(mixed)
            }
        }

        let replaceStatus = appSamples.withUnsafeMutableBytes { source in
            CMBlockBufferReplaceDataBytes(
                with: source.baseAddress!,
                blockBuffer: outputBlock,
                offsetIntoDestination: appByteOffset,
                dataLength: outputBytes
            )
        }
        guard replaceStatus == noErr else {
            logger.error("Failed to write mixed PCM into output block buffer")
            return nil
        }

        let intersectionEnd = CMTimeRangeGetEnd(intersection)
        let originalMicStart = CMSampleBufferGetPresentationTimeStamp(mic)
        let consumedInOriginalMic = max(
            micFrameOffset,
            frameOffset(for: intersectionEnd, relativeTo: originalMicStart, sampleRate: micAsbd.mSampleRate)
        )
        return MixResult(sample: output, micFramesConsumed: consumedInOriginalMic)
    }

    private static func resampleMicBuffer(_ mic: CMSampleBuffer, toAppSampleRate targetRate: Double) -> CMSampleBuffer? {
        guard CMSampleBufferDataIsReady(mic),
              let formatDesc = CMSampleBufferGetFormatDescription(mic),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              asbd.mBitsPerChannel == 16,
              asbd.mSampleRate != targetRate,
              let block = CMSampleBufferGetDataBuffer(mic) else {
            return nil
        }

        let channels = AVAudioChannelCount(asbd.mChannelsPerFrame)
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: asbd.mSampleRate,
            channels: channels,
            interleaved: true
        ), let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetRate,
            channels: channels,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }

        let inputFrames = CMSampleBufferGetNumSamples(mic)
        let inputBytes = inputFrames * Int(asbd.mBytesPerFrame)
        var rawBytes = [UInt8](repeating: 0, count: inputBytes)
        let copyStatus = rawBytes.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                block,
                atOffset: 0,
                dataLength: inputBytes,
                destination: destination.baseAddress!
            )
        }
        guard copyStatus == noErr else { return nil }

        guard let inputPCM = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(inputFrames)),
              let inputChannelData = inputPCM.int16ChannelData else {
            return nil
        }
        inputPCM.frameLength = AVAudioFrameCount(inputFrames)
        rawBytes.withUnsafeBytes { source in
            let samples = source.bindMemory(to: Int16.self)
            for index in 0..<inputFrames {
                for channel in 0..<Int(channels) {
                    inputChannelData[0][index * Int(channels) + channel] = samples[index * Int(channels) + channel]
                }
            }
        }

        let outputFrameCapacity = AVAudioFrameCount(
            (Double(inputFrames) * targetRate / asbd.mSampleRate).rounded(.up)
        )
        guard let outputPCM = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity),
              let outputChannelData = outputPCM.int16ChannelData else {
            return nil
        }

        var conversionError: NSError?
        var suppliedInput = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return inputPCM
        }
        converter.convert(to: outputPCM, error: &conversionError, withInputFrom: inputBlock)
        guard conversionError == nil, outputPCM.frameLength > 0 else { return nil }

        let outputFrames = Int(outputPCM.frameLength)
        let outputBytesPerFrame = Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
        let outputBytes = outputFrames * outputBytesPerFrame
        var outputBytesArray = [UInt8](repeating: 0, count: outputBytes)
        outputBytesArray.withUnsafeMutableBytes { destination in
            let samples = destination.bindMemory(to: Int16.self)
            for index in 0..<outputFrames {
                for channel in 0..<Int(channels) {
                    samples[index * Int(channels) + channel] = outputChannelData[0][index * Int(channels) + channel]
                }
            }
        }

        var outputBlockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: outputBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: outputBytes,
            flags: 0,
            blockBufferOut: &outputBlockBuffer
        )
        guard blockStatus == noErr, let outputBlock = outputBlockBuffer else { return nil }

        let replaceStatus = outputBytesArray.withUnsafeMutableBytes { source in
            CMBlockBufferReplaceDataBytes(
                with: source.baseAddress!,
                blockBuffer: outputBlock,
                offsetIntoDestination: 0,
                dataLength: outputBytes
            )
        }
        guard replaceStatus == noErr else { return nil }

        var outputAsbd = asbd
        outputAsbd.mSampleRate = targetRate
        var outputFormatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &outputAsbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &outputFormatDescription
        )
        guard formatStatus == noErr, let resampledFormat = outputFormatDescription else { return nil }

        let timescale = CMTimeScale(targetRate)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(mic),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(mic)
        )
        var outputBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: outputBlock,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: resampledFormat,
            sampleCount: outputFrames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outputBuffer
        )
        guard createStatus == noErr else { return nil }
        return outputBuffer
    }

    static func slice(_ buffer: CMSampleBuffer, fromFrame frameOffset: Int, frameCount: Int? = nil) -> CMSampleBuffer? {
        guard CMSampleBufferDataIsReady(buffer) else { return nil }

        let totalFrames = CMSampleBufferGetNumSamples(buffer)
        guard frameOffset < totalFrames else { return nil }
        if frameOffset <= 0, frameCount == nil {
            return buffer
        }

        let framesToCopy = min(frameCount ?? (totalFrames - frameOffset), totalFrames - frameOffset)
        guard framesToCopy > 0 else { return nil }

        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              let sourceBlock = CMSampleBufferGetDataBuffer(buffer) else {
            return nil
        }

        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        let byteOffset = frameOffset * bytesPerFrame
        let remainingBytes = framesToCopy * bytesPerFrame
        let timescale = CMTimeScale(asbd.mSampleRate)

        var tailBytes = [UInt8](repeating: 0, count: remainingBytes)
        let copyStatus = tailBytes.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                sourceBlock,
                atOffset: byteOffset,
                dataLength: remainingBytes,
                destination: destination.baseAddress!
            )
        }
        guard copyStatus == noErr else { return nil }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: remainingBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: remainingBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let outputBlock = blockBuffer else { return nil }

        let replaceStatus = tailBytes.withUnsafeMutableBytes { source in
            CMBlockBufferReplaceDataBytes(
                with: source.baseAddress!,
                blockBuffer: outputBlock,
                offsetIntoDestination: 0,
                dataLength: remainingBytes
            )
        }
        guard replaceStatus == noErr else { return nil }

        let presentationTimeStamp = CMTimeAdd(
            CMSampleBufferGetPresentationTimeStamp(buffer),
            CMTime(value: CMTimeValue(frameOffset), timescale: timescale)
        )
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(buffer)
        )
        var outputBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: outputBlock,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: framesToCopy,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outputBuffer
        )
        guard createStatus == noErr else { return nil }
        return outputBuffer
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
            CMBlockBufferReplaceDataBytes(
                with: source.baseAddress!,
                blockBuffer: outputBlock,
                offsetIntoDestination: 0,
                dataLength: outputBytes
            )
        }
        guard replaceStatus == noErr else { return nil }

        let referenceTimescale = CMTimeScale(referenceAsbd.mSampleRate)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: referenceTimescale),
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

    private static func copyPCMBuffer(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard CMSampleBufferDataIsReady(buffer) else { return nil }
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
              let sourceBlock = CMSampleBufferGetDataBuffer(buffer) else {
            return nil
        }

        let frames = CMSampleBufferGetNumSamples(buffer)
        let totalBytes = frames * Int(asbd.mBytesPerFrame)
        guard totalBytes > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: totalBytes)
        let copyStatus = bytes.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                sourceBlock,
                atOffset: 0,
                dataLength: totalBytes,
                destination: destination.baseAddress!
            )
        }
        guard copyStatus == noErr else { return nil }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: totalBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let outputBlock = blockBuffer else { return nil }

        let replaceStatus = bytes.withUnsafeMutableBytes { source in
            CMBlockBufferReplaceDataBytes(
                with: source.baseAddress!,
                blockBuffer: outputBlock,
                offsetIntoDestination: 0,
                dataLength: totalBytes
            )
        }
        guard replaceStatus == noErr else { return nil }

        let timescale = CMTimeScale(asbd.mSampleRate)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
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
            formatDescription: format,
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
