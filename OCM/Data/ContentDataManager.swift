//
//  ContentDataManager.swift
//  OCM
//
//  Created by José Estela on 14/6/17.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation
import GIGLibrary

typealias ContentListResultHandler = (Result<ContentList, NSError>) -> Void
typealias MenusResultHandler = (Result<[Menu], OCMRequestError>, Bool) -> Void

/// Defines the source for obtaining data for a given context
enum DataSource<T> {
    /// Data is obtained from server
    case fromNetwork
    /// Data is obtained from the persistent store (cache)
    case fromCache(T)
    /// Data is obtained from virtual memory (preloaded data)
    case fromMemory(T)
}

class ContentListRequest {
    
    let path: String
    let page: Int
    let items: Int
    let preload: Bool
    let completion: ContentListResultHandler
    
    init(path: String, page: Int, items: Int, preload: Bool, completion: @escaping (Result<ContentList, NSError>) -> Void) {
        self.path = path
        self.page = page
        self.items = items
        self.preload = preload
        self.completion = completion
    }
}

class ContentListRequestHandler {
    
    let path: String
    let page: Int
    var completions: [ContentListResultHandler]
    
    init(path: String, page: Int, completions: [ContentListResultHandler]) {
        self.path = path
        self.page = page
        self.completions = completions
    }
}

class ContentDataManager {
    
    // MARK: - Attributes
    
    static let sharedDataManager: ContentDataManager = defaultDataManager()

    let contentPersister: ContentPersister
    let menuService: MenuService
    let elementService: ElementServiceInput
    let contentListService: ContentListServiceProtocol
    let contentCacheManager: ContentCacheManager
    let offlineSupportConfig: OfflineSupportConfig?
    let reachability: ReachabilityWrapper
    
    // MARK: - Private attributes
    
    private var enqueuedRequests: [ContentListRequest] = []
    private var activeContentListRequestHandlers: ContentListRequestHandler?
    private var activeMenusRequestHandlers: [MenusResultHandler]?
    private var actionsCache: JSON?
    private var preloadedContentListDictionary: [String: JSON]
    
    // MARK: - Init method
    
    init(contentPersister: ContentPersister,
         menuService: MenuService,
         elementService: ElementServiceInput,
         contentListService: ContentListServiceProtocol,
         contentCacheManager: ContentCacheManager,
         offlineSupportConfig: OfflineSupportConfig?,
         reachability: ReachabilityWrapper) {
        self.contentPersister = contentPersister
        self.menuService = menuService
        self.elementService = elementService
        self.contentListService = contentListService
        self.contentCacheManager = contentCacheManager
        self.offlineSupportConfig = offlineSupportConfig
        self.reachability = reachability
        self.preloadedContentListDictionary = [String: JSON]()
    }
    
    // MARK: - Default instance method
    
    static func defaultDataManager() -> ContentDataManager {
        return ContentDataManager(
            contentPersister: ContentCoreDataPersister.shared,
            menuService: MenuService(),
            elementService: ElementService(),
            contentListService: ContentListService(),
            contentCacheManager: ContentCacheManager.shared,
            offlineSupportConfig: Config.offlineSupportConfig,
            reachability: ReachabilityWrapper.shared
        )
    }
    
    // MARK: - Methods
    
    func loadMenus(forcingDownload force: Bool = false, completion: @escaping (Result<[Menu], OCMRequestError>, Bool) -> Void) {

        self.contentCacheManager.initializeCache()
        switch self.loadDataSourceForMenus(forcingDownload: force) {
        case .fromNetwork:
            if self.activeMenusRequestHandlers == nil {
                self.activeMenusRequestHandlers = [completion]
                self.menuService.getMenus { result in
                    switch result {
                    case .success(let JSON):
                        guard let jsonMenu = JSON["menus"], let menus = try? jsonMenu.compactMap(Menu.menuList) else {
                                let error = OCMRequestError(error: .unexpectedError(), status: .unknownError)
                                completion(.error(error), false)
                                return
                        }
                        if self.offlineSupportConfig == nil {
                            // Clean database every menus download when we have offlineSupport disabled
                            ContentCoreDataPersister.shared.cleanDataBase()
                            ContentCacheManager.shared.resetCache()
                        }
                        self.saveMenusAndSections(from: JSON)
                        self.activeMenusRequestHandlers?.forEach { $0(.success(menus), false) }
                    case .error(let error):
                        self.activeMenusRequestHandlers?.forEach { $0(.error(error), false) }
                    }
                    self.activeMenusRequestHandlers = nil
                }
            } else {
                self.activeMenusRequestHandlers?.append(completion)
            }
        case .fromCache(let menus):
            completion(.success(menus), true)
        case .fromMemory(let menus):
            completion(.success(menus), true)
        }
    }
    
    func loadElement(forcingDownload force: Bool = false, with identifier: String, completion: @escaping (Result<Action, NSError>) -> Void) {
        switch self.loadDataSourceForElement(forcingDownload: force, with: identifier) {
        case .fromNetwork:
            self.elementService.getElement(with: identifier, completion: { result in
                switch result {
                case .success(let action):
                    completion(.success(action))
                case .error(let error):
                    completion(.error(error))
                }
            })
        case .fromCache(let action):
            completion(.success(action))
        case .fromMemory(let action):
            completion(.success(action))
        }
    }
    
    func loadContentList(forcingDownload force: Bool, with path: String, page: Int, items: Int, completion: @escaping (Result<ContentList, NSError>) -> Void) {
        switch self.loadDataSourceForContent(forcingDownload: force, with: path, page: page, items: items) {
        case .fromNetwork:
            let request = ContentListRequest(path: path, page: page, items: items, preload: false, completion: completion)
            self.addRequestToQueue(request)
            self.performNextRequest()
        case .fromCache(let content):
            self.contentCacheManager.startCaching(section: path)
            completion(.success(content))
        case .fromMemory(let content):
            self.contentCacheManager.startCaching(section: path)
            completion(.success(content))
        }
    }
    
    func preloadContentList(with path: String, page: Int, items: Int, completion: @escaping (Result<ContentList, NSError>) -> Void) {
        let request = ContentListRequest(path: path, page: page, items: items, preload: true, completion: completion)
        self.addRequestToQueue(request)
        self.performNextRequest()
    }
    
    func loadContentList(forcingDownload force: Bool = false, matchingString searchString: String, completion: @escaping (Result<ContentList, NSError>) -> Void) {
        self.contentListService.getContentList(matchingString: searchString) { result in
            switch result {
            case .success(let json):
                guard let contentList = try? ContentList.contentList(json) else { return completion(.error(.unexpectedError())) }
                self.appendElementsCache(elements: json["elementsCache"])
                completion(.success(contentList))
            case .error(let error):
                completion(.error(error as NSError))
            }
        }
    }
    
    func loadSection(with path: String) -> Section? {
        let section = self.contentPersister.loadSectionForContent(with: path)
        return section
    }
    
    func loadSectionForAction(with path: String) -> Section? {
        let section = self.contentPersister.loadSectionForAction(with: path)
        return section
    }
    
    func loadContentVersion(with path: String) -> String? {
        let contentVersion = self.contentPersister.loadContentVersion(with: path)
        return contentVersion
    }
    
    func cancelAllRequests() {
        self.menuService.cancelActiveRequest()
        self.contentListService.cancelActiveRequest()
        self.enqueuedRequests.forEach { $0.completion(.error(NSError.unexpectedError())) } // Cancel all content list enqueued requests
        self.enqueuedRequests = [] // Delete all requests in array
    }
    
    // MARK: - Private methods
    
    private func appendElementsCache(elements: JSON?) {
        guard var currentElements = self.actionsCache?.toDictionary() else {
            self.actionsCache = elements
            return
        }
        guard let newElements = elements?.toDictionary() else { logWarn("element to dictionary is nil"); return }
        for (key, value) in newElements {
            currentElements.updateValue(value, forKey: key)
        }
        self.actionsCache = JSON(from: currentElements)
    }
    
    private func saveMenusAndSections(from json: JSON) {
        guard
            let menuJson = json["menus"]
        else {
            return
        }
        
        let menus = menuJson.compactMap { try? Menu.menuList($0) }
        self.contentPersister.save(menus: menus)
        var sectionsMenu: [[String]] = []
        for menu in menuJson {
            guard
                let menuModel = try? Menu.menuList(menu),
                let elements = menu["elements"]?.toArray() as? [NSDictionary],
                let elementsCache = json["elementsCache"]
            else {
                return
            }
            // Sections to cache
            var sections = [String]()
            // Save sections in menu
            let jsonElements = elements.map({ JSON(from: $0) })
            self.contentPersister.save(sections: jsonElements, in: menuModel.slug)
            for element in jsonElements {
                if let elementUrl = element["elementUrl"]?.toString(),
                    let elementCache = elementsCache["\(elementUrl)"] {
                    // Save each action in section
                    self.contentPersister.save(action: elementCache, in: elementUrl)
                    if let sectionPath = elementCache["render"]?["contentUrl"]?.toString() {
                        sections.append(sectionPath)
                    }
                }
            }
            sectionsMenu.append(sections)
        }
        if self.offlineSupportConfig != nil {
            // Cache sections
            // In order to prevent errors with multiple menus, we are only caching the images from the menu with more sections
            let sortSections = sectionsMenu.sorted(by: { $0.count > $1.count })
            if sortSections.indices.contains(0) {
                self.contentCacheManager.cache(sections: sortSections[0])
            }
        }
    }
    
    private func saveContentAndActions(from json: JSON, in path: String) {
        let expirationDate = json["expireAt"]?.toDate()
        let contentVersion = json["contentVersion"]?.toString()
        // Save content in path
        self.contentPersister.save(content: json, in: path, expirationDate: expirationDate, contentVersion: contentVersion)
        self.saveElementsCache(from: json)
    }
    
    private func appendContentAndActions(from json: JSON, in path: String) {
        let expirationDate = json["expireAt"]?.toDate()
        // Append contents in path
        self.contentPersister.append(content: json, in: path, expirationDate: expirationDate)
        self.saveElementsCache(from: json)
    }
    
    private func saveElementsCache(from json: JSON) {
        if let elementsCache = json["elementsCache"]?.toDictionary() {
            for (identifier, action) in elementsCache {
                self.contentPersister.save(action: JSON(from: action), with: identifier)
            }
        }
    }
    
    private func requestContentList(with path: String, page: Int, items: Int, preload: Bool) {
        let requestWithSamePath = self.enqueuedRequests.compactMap({ $0.path == path ? $0 : nil })
        let completions = requestWithSamePath.map({ $0.completion })
        self.activeContentListRequestHandlers = ContentListRequestHandler(path: path, page: page, completions: completions)
        self.contentListService.getContentList(with: path, page: page, items: items) { result in
            let completions = self.activeContentListRequestHandlers?.completions
            switch result {
            case .success(let json):
                guard let contentList = try? ContentList.contentList(json) else {
                    completions?.forEach { $0(.error(NSError.unexpectedError())) }
                    return
                }
                if self.offlineSupportConfig != nil {
                    if page > 1 {
                        self.appendContentAndActions(from: json, in: path)
                        var loadedContentList = self.cachedContent(with: path, page: page, items: items) ?? contentList
                        loadedContentList.contentVersion = contentList.contentVersion
                        completions?.forEach { $0(.success(loadedContentList)) }
                    } else {
                        if preload {
                            self.preloadedContentListDictionary[path] = json
                        } else {
                            self.saveContentAndActions(from: json, in: path)
                        }
                        self.contentCacheManager.cache(contents: contentList.contents, with: path) {
                            completions?.forEach { $0(.success(contentList)) }
                        }
                    }
                } else {
                    self.appendElementsCache(elements: json["elementsCache"])
                    completions?.forEach { $0(.success(contentList)) }
                }
            case .error(let error):
                completions?.forEach { $0(.error(error as NSError)) }
            }
            self.removeRequest(for: path, page: page)
            self.performNextRequest()
        }
    }
    
    // MARK: - Enqueued request manager methods
    
    private func addRequestToQueue(_ request: ContentListRequest) {
        self.enqueuedRequests.append(request)
        // If there is a download with the same path, append the completion block in order to return the same data
        if self.activeContentListRequestHandlers?.path == request.path, self.activeContentListRequestHandlers?.page == request.page {
            self.activeContentListRequestHandlers?.completions.append(request.completion)
        }
    }
    
    private func removeRequest(for path: String, page: Int) {
        self.enqueuedRequests = self.enqueuedRequests.compactMap({ ($0.path == path && $0.page == page) ? nil : $0 })
        self.activeContentListRequestHandlers = nil
    }
    
    private func performNextRequest() {
        if self.enqueuedRequests.count > 0 {
            if self.activeContentListRequestHandlers == nil {
                let next = self.enqueuedRequests[0]
                self.requestContentList(with: next.path, page: next.page, items: next.items, preload: next.preload)
            }
        } else {
            if self.offlineSupportConfig != nil {
                // Start caching when all content is downloaded
                self.contentCacheManager.startCaching()
            }
        }
    }
    
    // MARK: - Data source methods
    
    /// The Menu Data Source. It is fromCache when offlineSupport is enabled and we have it in db. When we force the 
    /// download, it checks internet and return cached data if there isn't internet connection.
    ///
    /// - Parameter force: If the request wants to force the download
    /// - Returns: The data source
    private func loadDataSourceForMenus(forcingDownload force: Bool) -> DataSource<[Menu]> {
        let cachedMenu = self.cachedMenus()
        if self.offlineSupportConfig != nil {
            if self.reachability.isReachable() {
                if force {
                    return .fromNetwork
                } else {
                    if cachedMenu.isEmpty {
                        return .fromNetwork
                    } else {
                        return .fromCache(cachedMenu)
                    }
                }
                
            } else if cachedMenu.count != 0 {
                return .fromCache(cachedMenu)
            }
        }
        return .fromNetwork
    }
    
    /// The Element Data Source. It is fromCache when it is in db (offlineSupport doesn't matter here, we always save actions info and try to get it from cache). When we force the download, it checks internet and return cached data if there isn't internet connection.
    ///
    /// - Parameters:
    ///   - force: If the request wants to force the download
    ///   - identifier: The identifier of the element
    /// - Returns: The data source
    private func loadDataSourceForElement(forcingDownload force: Bool, with identifier: String) -> DataSource<Action> {
        let action = self.cachedAction(from: identifier)
        if self.offlineSupportConfig != nil {
            if self.reachability.isReachable() {
                if force || action == nil {
                    return .fromNetwork
                } else if let action = action {
                    return .fromCache(action)
                }
            } else if let action = action {
                return .fromCache(action)
            }
        } else if let action = action {
            return .fromCache(action)
        }
        return .fromNetwork
    }
    
    /// The Content Data Source. It is fromCache when offlineSupport is disabled and we have it in db. When we force the download, it checks internet and return cached data if there isn't internet connection. If you have internet connection, first check if the content is expired.
    ///
    /// - Parameters:
    ///   - force: If the request wants to force the download
    ///   - path: The path of the content
    ///   - page: The page that we want to request
    ///   - items: The number of items that we want to request
    /// - Returns: The data source
    private func loadDataSourceForContent(forcingDownload force: Bool, with path: String, page: Int, items: Int) -> DataSource<ContentList> {
        if self.offlineSupportConfig != nil {
            let content = self.cachedContent(with: path, page: page, items: items)
            if let preloadedContentJSON = self.preloadedContentListDictionary[path], page == 1 {
                self.preloadedContentListDictionary[path] = nil
                self.saveContentAndActions(from: preloadedContentJSON, in: path)
                guard let content = try? ContentList.contentList(preloadedContentJSON) else { return .fromNetwork }
                return .fromMemory(content)
            } else {
                if self.reachability.isReachable() {
                    if force || content == nil {
                        return .fromNetwork
                    } else if let content = content, content.contents.count < items && page != 1 {
                        return .fromNetwork
                    } else if let content = content {
                        return .fromCache(content)
                    }
                } else if let content = content {
                    return .fromCache(content)
                }
            }
        }
        return .fromNetwork
    }
    
    // MARK: - Fetch from cache
    
    private func cachedMenus() -> [Menu] {
        return self.contentPersister.loadMenus()
    }
    
    private func cachedContent(with path: String, page: Int, items: Int) -> ContentList? {
        return self.contentPersister.loadContentList(with: path, validAt: Date(), page: page, items: items)
    }
    
    private func cachedAction(from url: String) -> Action? {
        guard let memoryCachedJson = self.actionsCache?[url] else { return self.contentPersister.loadAction(with: url) }
        return ActionFactory.action(from: memoryCachedJson, identifier: url) ?? self.contentPersister.loadAction(with: url) 
    }
}
