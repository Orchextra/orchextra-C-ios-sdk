//
//  Section.swift
//  OCM
//
//  Created by Alejandro Jiménez Agudo on 4/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary

public struct Section {
    
    public let name: String
    public let slug: String
    public let elementUrl: String
    public let customProperties: [String: Any]?
    public let contentVersion: String?
    
    private let actionInteractor: ActionInteractor
    
    init(name: String, slug: String, elementUrl: String, customProperties: [String: Any]?, contentVersion: String?) {
        self.name = name
        self.elementUrl = elementUrl
        self.slug = slug
        self.customProperties = customProperties
        self.contentVersion = contentVersion
        
        self.actionInteractor = ActionInteractor(
            contentDataManager: .sharedDataManager,
            ocmController: OCMController.shared,
            actionScheduleManager: ActionScheduleManager.shared
        )
    }
    
    static public func parseSection(json: JSON) -> Section? {
        guard
            let name = json["sectionView.text"]?.toString(),
            let slug = json["slug"]?.toString(),
            let elementUrl = json["elementUrl"]?.toString() else {
                logWarn("Mandatory field not found")
                return nil
        }
        
        return Section(
            name: name,
            slug: slug,
            elementUrl: elementUrl,
            customProperties: json["customProperties"]?.toDictionary(),
            contentVersion: json["contentVersion"]?.toString()
        )
    }
    
    public func openAction(completion: @escaping (UIViewController?) -> Void) {
        self.actionInteractor.action(forcingDownload: false, with: self.elementUrl) { action, _ in
            guard let action = action else { logWarn("actions is nil"); return }
            if let view = ActionViewer(action: action, ocmController: OCMController.shared).view() {
                completion(view)
            } else {
                ActionInteractor().run(action: action, viewController: nil)
                completion(nil)
            }
        }
    }
}

extension Section: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(slug)
        hasher.combine(elementUrl)
    }

    public static func == (lhs: Section, rhs: Section) -> Bool {
        
        return lhs.hashValue == rhs.hashValue
    }
}
