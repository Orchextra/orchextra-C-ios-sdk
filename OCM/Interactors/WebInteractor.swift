//
//  WebInteractor.swift
//  OCM
//
//  Created by Carlos Vicente on 11/1/17.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation

class WebInteractor {
    let passBookWrapper: PassbookWrapperProtocol
    var passbookResult: PassbookWrapperResult?
    
    init(passbookWrapper: PassbookWrapperProtocol) {
        self.passBookWrapper = passbookWrapper
    }
    
    func userDidProvokeRedirection(with url: URL, completionHandler: @escaping (PassbookWrapperResult) -> Void) -> Void {
        let lastPathComponent = url.lastPathComponent
        if lastPathComponent == "passbook" ||
            lastPathComponent.hasSuffix("pkpass") {
            self.performAction(for: url, completionHandler: completionHandler)
        }
    }
    
    fileprivate func performAction(for url: URL, completionHandler: @escaping (PassbookWrapperResult) -> Void) -> Void {
        let urlString = url.absoluteString
         passBookWrapper.addPassbook(from: urlString) { result in
            switch result {
            case .success:
                 completionHandler(.success)
                
            case .unsupportedVersionError(let error):
                 completionHandler(.unsupportedVersionError(error))
                
            case .error(let error):
                completionHandler(.error(error))
            }
            
            self.passbookResult = result
        }
    }
}
