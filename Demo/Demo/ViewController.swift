//
//  ViewController.swift
//  Demo
//
//  Created by clee on 16/10/25.
//  Copyright © 2016年 lixiang. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    var cameraView = CLCameraPreviewView()
    var captureDevice: CLCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        cameraView.frame = self.view.bounds
        cameraView.backgroundColor = UIColor.black
        self.view.addSubview(cameraView)

        captureDevice = CLCameraManager.shareManager.captureDevice(.video) {
            let statusbarOriention = UIApplication.shared.statusBarOrientation
            var videoOriention = AVCaptureVideoOrientation.portrait
            if statusbarOriention != .unknown {
                videoOriention = AVCaptureVideoOrientation(rawValue: statusbarOriention.rawValue)!
            }
            let layer = self.cameraView.layer as! AVCaptureVideoPreviewLayer
            layer.videoGravity = AVLayerVideoGravityResizeAspectFill
            layer.connection.videoOrientation = videoOriention
        }
        cameraView.session = captureDevice!.session
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.captureDevice?.startCamera()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.captureDevice?.stopCamera()
    }
}

