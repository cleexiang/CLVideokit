//
//  CameraSession.swift
//  @cleexiang
//
//  Created by clee on 16/9/9.
//  Copyright © 2016年 M. All rights reserved.
//
import AVFoundation

public enum CLCameraSetupResult: Int {
    case success
    case notAuthorized
    case configurationFailed
}

public extension AVCaptureDevice {
    class func device(_ mediaType: String, position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        let devices: [AVCaptureDevice]?
        if #available(iOS 10.0, *) {
            let allCameraDevices = [AVCaptureDeviceType.builtInWideAngleCamera, AVCaptureDeviceType.builtInDuoCamera]
            let discoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: allCameraDevices, mediaType: AVMediaTypeVideo, position: position)
            devices = discoverySession?.devices
        } else {
            devices = AVCaptureDevice.devices(withMediaType: mediaType) as! [AVCaptureDevice]?
        }
        guard let availableDevices = devices else {
            return nil
        }

        guard var availableDevice = availableDevices.first else {
            return nil
        }
        for device in devices! {
            if device.position == position {
                availableDevice = device
            }
        }

        return availableDevice
    }
}

protocol CLCaptureStillImageable {
    func startCapture()
}

protocol CLRecordingVideoable {
    func startRecording(_ outputFile: URL, delegate: AVCaptureFileOutputRecordingDelegate)
    func stopRecording()
}

public class CLCaptureDevice: NSObject {
    let session = AVCaptureSession()
    var deviceInput: AVCaptureDeviceInput?
    var sessionQueue: DispatchQueue!
    fileprivate var sessionSetupResult = CLCameraSetupResult.success
    fileprivate var positionValue = AVCaptureDevicePosition.back
    fileprivate var sessionRunning = false

    override init() {
        super.init()
        self.sessionQueue = DispatchQueue(label: "com.camera360.queue.session")
    }

    func startCamera() {
        self.sessionQueue.async {
            switch self.sessionSetupResult {
            case .success:
                self.session.startRunning()
                self.sessionRunning = self.session.isRunning
            case .notAuthorized, .configurationFailed:
                print("start camera failed")
            }
        }
    }

    func stopCamera() {
        self.sessionQueue.async {
            self.session.stopRunning()
            self.sessionRunning = self.session.isRunning
        }
    }

    func initSession(_ finish: @escaping () -> ()) {
        fatalError("must be override by subclass")
    }

    func configDevice(_ action: @escaping (_ device: AVCaptureDevice) -> (), finish: @escaping () -> ()) throws {
        self.sessionQueue.async {
            if let device = self.deviceInput?.device {
                do {
                   try device.lockForConfiguration()
                    action(device)
                    device.unlockForConfiguration()
                    DispatchQueue.main.async(execute: {
                        finish()
                    })
                } catch {
                    print("配置失败")
                }
            }
        }
    }

    func configSession(_ action: @escaping (_ session: AVCaptureSession) -> (), finish: @escaping () -> ()) {
        self.sessionQueue.async {
            self.session.beginConfiguration()
            action(self.session)
            self.session.commitConfiguration()
            DispatchQueue.main.async(execute: {
                finish()
            })
        }
    }
}

public extension CLCaptureDevice {
    var position: AVCaptureDevicePosition {
        get {
            return positionValue
        }
        set {
            if self.positionValue == newValue {
                return
            }
            self.configSession({ (session) in
                session.removeInput(self.deviceInput)
                let device = AVCaptureDevice.device(AVMediaTypeVideo, position: newValue)
                var devieInput: AVCaptureDeviceInput?
                do {
                    devieInput = try AVCaptureDeviceInput(device: device)
                } catch { print(error) }

                if session.canAddInput(devieInput) {
                    session.addInput(devieInput)
                    self.deviceInput = devieInput
                    self.positionValue = newValue
                }
                }) {
            }
        }
    }
}

public class CLPhotoCaptureDevice: CLCaptureDevice {
    var videoDataOutput: AVCaptureVideoDataOutput?

    override func initSession(_ finish: @escaping () -> ()) {
        self.sessionQueue.async {
            let videoDevice = AVCaptureDevice.device(AVMediaTypeVideo, position: .back)
            var videoDeviceInput: AVCaptureDeviceInput?
            do {
                videoDeviceInput = try AVCaptureDeviceInput.init(device: videoDevice)
            } catch { print(error) }

            self.session.beginConfiguration()
            if self.session.canAddInput(videoDeviceInput) {
                self.session.addInput(videoDeviceInput)
            } else {
                self.sessionSetupResult = .configurationFailed
            }

            let videoDataOutput = AVCaptureVideoDataOutput()
            let connection = videoDataOutput.connection(withMediaType: AVMediaTypeVideo)
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = .auto
            }
            if (connection?.isVideoOrientationSupported)! {
                connection?.videoOrientation = .portrait
            }
            if self.session.canAddOutput(videoDataOutput) {
                self.session.addOutput(videoDataOutput)
            } else {
                self.sessionSetupResult = .configurationFailed
            }

            let stillImageOutput = AVCaptureStillImageOutput()
            if self.session.canAddOutput(stillImageOutput) {
                self.session.addOutput(stillImageOutput)
            } else {
                self.sessionSetupResult = .configurationFailed
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                finish()
            }
        }
    }
}

public class CLVideoCaptureDevice: CLCaptureDevice, CLRecordingVideoable {

    var movieFileOutput: AVCaptureMovieFileOutput?

    override func initSession(_ finish: @escaping () -> ()) {
        self.sessionQueue.async {
            let videoDevice = AVCaptureDevice.device(AVMediaTypeVideo, position: .back)
            var videoDeviceInput: AVCaptureDeviceInput?
            do {
                videoDeviceInput = try AVCaptureDeviceInput.init(device: videoDevice)
            } catch { print(error) }

            self.session.beginConfiguration()
            if self.session.canAddInput(videoDeviceInput) {
                self.session.addInput(videoDeviceInput)
                self.deviceInput = videoDeviceInput
            } else {
                self.sessionSetupResult = .configurationFailed
            }

            let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
            var audioDeviceInput: AVCaptureDeviceInput?
            do {
                audioDeviceInput = try AVCaptureDeviceInput.init(device: audioDevice)
            } catch { print(error) }

            if self.session.canAddInput(audioDeviceInput) {
                self.session.addInput(audioDeviceInput)
            }

            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.addOutput(movieFileOutput)
                let connection = movieFileOutput.connection(withMediaType: AVMediaTypeVideo)
                if (connection?.isVideoStabilizationSupported)! {
                    connection?.preferredVideoStabilizationMode = .auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                self.sessionSetupResult = .configurationFailed
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async(execute: {
                finish()
            })
        }
    }

    func startRecording(_ outputFile: URL, delegate: AVCaptureFileOutputRecordingDelegate) {
    }

    func stopRecording() {

    }
}

public class CLCameraManager: NSObject {
    enum CLCaptureType {
        case photo
        case video
    }

    class var shareManager: CLCameraManager {
        struct Static {
            static let instance = CLCameraManager()
        }
        return Static.instance
    }

    func captureDevice(_ type: CLCaptureType) -> CLCaptureDevice {
        return captureDevice(type, configSession: nil)
    }

    func captureDevice(_ type: CLCaptureType, configSession: (() -> ())?) -> CLCaptureDevice {
        var captureDevice: CLCaptureDevice!
        switch type {
        case .photo:
            captureDevice = CLPhotoCaptureDevice()
        case .video:
            captureDevice = CLVideoCaptureDevice()
        }
        captureDevice.initSession {
            if let configSession = configSession {
                configSession()
            }
            print("相机配置完毕")
        }
        return captureDevice
    }
}
