//
//  ImageConstants.swift
//  OCM
//
//  Created by Sergio López on 25/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit

extension UIImage {
    struct OCM {
        static let previewGrading = UIImage(named: "preview_grading", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let previewSmallGrading = UIImage(named: "preview_small_grading", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let previewScrollDownIcon = UIImage(named: "preview_scroll_arrow_icon", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let playIconPreviewView = UIImage(named: "iconPlay", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let shareButtonIcon = UIImage(named: "content_share_button", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let backButtonIcon = UIImage(named: "content_back_button", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let closeButtonIcon = UIImage(named: "iconClose", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let loadingIcon = UIImage(named: "spinner", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let soundOnButtonIcon = UIImage(named: "sound_on_button", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let soundOffButtonIcon = UIImage(named: "sound_off_button", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let scrollDownIcon = UIImage(named: "scrolldownicon", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let playIcon = UIImage(named: "play", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let pauseIcon = UIImage(named: "pause", in: Bundle.OCMBundle(), compatibleWith: nil)
        static let playerOval = UIImage(named: "oval", in: Bundle.OCMBundle(), compatibleWith: nil)
    }
}
