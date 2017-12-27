//
//  ArticleViewController.swift
//  OCM
//
//  Created by Judith Medina on 17/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary

class ArticleViewController: OrchextraViewController, Instantiable {
    
    // MARK: - Outlets
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    // MARK: - Attributes
    
    var stackView: UIStackView?
    var presenter: ArticlePresenter?
	
    static var identifier =  "ArticleViewController"
	
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
        self.presenter?.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.presenter?.viewWillAppear()
    }
    
    // MARK: Helpers
    
    private func setup() {
        self.stackView = UIStackView()
        self.stackView?.axis = .vertical
        self.stackView?.distribution = .fill
        self.stackView?.alignment = .fill
        self.stackView?.spacing = 0
        if let stackView = self.stackView {
            self.view.addSubview(stackView)
            self.addWrappingConstraints()
        }
        self.activityIndicator.color = Config.styles.primaryColor
    }
    
    private func addWrappingConstraints() {
        if let stackView = self.stackView {
            stackView.translatesAutoresizingMaskIntoConstraints = false
            // Attach to top
            self.view.addConstraint(NSLayoutConstraint(item: stackView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0))
            // Attach to view controller's bottom layout guide
            self.view.addConstraint(NSLayoutConstraint(item: stackView, attribute: .bottom, relatedBy: .lessThanOrEqual, toItem: self.bottomLayoutGuide, attribute: .bottom, multiplier: 1, constant: 0))
            // Attach to left
            self.view.addConstraint(NSLayoutConstraint(item: stackView, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0))
            // Attach to right
            self.view.addConstraint(NSLayoutConstraint(item: stackView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0))
        }
        self.view.layoutIfNeeded()
    }
}

extension ArticleViewController: ActionableElementDelegate {
    
    func performAction(of element: Element, with info: Any) {
        self.presenter?.performAction(of: element, with: info)
    }
}

extension ArticleViewController: ConfigurableElementDelegate {
    
    func configure(_ element: Element) {
        self.presenter?.configure(element: element)
    }
}

// MARK: PArticleVC

extension  ArticleViewController: ArticleUI {
    func show(article: Article) {
        for case var element as ActionableElement in article.elements {
            element.actionableDelegate = self
        }
        for case var element as ConfigurableElement in article.elements {
            element.configurableDelegate = self
        }
        // We choose the last because Elements are created following the Decorator Pattern
        guard let last = article.elements.last else { logWarn("last element is nil"); return }
        for element in last.render() {
            print("Adding: \(element)")
            self.stackView?.addArrangedSubview(element)
        }
    }
    
    func showViewForAction(_ action: Action) {
        OCM.shared.wireframe.showMainComponent(with: action, viewController: self)
    }
    
    func update(with article: Article) {
        self.stackView?.removeFromSuperview()
        self.setup()
        self.show(article: article)
    }
    
    
    func showLoadingIndicator() {
        self.activityIndicator.startAnimating()
    }
    
    func dismissLoadingIndicator() {
        self.activityIndicator.stopAnimating()
    }
    
    func displaySpinner(show: Bool) {
        self.showSpinner(show: show)
    }
    
    func showAlert(_ message: String) {
        if let parentViewController = self.parent as? OrchextraViewController {
            parentViewController.showBannerAlert(message)
        }
    }
}
