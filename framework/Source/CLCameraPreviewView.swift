//
//  CLCameraPreviewView.swift
//  CLVideokit
//
//  Created by clee on 16/10/25.
//  Copyright © 2016年 lixiang. All rights reserved.
//

import UIKit
import AVFoundation

class CLCameraPreviewView: UIView {

    var session: AVCaptureSession {
        get {
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            return previewLayer.session
        }
        set {
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            previewLayer.session = newValue
        }
    }

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}
