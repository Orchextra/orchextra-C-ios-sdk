//
//  PreviewInteractionController.swift
//  OCM
//
//  Created by Sergio López on 24/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary

protocol Behaviour: class {
    init(scroll: UIScrollView, previewView: UIView, content: OrchextraViewController?)
    func performAction(with info: Any?, completion: @escaping (Bool) -> Void)
}

enum BehaviourType {
    case tap
    case swipe
    
    static func behaviour(fromJson json: JSON) -> BehaviourType? {
        guard let behaviourString = json["behaviour"]?.toString() else { return nil }
        switch behaviourString {
        case "click":
            return .tap
        case "swipe":
            return .swipe
        default:
            return nil
        }
    }
}

struct PreviewInteractionController {
    
    private let behaviour: Behaviour
    
    // MARK: - Init
    
    static func previewInteractionController(scroll: UIScrollView, previewView: UIView, preview: Preview, content: OrchextraViewController?) -> Behaviour? {
        
        switch preview.behaviour {
        case .some(.tap):
            return Tap(scroll: scroll, previewView: previewView, content: content)
        case .some(.swipe):
            return Swipe(scroll: scroll, previewView: previewView, content: content)
        default:
            return nil
        }
    }
}
