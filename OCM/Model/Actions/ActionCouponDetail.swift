//
//  ActionCouponDetail.swift
//  OCM
//
//  Created by Alejandro Jiménez on 19/4/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import GIGLibrary


struct ActionCouponDetail: Action {
    internal var preview: Preview?
    internal var shareUrl: String?

	
	var idCoupon: String
	
	static func action(from json: JSON) -> Action? {
		return nil
	}
	
    func run(viewController: UIViewController?) {
		OCM.shared.delegate?.openCoupon(with: self.idCoupon)
	}
	
}
