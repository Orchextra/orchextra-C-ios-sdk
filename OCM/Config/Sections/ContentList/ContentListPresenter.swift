//
//  ContentListPresenter.swift
//  OCM
//
//  Created by Alejandro Jiménez Agudo on 31/3/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit

enum ViewState {
    case error
    case loading
    case showingContent
    case noContent
    case noSearchResults
}

enum Authentication: String {
    case logged
    case anonymous
}

enum ContentSource {
    case initialContent
    case refreshing
    case becomeActive
    case internetBecomesActive
    case search
}

protocol ContentListView: class {
    func layout(_ layout: LayoutDelegate)
	func show(_ contents: [Content])
    func showNewContentAvailableView(with contents: [Content])
    func dismissNewContentAvailableView()
    func state(_ state: ViewState)
    func show(error: String)
    func showAlert(_ message: String)
    func set(retryBlock: @escaping () -> Void)
    func reloadVisibleContent()
    func stopRefreshControl()
    func displaySpinner(show: Bool)
}

class ContentListPresenter {
	
	let defaultContentPath: String?
	weak var view: ContentListView?
    var contents = [Content]()
	let contentListInteractor: ContentListInteractorProtocol
    var currentFilterTags: [String]?
    let reachability = ReachabilityWrapper.shared
    let refreshManager = RefreshManager.shared
    var viewDataStatus: ViewDataStatus = .notLoaded
    
    // MARK: - Init
    
    init(view: ContentListView, contentListInteractor: ContentListInteractorProtocol, defaultContentPath: String? = nil) {
        self.defaultContentPath = defaultContentPath
        self.view = view
        self.contentListInteractor = contentListInteractor
    }
    
    deinit {
        self.refreshManager.unregisterForNetworkChanges(self)
    }
    
    // MARK: - PUBLIC
    
	func viewDidLoad() {
        self.refreshManager.registerForNetworkChanges(self)
        if let defaultContentPath = self.defaultContentPath {
            self.fetchContent(fromPath: defaultContentPath, of: .initialContent)
        }
	}
	
    func applicationDidBecomeActive() {
        if let defaultContentPath = self.defaultContentPath {
            self.fetchContent(fromPath: defaultContentPath, of: .becomeActive)
        }
    }
    
    func userDidSelectContent(_ content: Content, viewController: UIViewController) {

        if !Config.isLogged && content.requiredAuth == "logged" {
            OCM.shared.delegate?.requiredUserAuthentication() // TODO: Remove in version 3.0.0 of SDK
            OCM.shared.delegate?.contentRequiresUserAuthentication {
                if Config.isLogged && OrchextraWrapper.shared.currentUser() != nil {
                    ActionScheduleManager.shared.registerAction(for: .login) { [unowned self] in
                        self.userDidSelectContent(content, viewController: viewController)
                    }
                }
            }
        } else {
            if self.reachability.isReachable() {
                self.openContent(content, in: viewController)
            } else if Config.offlineSupport, ContentCacheManager.shared.cachedArticle(for: content) != nil {
                self.openContent(content, in: viewController)
            } else {
                self.view?.showAlert(Config.strings.internetConnectionRequired)
            }
        }
	}
	
    func userDidFilter(byTag tags: [String]) {
        
        self.currentFilterTags = tags
        
        let filteredContent = self.contents.filter(byTags: tags)
        self.show(contents: filteredContent, contentSource: .initialContent)
    }
    
    func userDidSearch(byString string: String) {
        self.fetchContent(matchingString: string, showLoadingState: true)
    }
    
    func userDidRefresh() {
        self.view?.dismissNewContentAvailableView()
        if let defaultContentPath = self.defaultContentPath {
            self.fetchContent(fromPath: defaultContentPath, of: .refreshing)
        }
    }
    
    func userAskForInitialContent() {
        if self.defaultContentPath != nil {
            self.currentFilterTags = nil
            self.show(contents: self.contents, contentSource: .initialContent)
        } else {
            self.clearContent()
        }
    }
    
    // MARK: - PRIVATE
    
    
    fileprivate func fetchContent(fromPath path: String, of contentSource: ContentSource) {
        self.view?.set {
            self.fetchContent(fromPath: path, of: contentSource)
        }
        switch contentSource {
        case .initialContent:
            self.view?.state(.loading)
        default:
            break
        }
        self.contentListInteractor.contentList(from: path, forcingDownload: shouldForceDownload(for: contentSource)) { result in
            let oldContents = self.contents
            // If the response is success, set the contents downloaded
            switch result {
            case .success(let contentList):
                self.contents = contentList.contents
            default: break
            }
            // Check the source to update the content or show a message
            switch contentSource {
            case .becomeActive, .internetBecomesActive:
                if oldContents.count == 0 {
                    self.show(contentListResponse: result, contentSource: contentSource)
                } else if oldContents != self.contents {
                    self.view?.showNewContentAvailableView(with: self.contents)
                } else {
                    self.view?.reloadVisibleContent()
                }
            default:
                self.show(contentListResponse: result, contentSource: contentSource)
            }
            self.viewDataStatus = .canReload
        }
    }
    
    private func fetchContent(matchingString searchString: String, showLoadingState: Bool) {

        if showLoadingState { self.view?.state(.loading) }
        
        self.view?.set(retryBlock: { self.fetchContent(matchingString: searchString, showLoadingState: showLoadingState) })
        
        self.contentListInteractor.contentList(matchingString: searchString) {  result in
            self.show(contentListResponse: result, contentSource: .search)
        }
    }
    
    private func show(contentListResponse: ContentListResult, contentSource: ContentSource) {
        switch contentListResponse {
        case .success(let contentList):
            self.show(contentList: contentList, contentSource: contentSource)
        case .empty:
            self.showEmptyContentView(forContentSource: contentSource)
        case .cancelled:
            self.view?.stopRefreshControl()
        case .error:
            self.view?.show(error: kLocaleOcmErrorContent)
            self.view?.state(.error)
        }
    }

    private func show(contentList: ContentList, contentSource: ContentSource) {
        self.view?.layout(contentList.layout)
        
        var contentsToShow = contentList.contents
        
        if let tags = self.currentFilterTags {
            contentsToShow = contentsToShow.filter(byTags: tags)
        }
        
        self.show(contents: contentsToShow, contentSource: contentSource)
    }
    
    private func show(contents: [Content], contentSource: ContentSource) {
        if contents.isEmpty {
            self.showEmptyContentView(forContentSource: contentSource)
        } else {
            self.view?.show(contents)
            self.view?.state(.showingContent)
        }
    }
    
    private func showEmptyContentView(forContentSource source: ContentSource) {
        switch source {
        case .initialContent, .becomeActive, .refreshing, .internetBecomesActive:
            self.view?.state(.noContent)
        case .search:
            self.view?.state(.noSearchResults)
        }
    }
    
    private func openContent(_ content: Content, in viewController: UIViewController) {
        // Notified when user opens a content
        OCM.shared.delegate?.userDidOpenContent(with: content.elementUrl)
        OCM.shared.analytics?.track(
            with: [AnalyticConstants.kAction: AnalyticConstants.kContent,
                   AnalyticConstants.kType: AnalyticConstants.kAccess,
                   AnalyticConstants.kContentType: content.type ?? "",
                   AnalyticConstants.kValue: content.elementUrl]
        )
        _ = content.openAction(from: viewController, contentList: self)
    }
    
    private func clearContent() {
        self.view?.show([])
    }
    
    private func shouldForceDownload(for contentSource: ContentSource) -> Bool {
        switch contentSource {
        case .becomeActive, .refreshing, .search, .internetBecomesActive:
            return true
        default:
            return false
        }
    }
}

extension ContentListPresenter: Refreshable {
    
    func refresh() {
        if let defaultContentPath = self.defaultContentPath {
            self.fetchContent(fromPath: defaultContentPath, of: .internetBecomesActive)
        }
    }
}

// MARK: - ActionOut

extension ContentListPresenter: ActionOut {
    
    func blockView() {
        self.view?.displaySpinner(show: true)
    }
    
    func unblockView() {
        self.view?.displaySpinner(show: false)
    }
}
