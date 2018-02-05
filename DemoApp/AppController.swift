//
//  AppController.swift
//  OCMDemo
//
//  Created by Judith Medina on 25/10/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary

class AppController: NSObject, SettingOutput {
    
    static let shared = AppController()

    let application = Application()
    var window: UIWindow?
    
    // Attributes Orchextra
    var orchextraHost: Environment = .staging
    var orchextraApiKey = InfoDictionary("ORCHEXTRA_APIKEY")
    var orchextraApiSecret = InfoDictionary("ORCHEXTRA_APISECRET")

    func homeDemo() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let settingsVC = storyboard.instantiateViewController(withIdentifier: "HomeVC") as? ViewController else {
            return
        }
        let navigationController = UINavigationController(rootViewController: settingsVC)
        navigationController.setNavigationBarHidden(true, animated: false)
        self.window?.rootViewController = navigationController
    }
    
    func settings() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let settingsVC = storyboard.instantiateViewController(withIdentifier: "SettingsVC") as? SettingsVC else {
            return
        }
        settingsVC.settingOutput = self
        self.application.presentModal(settingsVC)
    }
    
    func orxCredentialesHasChanged(apikey: String, apiSecret: String) {
        self.orchextraApiKey = apikey
        self.orchextraApiSecret = apiSecret
        self.homeDemo()
    }
}

extension UIApplication {
    class func topViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(base: selected)
            }
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
