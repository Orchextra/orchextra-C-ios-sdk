//
//  Element.swift
//  OCM
//
//  Created by Judith Medina on 18/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary

/// Implement this protocol in the class that have to handle the element action
protocol ActionableElementDelegate: class {
    
    /// Method called when the element wants to perform his action
    ///
    /// - Parameters:
    ///   - element: The element itself
    ///   - info: Extra info about the element relevant to perform the action
    func performAction(of element: Element, with info: Any)
}

/// Implement this protocol in each Element that needs to perform any action when it has tapped or similar
protocol ActionableElement {
    weak var actionableDelegate: ActionableElementDelegate? { get set }
}

/// Implement this protocol in the class that have to handle the element configuration
protocol ConfigurableElementDelegate: class {
    
    /// Method called when the element wants to configure
    ///
    /// - Parameter element: The element itself
    func configure(_ element: Element)
}

/// Implement this protocol in each Element that needs extra info to be configured
protocol ConfigurableElement {
    weak var configurableDelegate: ConfigurableElementDelegate? { get set }
    
    /// Method called to update the element information
    ///
    /// - Parameter info: The info to update the Element
    func update(with info: [AnyHashable: Any])
    
    // TODO: Add documentation
    func checkVisibility()
}

protocol Element {
    func render() -> [UIView]
    func descriptionElement() -> String
}

// IMPLEMENTATION BY DEFAULT
extension Element {
    func render() -> [UIView] {
        return []
    }
}

class ElementFactory {
    
    class func element(from json: JSON, element: Element) -> Element? {
        
        guard let type = json[ParsingConstants.Element.kType]?.toString(),
            let render = json[ParsingConstants.Element.kRender]
            else {return nil}
        
        switch type {
        case ParsingConstants.VideoElement.kVideoType:
            return ElementVideo.parseRender(from: render, element: element)
        case ParsingConstants.ImageElement.kImageType:
            return ElementImage.parseRender(from: render, element: element)
        case ParsingConstants.RichTextElement.kRichTextType:
            return ElementRichText.parseRender(from: render, element: element)
        case ParsingConstants.HeaderElement.kHeaderType:
            return ElementHeader.parseRender(from: render, element: element)
        case ParsingConstants.ButtonElement.kButtonType:
            return ElementButton.parseRender(from: render, element: element)
        default:
            return nil
        }
    }
}
