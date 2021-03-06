//
//  PreviewListCollectionViewCell.swift
//  OCM
//
//  Created by Jerilyn Goncalves on 03/04/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import UIKit

class PreviewListCollectionViewCell: UICollectionViewCell {
    
    override init(frame: CGRect) {
        
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setup(with preview: PreviewView) {

        let subview = preview.show()
        subview.clipsToBounds = true
        contentView.addSubview(subview, settingAutoLayoutOptions: [.zeroMargin(to: contentView)])
    }
}
