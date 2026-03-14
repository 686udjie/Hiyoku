//
//  PipController.swift
//  Hiyoku
//
//  Created by 686udjie on 03/14/26.
//

import UIKit
import AVKit

// MARK: - Picture in Picture
extension PlayerViewController: AVPictureInPictureControllerDelegate {
    func setupPictureInPictureIfPossible() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }

        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            return
        }
        controller.delegate = self
        pipController = controller
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
    }
}
