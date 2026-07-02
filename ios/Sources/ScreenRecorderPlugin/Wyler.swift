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
}

public final class ScreenRecorder {
    private var videoOutputURL: URL?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var micAudioWriterInput: AVAssetWriterInput?
    private var appAudioWriterInput: AVAssetWriterInput?
    private var saveToCameraRoll = false
    private var recordAudio = false
    let recorder = RPScreenRecorder.shared()

    public func startRecording(to outputURL: URL? = nil,
                               size: CGSize? = nil,
                               saveToCameraRoll: Bool = false,
                               recordAudio: Bool = false,
                               handler: @escaping (Error?) -> Void) {
        self.saveToCameraRoll = saveToCameraRoll
        self.recordAudio = recordAudio
        resetWriterState()

        recorder.isMicrophoneEnabled = recordAudio

        do {
            if recordAudio {
                try configureAudioSession()
            }
            try createVideoWriter(in: outputURL)
            addVideoWriterInput(size: size)
            if recordAudio {
                self.micAudioWriterInput = createAndAddAudioInput()
                self.appAudioWriterInput = createAndAddAudioInput()
            }
            startCapture(handler: handler)
        } catch let err {
            handler(err)
        }
    }

    private func resetWriterState() {
        videoWriter = nil
        videoWriterInput = nil
        micAudioWriterInput = nil
        appAudioWriterInput = nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
    }

    private func createVideoWriter(in outputURL: URL? = nil) throws {
        let newVideoOutputURL: URL

        if let passedVideoOutput = outputURL {
            self.videoOutputURL = passedVideoOutput
            newVideoOutputURL = passedVideoOutput
        } else {
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            newVideoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent("WylerNewVideo.mp4"))
            self.videoOutputURL = newVideoOutputURL
        }

        do {
            try FileManager.default.removeItem(at: newVideoOutputURL)
        } catch {}

        do {
            try videoWriter = AVAssetWriter(outputURL: newVideoOutputURL, fileType: AVFileType.mp4)
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
        guard recorder.isAvailable else {
            return handler(ScreenRecorderError.notAvailable)
        }
        var sent = false
        recorder.startCapture(handler: { (sampleBuffer, sampleType, passedError) in
            if let passedError = passedError {
                if !sent {
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
            if let error = error {
                handler(error)
                return
            }

            self.videoWriterInput?.markAsFinished()
            self.micAudioWriterInput?.markAsFinished()
            self.appAudioWriterInput?.markAsFinished()

            guard let writer = self.videoWriter else {
                handler(nil)
                return
            }

            if writer.status == .writing {
                writer.finishWriting {
                    if let finishError = writer.error {
                        handler(finishError)
                        return
                    }
                    if self.saveToCameraRoll {
                        self.saveVideoToCameraRollAfterAuthorized(handler: handler)
                    } else {
                        handler(nil)
                    }
                }
            } else if writer.status == .failed {
                handler(writer.error)
            } else {
                if self.saveToCameraRoll {
                    self.saveVideoToCameraRollAfterAuthorized(handler: handler)
                } else {
                    handler(nil)
                }
            }
        })
    }

    private func saveVideoToCameraRollAfterAuthorized(handler: @escaping (Error?) -> Void) {
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            self.saveVideoToCameraRoll(handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization({ (status) in
                if status == .authorized {
                    self.saveVideoToCameraRoll(handler: handler)
                } else {
                    handler(ScreenRecorderError.photoLibraryAccessNotGranted)
                }
            })
        }
    }

    private func saveVideoToCameraRoll(handler: @escaping (Error?) -> Void) {
        guard let videoOutputURL = self.videoOutputURL else {
            return handler(nil)
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoOutputURL)
        }, completionHandler: { _, error in
            if let error = error {
                handler(error)
            } else {
                handler(nil)
            }
        })
    }
}
