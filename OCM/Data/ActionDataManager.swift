//
//  ActionDataManager.swift
//  OCM
//
//  Created by Alejandro Jiménez Agudo on 11/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation


enum ActionError: Error {
	case notInCache
	case cacheNotInitialized
	case jsonError
	
	func logError(filename: NSString = #file, line: Int = #line, funcname: String = #function) {
		var string: String
		
		switch self {
		case .notInCache:
			string = "Action not in cache"
			
		case .cacheNotInitialized:
			string = "Cache not initialized"
			
		case .jsonError:
			string = "Error parsing json action"
		}
		
		logWarn(string, filename: filename, line: line, funcname: funcname)
	}
}

struct ActionDataManager {
	
	let storage: Storage
    let elementService: ElementService
	
	func cachedAction(from url: String) throws -> Action {
		guard var action = ContentCoreDataPersister.shared.loadAction(with: url) else { throw ActionError.notInCache }
        action.identifier = url
		return action
	}
    
    func cachedOrAPIAction(with identifier: String, completion: @escaping (Action?, Error?) -> Void) {
        do {
            let action = try self.cachedAction(from: identifier)
            completion(action, nil)
        } catch _ {
            self.elementService.getElement(with: identifier, completion: { result in
                switch result {
                case .success(let action):
                    completion(action, nil)
                case .error(let error):
                    completion(nil, error)
                }
            })
        }
    }
}
