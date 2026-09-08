//
//  ScreenRecorder.swift
//  Wyler
//
//  Created by Cesar Vargas on 10.04.20.
//  Copyright © 2020 Cesar Vargas. All rights reserved.
//

import AVFoundation
import Foundation
import Photos
import ReplayKit
import UIKit

public enum ScreenRecorderError: Error {
    case notAvailable
    case photoLibraryAccessNotGranted
    case alreadyRecording
}

public enum VideoContainerFormat {
    case mp4
    case mov

    var fileType: AVFileType {
        switch self {
        case .mp4:
            return .mp4
        case .mov:
            return .mov
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        }
    }

    static func from(_ value: String?) -> VideoContainerFormat {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mov", "video/quicktime", "quicktime":
            return .mov
        default:
            return .mp4
        }
    }
}

public final class ScreenRecorder {
    private var videoOutputURL: URL?
    private var didCreateOutputFile = false
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var micAudioWriterInput: AVAssetWriterInput?
    private var appAudioWriterInput: AVAssetWriterInput?
    private var saveToCameraRoll = false
    private var recordAudio = false
    private var videoFormat: VideoContainerFormat = .mp4
    private var isRecording = false
    let recorder = RPScreenRecorder.shared()

    public func startRecording(to outputURL: URL? = nil,
                               size: CGSize? = nil,
                               saveToCameraRoll: Bool = false,
                               recordAudio: Bool = false,
                               videoFormat: VideoContainerFormat = .mp4,
                               handler: @escaping (Error?) -> Void) {
        guard !isRecording else {
            return handler(ScreenRecorderError.alreadyRecording)
        }
        isRecording = true

        self.saveToCameraRoll = saveToCameraRoll
        self.recordAudio = recordAudio
        self.videoFormat = videoFormat
        resetWriterState()

        recorder.isMicrophoneEnabled = recordAudio

        var attemptOutputURL: URL?
        var attemptDidCreate = false

        do {
            if recordAudio {
                try configureAudioSession()
            }
            try createVideoWriter(in: outputURL)
            attemptOutputURL = self.videoOutputURL
            attemptDidCreate = self.didCreateOutputFile
            addVideoWriterInput(size: size)
            if recordAudio {
                self.micAudioWriterInput = createAndAddAudioInput()
                self.appAudioWriterInput = createAndAddAudioInput()
            }
            startCapture(handler: handler)
        } catch let err {
            isRecording = false
            if let cleanupURL = attemptOutputURL {
                self.deleteOutputFileIfNeeded(outputURL: cleanupURL, didCreate: attemptDidCreate)
            } else if self.didCreateOutputFile, let cleanupURL = self.videoOutputURL {
                self.deleteOutputFileIfNeeded(outputURL: cleanupURL, didCreate: true)
            }
            handler(err)
        }
    }

    private func resetWriterState() {
        videoWriter = nil
        videoWriterInput = nil
        micAudioWriterInput = nil
        appAudioWriterInput = nil
        videoOutputURL = nil
        didCreateOutputFile = false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
    }

    private func createVideoWriter(in outputURL: URL? = nil) throws {
        let newVideoOutputURL: URL

        if let passedVideoOutput = outputURL {
            self.didCreateOutputFile = false
            self.videoOutputURL = passedVideoOutput
            newVideoOutputURL = passedVideoOutput
        } else {
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            let fileName = "WylerNewVideo-\(UUID().uuidString).\(videoFormat.fileExtension)"
            newVideoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent(fileName))
            self.didCreateOutputFile = true
            self.videoOutputURL = newVideoOutputURL
        }

        do {
            try FileManager.default.removeItem(at: newVideoOutputURL)
        } catch {}

        do {
            try videoWriter = AVAssetWriter(outputURL: newVideoOutputURL, fileType: videoFormat.fileType)
        } catch let writerError as NSError {
            videoWriter = nil
            throw writerError
        }
    }

    private func addVideoWriterInput(size: CGSize?) {
        let passingSize: CGSize = size ?? UIScreen.main.bounds.size

        let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                            AVVideoWidthKey: passingSize.width,
                                            AVVideoHeightKey: passingSize.height]

        let newVideoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        self.videoWriterInput = newVideoWriterInput
        newVideoWriterInput.expectsMediaDataInRealTime = true
        videoWriter?.add(newVideoWriterInput)
    }

    private func createAndAddAudioInput() -> AVAssetWriterInput {
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        audioInput.expectsMediaDataInRealTime = true
        videoWriter?.add(audioInput)
        return audioInput
    }

    private func startCapture(handler: @escaping (Error?) -> Void) {
        let outputURL = self.videoOutputURL
        let didCreate = self.didCreateOutputFile

        guard recorder.isAvailable else {
            self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
            self.isRecording = false
            return handler(ScreenRecorderError.notAvailable)
        }
        var sent = false
        recorder.startCapture(handler: { (sampleBuffer, sampleType, passedError) in
            if let passedError = passedError {
                self.videoWriterInput?.markAsFinished()
                self.micAudioWriterInput?.markAsFinished()
                self.appAudioWriterInput?.markAsFinished()
                if self.videoWriter?.status == .writing {
                    self.videoWriter?.cancelWriting()
                }
                self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
                if !sent {
                    self.isRecording = false
                    handler(passedError)
                    sent = true
                }
                return
            }

            switch sampleType {
            case .video:
                self.handleSampleBuffer(sampleBuffer: sampleBuffer)
            case .audioApp:
                if self.recordAudio {
                    self.add(sample: sampleBuffer, to: self.appAudioWriterInput)
                }
            case .audioMic:
                if self.recordAudio {
                    self.add(sample: sampleBuffer, to: self.micAudioWriterInput)
                }
            default:
                break
            }
            if !sent {
                handler(nil)
                sent = true
            }
        })
    }

    private func handleSampleBuffer(sampleBuffer: CMSampleBuffer) {
        if self.videoWriter?.status == AVAssetWriter.Status.unknown {
            self.videoWriter?.startWriting()
            self.videoWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        } else if self.videoWriter?.status == AVAssetWriter.Status.writing &&
                    self.videoWriterInput?.isReadyForMoreMediaData == true {
            self.videoWriterInput?.append(sampleBuffer)
        }
    }

    private func add(sample: CMSampleBuffer, to writerInput: AVAssetWriterInput?) {
        guard let writerInput = writerInput else { return }
        guard self.videoWriter?.status == .writing else { return }
        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sample)
        }
    }

    public func stoprecording(handler: @escaping (Error?) -> Void) {
        recorder.stopCapture(handler: { error in
            let outputURL = self.videoOutputURL
            let didCreate = self.didCreateOutputFile
            let shouldSaveToCameraRoll = self.saveToCameraRoll
            let complete: (Error?) -> Void = { stopError in
                self.isRecording = false
                handler(stopError)
            }

            if let error = error {
                self.videoWriterInput?.markAsFinished()
                self.micAudioWriterInput?.markAsFinished()
                self.appAudioWriterInput?.markAsFinished()
                if self.videoWriter?.status == .writing {
                    self.videoWriter?.cancelWriting()
                }
                self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
                complete(error)
                return
            }

            self.videoWriterInput?.markAsFinished()
            self.micAudioWriterInput?.markAsFinished()
            self.appAudioWriterInput?.markAsFinished()

            guard let writer = self.videoWriter else {
                complete(nil)
                return
            }

            if writer.status == .writing {
                writer.finishWriting {
                    if let finishError = writer.error {
                        self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
                        complete(finishError)
                        return
                    }
                    if shouldSaveToCameraRoll {
                        self.saveVideoToCameraRollAfterAuthorized(outputURL: outputURL,
                                                                    didCreate: didCreate,
                                                                    handler: complete)
                    } else {
                        self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
                        complete(nil)
                    }
                }
            } else if writer.status == .failed {
                self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
                complete(writer.error)
            } else {
                if shouldSaveToCameraRoll {
                    self.saveVideoToCameraRollAfterAuthorized(outputURL: outputURL,
                                                                didCreate: didCreate,
                                                                handler: complete)
                } else {
                    self.deleteOutputFileIfNeeded(outputURL: outputURL, didCreate: didCreate)
                    complete(nil)
                }
            }
        })
    }

    private func canSaveToPhotoLibrary(_ status: PHAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    private func saveVideoToCameraRollAfterAuthorized(outputURL: URL? = nil,
                                                      didCreate: Bool? = nil,
                                                      handler: @escaping (Error?) -> Void) {
        let capturedOutputURL = outputURL ?? self.videoOutputURL
        let capturedDidCreate = didCreate ?? self.didCreateOutputFile
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if canSaveToPhotoLibrary(status) {
            self.saveVideoToCameraRoll(outputURL: capturedOutputURL,
                                       didCreate: capturedDidCreate,
                                       handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: { (status) in
                if self.canSaveToPhotoLibrary(status) {
                    self.saveVideoToCameraRoll(outputURL: capturedOutputURL,
                                               didCreate: capturedDidCreate,
                                               handler: handler)
                } else {
                    self.deleteOutputFileIfNeeded(outputURL: capturedOutputURL, didCreate: capturedDidCreate)
                    handler(ScreenRecorderError.photoLibraryAccessNotGranted)
                }
            })
        }
    }

    private func saveVideoToCameraRoll(outputURL: URL?,
                                       didCreate: Bool,
                                       handler: @escaping (Error?) -> Void) {
        guard let videoOutputURL = outputURL else {
            return handler(nil)
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoOutputURL)
        }, completionHandler: { success, error in
            if let error = error {
                self.deleteOutputFileIfNeeded(outputURL: videoOutputURL, didCreate: didCreate)
                handler(error)
            } else if success {
                self.deleteOutputFileIfNeeded(outputURL: videoOutputURL, didCreate: didCreate)
                handler(nil)
            } else {
                self.deleteOutputFileIfNeeded(outputURL: videoOutputURL, didCreate: didCreate)
                handler(NSError(domain: "ScreenRecorder",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to save video to photo library"]))
            }
        })
    }

    private func deleteOutputFileIfNeeded(outputURL: URL? = nil, didCreate: Bool? = nil) {
        let shouldDelete = didCreate ?? didCreateOutputFile
        guard shouldDelete, let fileURL = outputURL ?? self.videoOutputURL else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            debugPrint("Failed to delete recording file \(fileURL): \(error)")
        }
    }
}
