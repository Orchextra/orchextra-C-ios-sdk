//
//  ArticleInteractor.swift
//  OCM
//
//  Created by Eduardo Parada on 6/11/17.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation
import GIGLibrary

protocol ArticleInteractorProtocol: class {
    func traceSectionLoadForArticle()
    func action(of element: Element, with info: Any)
}

protocol ArticleInteractorOutput: class {
    func willExecuteAction(_ action: Action)
    func actionLoadingDidFinishWithAction(_ action: Action)
    func actionLoadingDidFinishWithError(_ error: Error)
    func showVideo(_ video: Video, in player: VideoPlayerProtocol?)
}

class ArticleInteractor: ArticleInteractorProtocol {
    
    var elementUrl: String?
    weak var output: ArticleInteractorOutput?
    let sectionInteractor: SectionInteractorProtocol
    let actionInteractor: ActionInteractorProtocol
    var ocm: OCM
    var ocmController: OCMController
    
    // MARK: - Initializer
    
    init(elementUrl: String?, sectionInteractor: SectionInteractorProtocol, actionInteractor: ActionInteractorProtocol, ocm: OCM) {
        self.elementUrl = elementUrl
        self.sectionInteractor = sectionInteractor
        self.actionInteractor = actionInteractor
        self.ocm = ocm
        self.ocmController = OCMController.shared
    }
    
    // MARK: - ArticleInteractorProtocol
    
    func traceSectionLoadForArticle() {
        guard
            let elementUrl = self.elementUrl,
            let section = self.sectionInteractor.sectionForActionWith(identifier: elementUrl)
            else {
                logWarn("Element url or section is nil")
                return
        }
        self.ocm.eventDelegate?.sectionDidLoad(section)
    }
    
    func action(of element: Element, with info: Any) {
        if let customProperties = element.customProperties {
            self.ocm.customBehaviourDelegate?.contentNeedsValidation(
                for: customProperties,
                completion: { (succeed) in
                    if succeed {
                        self.performAction(of: element, with: info)
                    }
            })
        } else {
            self.performAction(of: element, with: info)
        }
    }
    
    // MARK: - Helpers
    
    private func performAction(of element: Element, with info: Any) {
        if element is ElementButton {
            self.performButtonAction(info)
        } else if element is ElementRichText {
            self.performRichTextAction(info)
        } else if element is ElementVideo {
            self.performVideoAction(info)
        }
    }

    private func performButtonAction(_ info: Any) {
        // Perform button's action
        if let action = info as? String {
            self.actionInteractor.action(forcingDownload: false, with: action) { action, error in
                if var unwrappedAction = action {
                    if let elementUrl = unwrappedAction.elementUrl, !elementUrl.isEmpty {
                        self.ocm.eventDelegate?.userDidOpenContent(identifier: elementUrl, type: unwrappedAction.type ?? "")
                    } else if let slug = unwrappedAction.slug, !slug.isEmpty {
                        self.ocm.eventDelegate?.userDidOpenContent(identifier: slug, type: unwrappedAction.type ?? "")
                    }
                    if  ActionViewer(action: unwrappedAction, ocmController: self.ocmController).view() != nil {
                        self.output?.actionLoadingDidFinishWithAction(unwrappedAction)
                    } else {
                        self.output?.willExecuteAction(unwrappedAction)
                        ActionInteractor().execute(action: unwrappedAction)
                    }
                } else if let error = error {
                    self.output?.actionLoadingDidFinishWithError(error)
                }
            }
        }
    }
    
    private func performRichTextAction(_ info: Any) {
        // Open hyperlink's URL on web view
        if let URL = info as? URL {
            // Open on Safari VC
            self.ocmController.wireframe?.showBrowser(url: URL)
        }
    }
    
    private func performVideoAction(_ info: Any) {
        if let dictionary = info as? [String: Any], let video = dictionary["video"] as? Video {
            let player = dictionary["player"] as? VideoPlayerProtocol
            self.output?.showVideo(video, in: player)
        }
    }
}
