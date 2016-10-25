//
//  Extensions.swift
//  @cleexiang
//
//  Created by clee on 16/9/30.
//  Copyright © 2016年 PG. All rights reserved.
//

import Foundation
import AVFoundation
import Photos
import UIKit

public enum CLError: Error {
    public enum FileResourceFailureReason {
        
    }
}

extension NSError {
    static func error(domain: String, code: Int, description: String) -> NSError {
        return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey : description])
    }
}

extension AVAsset {
    func reverseVideo(_ outputURL: URL) -> AVAsset? {
        let track = self.tracks(withMediaType: AVMediaTypeVideo)[0]
        var assetReader: AVAssetReader
        do {
            assetReader = try AVAssetReader(asset: self)
        } catch {
            print(error)
            return nil
        }
        let setting = [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32)]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: setting)
        assetReader.add(output)

        var sampleBuffers = [CMSampleBuffer]()
        assetReader.startReading()
        while true {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                break
            }
            sampleBuffers.append(sampleBuffer)
        }

        var assetWriter: AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: AVFileTypeMPEG4)
        } catch {
            print(error)
            return nil
        }

        let videoCompressionProps = [AVVideoAverageBitRateKey : track.estimatedDataRate]
        let settings = [AVVideoCodecKey: AVVideoCodecH264,
                        AVVideoWidthKey: track.naturalSize.width,
                        AVVideoHeightKey: track.naturalSize.height,
                        AVVideoCompressionPropertiesKey: videoCompressionProps] as [String : Any]
        let writerInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: settings)
        writerInput.transform = track.preferredTransform
        assetWriter.add(writerInput)
        let pixelBufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffers[0]))
        for i in 0..<sampleBuffers.count {
            while writerInput.isReadyForMoreMediaData == false {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffers[i])
            let imageBufferRef = CMSampleBufferGetImageBuffer(sampleBuffers[sampleBuffers.count - i - 1])
            let srcPtr = Unmanaged.passUnretained(imageBufferRef!).toOpaque()
            let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(srcPtr).takeUnretainedValue()
            pixelBufferAdapter.append(pixelBuffer, withPresentationTime: presentationTime)

        }
        assetWriter.finishWriting {
            print("写入完毕")
        }

        let reverseAsset = AVAsset(url: outputURL)
        return reverseAsset
    }

    class func merge(_ videos: [URL], finish: @escaping (URL?, NSError?) -> Swift.Void) throws {
        let mixComposition = AVMutableComposition()
        let mixCompositionTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)

        var hasPortraitAsset = false
        var hasLandscapeAsset = false

        var instructions = Array<AVMutableVideoCompositionInstruction>()

        var startTime = kCMTimeZero
        var lastCMTime = kCMTimeZero

        var maxWidth = CGFloat(0)
        var maxHeight = CGFloat(0)
        for assetURL in videos {
            let asset = AVAsset(url: assetURL)
            print("asset duration: \(asset.duration)")
            let track = asset.tracks(withMediaType: AVMediaTypeVideo)[0]
            let timeRange = CMTimeRangeMake(kCMTimeZero, track.timeRange.duration)
            try mixCompositionTrack.insertTimeRange(timeRange, of: track, at: lastCMTime)

            let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
            videoCompositionInstruction.timeRange = CMTimeRangeMake(lastCMTime, CMTimeAdd(lastCMTime, track.timeRange.duration))

            let videoCompositionLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: mixCompositionTrack)
            videoCompositionLayerInstruction.setTransform(track.preferredTransform, at: lastCMTime)
            videoCompositionInstruction.layerInstructions = [videoCompositionLayerInstruction]
            instructions.append(videoCompositionInstruction)

            var naturalSize = track.naturalSize
            if track.isPortrait() {
                naturalSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            }

            if naturalSize.width > maxWidth {
                maxWidth = naturalSize.width
            }

            if naturalSize.height > maxHeight {
                maxHeight = naturalSize.height
            }

            lastCMTime = track.timeRange.duration
            startTime = CMTimeAdd(startTime, track.timeRange.duration)

            if track.isPortrait() {
                hasPortraitAsset = true
            } else {
                hasLandscapeAsset = true
            }
        }

        if hasPortraitAsset && hasLandscapeAsset {
            let error = NSError.error(domain: "", code:0 , description: "不能同时合成横屏和竖屏的视频")
            finish(nil, error)
        }

        let mutableVideoComposition = AVMutableVideoComposition()
        mutableVideoComposition.instructions = instructions
        mutableVideoComposition.renderSize = CGSize(width: maxWidth, height: maxHeight)
        mutableVideoComposition.frameDuration = CMTimeMake(1, 30)

        print("merge video duration: \(mixComposition.duration)")

        let mergeFileUrl = URL(fileURLWithPath: NSTemporaryDirectory() + ProcessInfo.processInfo.globallyUniqueString + ".mov")
        guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
            let error = NSError.error(domain: "", code: 0, description: "合成视频失败")
            finish(nil, error)
            return
        }
        exporter.outputURL = mergeFileUrl
        exporter.outputFileType = AVFileTypeMPEG4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = mutableVideoComposition

        exporter.exportAsynchronously {
            DispatchQueue.main.async(execute: {
                switch exporter.status {
                case .completed:
                    finish(mergeFileUrl, nil)
                case .unknown, .failed:
                    finish(nil, exporter.error as NSError?)
                default:
                    let error = NSError.error(domain: "", code: 0, description: "合成视频失败")
                    finish(nil, error)
                }
            })
        }
    }

    func scaleTime(_ outputURL: URL, factor: Float64, finish: @escaping (URL?, NSError?) -> Swift.Void) {
        let mixComposition = AVMutableComposition()
        let mixCompositionTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
        let assetTrack = self.tracks(withMediaType: AVMediaTypeVideo)[0]

        do {
            let timeRange = CMTimeRangeMake(kCMTimeZero, assetTrack.timeRange.duration)
            try mixCompositionTrack.insertTimeRange(timeRange, of: assetTrack, at: kCMTimeZero)
        } catch {
            print("insert failed \(error)")
        }
        let scaledDuration = CMTimeMultiplyByFloat64(assetTrack.timeRange.duration, 1.0/factor)
        mixCompositionTrack.scaleTimeRange(assetTrack.timeRange, toDuration: scaledDuration)

        let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
        videoCompositionInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, mixCompositionTrack.timeRange.duration)
        let videoCompositionLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetTrack)
        videoCompositionLayerInstruction.setTransform(assetTrack.preferredTransform, at: kCMTimeZero)
        videoCompositionInstruction.layerInstructions = [videoCompositionLayerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [videoCompositionInstruction]
        videoComposition.frameDuration = CMTimeMake(1, 30)
        if assetTrack.isPortrait() {
            videoComposition.renderSize = CGSize(width: assetTrack.naturalSize.height, height: assetTrack.naturalSize.width)
        } else {
            videoComposition.renderSize = assetTrack.naturalSize
        }

        guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
            let error = NSError.error(domain: "", code: 0, description: "合成视频失败")
            finish(nil, error)
            return
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = AVFileTypeMPEG4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition

        exporter.exportAsynchronously {
            DispatchQueue.main.async(execute: {
                switch exporter.status {
                case .completed:
                    finish(outputURL, nil)
                case .unknown, .failed:
                    finish(nil, exporter.error as NSError?)
                default:
                    let error = NSError.error(domain: "", code: 0, description: "合成视频失败")
                    finish(nil, error)
                }
            })
        }
    }

    func divide(from parts: Int64) {

        let track = self.tracks(withMediaType: AVMediaTypeVideo)[0]

        let firstSegmentStart = CMTimeMake(1, self.duration.timescale)
        let firstSegmentStartDuration = CMTimeMakeWithSeconds(Float64(parts), self.duration.timescale)
        let firstSegmentTime = CMTimeRangeMake(firstSegmentStart, firstSegmentStartDuration)
        var outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + ".mov")
        _ = self.exportSegment(track, timePart: firstSegmentTime, outputURL: outputURL, finish: nil)

        let secondSegmentStart = CMTimeAdd(kCMTimeZero, firstSegmentStartDuration)
        let secondSegmentStartDuration = CMTimeMakeWithSeconds((CMTimeGetSeconds(self.duration)) - Float64(parts), self.duration.timescale)
        let secondSegmentTime = CMTimeRangeMake(secondSegmentStart, secondSegmentStartDuration)
        outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + ".mov")
        _ = self.exportSegment(track, timePart: secondSegmentTime, outputURL: outputURL, finish: nil)
    }

    private func exportSegment(_ track: AVAssetTrack, timePart: CMTimeRange, outputURL: URL, finish: (()->())? ) {
        let mixComposition = AVMutableComposition()
        let mixCompositionTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
        do {
            try mixCompositionTrack.insertTimeRange(timePart, of: track, at: kCMTimeZero)
        } catch {
            print("error")
        }

        let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
        videoCompositionInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, mixCompositionTrack.timeRange.duration)
        let videoCompositionLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: mixCompositionTrack)
        videoCompositionLayerInstruction.setTransform(track.preferredTransform, at: kCMTimeZero)
        videoCompositionInstruction.layerInstructions = [videoCompositionLayerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [videoCompositionInstruction]
        videoComposition.frameDuration = CMTimeMake(1, 30)
        if track.isPortrait() {
            videoComposition.renderSize = CGSize(width: track.naturalSize.height, height: track.naturalSize.width)
        } else {
            videoComposition.renderSize = track.naturalSize
        }

        guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
            print("合成视频失败")
            return
        }

        exporter.outputURL = outputURL as URL
        exporter.outputFileType = AVFileTypeMPEG4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition
        exporter.exportAsynchronously {
            if let finish = finish {
                finish()
            }
        }
    }

    func clip(startTime: Double, endTime: Double, outputURL: URL, finish:@escaping ()-> ()) {
        DispatchQueue.global().async {
            let track = self.tracks(withMediaType: AVMediaTypeVideo)[0]
            let start = CMTimeMakeWithSeconds(startTime, self.duration.timescale)
            let duration = CMTimeAdd(start, CMTimeMakeWithSeconds(endTime-startTime, self.duration.timescale))
            let timeRange = CMTimeRangeMake(start, duration)
            self.exportSegment(track, timePart: timeRange, outputURL: outputURL) {
                DispatchQueue.main.async {
                    finish()
                }
            }
        }
    }
}

extension AVAssetTrack {
    func isPortrait() -> Bool {
        let transform = self.preferredTransform
        if transform.a == 0 && transform.d == 0 && (transform.b == 1.0 || transform.b == -1.0) && (transform.c == 1.0 || transform.c == -1.0) {
            return true
        } else {
            return false
        }
    }
}
