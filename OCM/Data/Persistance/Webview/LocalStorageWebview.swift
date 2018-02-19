//
//  LocalStorageWebview.swift
//  OCM
//
//  Created by Eduardo Parada on 19/2/18.
//  Copyright © 2018 Gigigo SL. All rights reserved.
//

import Foundation
import WebKit

class LocalStorageWebview {
    
    class func removeLocalStorage() {
        if #available(iOS 9.0, *) {
            let websiteDataTypes = NSSet(array: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeLocalStorage])
            let date = NSDate(timeIntervalSince1970: 0)
            
            guard let webSite = websiteDataTypes as? Set<String> else {
                return
            }
            
            WKWebsiteDataStore.default().removeData(ofTypes: webSite, modifiedSince: date as Date, completionHandler: {
                
            })
        } else {
            var libraryPath = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.libraryDirectory, FileManager.SearchPathDomainMask.localDomainMask, false).first!
            libraryPath += "/Cookies"
            
            do {
                try FileManager.default.removeItem(atPath: libraryPath)
            } catch {
                print("error")
            }
            URLCache.shared.removeAllCachedResponses()
        }
    }
}
