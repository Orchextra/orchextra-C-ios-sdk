//
//  ActionBrowser.swift
//  OCM
//
//  Created by Judith Medina on 26/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary


class ActionBrowser: Action {
    
    var output: ActionOut?
    internal var identifier: String?
    internal var preview: Preview?
    internal var shareInfo: ShareInfo?
    internal var actionView: OrchextraViewController?
    internal var federated: [String: Any]?
    
    var url: URL
    
    init(url: URL, preview: Preview?, shareInfo: ShareInfo?, federated: [String: Any]?) {
        self.url = url
        self.preview = preview
        self.shareInfo = shareInfo
        self.federated = federated
    }
    
    static func action(from json: JSON) -> Action? {
        guard json["type"]?.toString() == ActionType.actionBrowser
            else { return nil }
        
        if let render = json["render"] {
            
            guard let urlString = render["url"]?.toString() else {
                logError(NSError(message: "URL render webview not valid."))
                return nil
            }
            guard let url = URL(string: urlString) else { return nil }
            let federated = render["federatedAuth"]?.toDictionary()
            return ActionBrowser(url: url, preview: preview(from: json), shareInfo: shareInfo(from: json), federated: federated)
        }
        return nil
    }
    
    func view() -> OrchextraViewController? {
        return self.actionView
    }
    
    func executable() {
        _ = OCM.shared.wireframe.showBrowser(url: self.url)
    }
    
    func run(viewController: UIViewController?) {
        guard let fromVC = viewController else {
            return
        }
        
        if OCM.shared.isLogged {
            if let federatedData = self.federated, federatedData["active"] as? Bool == true {
                self.output?.blockView()
                OCM.shared.delegate?.federatedAuthentication(federatedData, completion: { params in
                    self.output?.unblockView()
                    
                    var urlFederated = self.url.absoluteString
                    
                    guard let params = params else {
                        logWarn("ActionBrowser: urlFederatedAuth params is null")
                        self.launchAction(fromVC: fromVC)
                        return
                    }
                    
                    for (key, value) in params {
                        urlFederated = self.concatURL(url: urlFederated, key: key, value: value)
                    }
                    
                    guard let urlFederatedAuth = URL(string: urlFederated) else {
                        logWarn("ActionBrowser: urlFederatedAuth is not a valid URL")
                        self.launchAction(fromVC: fromVC)
                        return
                        
                    }
                    self.url = urlFederatedAuth
                    logInfo("ActionBrowser: received urlFederatedAuth: \(self.url)")
                    
                    self.launchAction(fromVC: fromVC)
                })
            } else {
                logInfo("ActionBrowser: open: \(self.url)")
                self.launchAction(fromVC: fromVC)
            }
        } else {
            self.launchAction(fromVC: fromVC)
        }
    }
    
    // MARK: Private Method
    
    private func launchAction(fromVC: UIViewController) {
        if self.preview != nil {
            OCM.shared.wireframe.showMainComponent(with: self, viewController: fromVC)
        } else {
            OCM.shared.wireframe.showBrowser(url: self.url)
        }
    }
    
    private func concatURL(url: String, key: String, value: Any) -> String {
        guard let valueURL = value as? String else {
            LogWarn("Value URL is not a String")
            return url
        }
        
        var urlResult = url
        if url.contains("?") {
            urlResult = "\(url)&\(key)=\(valueURL)"
        } else {
            urlResult = "\(url)?\(key)=\(valueURL)"
        }
        return urlResult
    }
}
