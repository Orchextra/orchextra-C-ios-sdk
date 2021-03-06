//
//  ContentCoreDataPersister.swift
//  OCM
//
//  Created by José Estela on 16/11/17.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation
import CoreData
import GIGLibrary

class ContentCoreDataPersister: ContentPersister {
    
    // MARK: - Public attributes
    
    static let shared = ContentCoreDataPersister()
    
    // MARK: - Private attributes
    
    fileprivate var notification: NSObjectProtocol?
    
    fileprivate lazy var applicationDocumentsDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.count-1]
    }()
    
    fileprivate lazy var managedObjectModel: NSManagedObjectModel? = {
        guard let modelURL = Bundle.OCMBundle().url(forResource: "ContentDB", withExtension: "momd") else { return nil }
        return NSManagedObjectModel(contentsOf: modelURL)
    }()
    
    fileprivate var managedObjectContext: NSManagedObjectContext?
    
    // MARK: - Object life cycle
    
    init() {
        self.notification = NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [unowned self] _ in
            self.saveContext()
        }
        self.initDataBase()
    }
    
    init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    deinit {
        if let notification = self.notification {
            NotificationCenter.default.removeObserver(notification)
        }
    }
    
    // MARK: - Save methods
    
    func save(menus: [Menu]) {
        // First, we need to check if any of the already saved menus has been deleted
        self.managedObjectContext?.saveAfter {
            let setOfMenus = Set(menus.map({ $0.slug }))
            let setOfDBMenus = Set(self.loadAllMenus().compactMap({ $0?.identifier }))
            setOfMenus
                .subtracting(setOfDBMenus)
                .compactMap({ self.fetchMenuFromDB(with: $0) })
                .forEach({ self.managedObjectContext?.delete($0) })
        }
        // Now we add new menus
        self.managedObjectContext?.saveAfter {
            for menu in menus where self.fetchMenuFromDB(with: menu.slug) == nil {
                if let menuDB = self.createMenu() {
                    menuDB.identifier = menu.slug
                }
            }
        }
    }
    
    func save(sections: [JSON], in menu: String) {
        // First, we need to check if any of the already saved sections have been deleted
        self.managedObjectContext?.saveAfter {
            let menus = self.loadMenus().compactMap({ $0.slug == menu ? $0 : nil })
            if menus.count > 0 {
                // Sections that are not in the new json
                let setOfSections = Set(menus[0].sections.map({ $0.elementUrl }))
                let setOfDBSections = Set(sections.compactMap({ $0["elementUrl"]?.toString() }))
                // Remove from db
                setOfSections
                    .subtracting(setOfDBSections)
                    .compactMap({ self.fetchSectionFromDB(with: $0) })
                    .forEach({
                        self.fetchMenuFromDB(with: menu)?.removeFromSections($0)
                        self.managedObjectContext?.delete($0)
                    })
            }
        }
        self.managedObjectContext?.saveAfter {
            // Now, add or update the sections
            for (index, section) in sections.enumerated() {
                guard let elementUrl = section["elementUrl"]?.toString() else { logWarn("elementUrl is nil"); return }
                let fetchedSection = self.fetchSectionFromDB(with: elementUrl)
                let sectionDB = fetchedSection ?? self.createSection()
                sectionDB?.orderIndex = Int64(index)
                sectionDB?.identifier = elementUrl
                sectionDB?.value = section.stringRepresentation()
                if let sectionDB = sectionDB, fetchedSection == nil {
                    self.fetchMenuFromDB(with: menu)?.addToSections(sectionDB)
                } else if let fetchedSection = fetchedSection {
                    fetchedSection.menu = self.fetchMenuFromDB(with: menu)
                }
            }
        }
    }
    
    func save(action: JSON, in section: String) {
        self.managedObjectContext?.saveAfter {
            guard let sectionDB = self.fetchSectionFromDB(with: section), let actionDB = self.createAction() else {
                logWarn("There is an error getting section \(section) from db")
                return
            }
            actionDB.identifier = section
            actionDB.value = action.stringRepresentation()
            sectionDB.addToActions(actionDB)
        }
    }
    
    
    func save(content: JSON, in contentPath: String, expirationDate: Date?, contentVersion: String?) {
        self.managedObjectContext?.saveAfter {
            let actionDB = CoreDataObject<ActionDB>.from(self.managedObjectContext, with: "value CONTAINS %@", arguments: ["\"contentUrl\" : \"\(contentPath)\""])
            if actionDB != nil {
                if let contentDB = self.fetchContentListFromDB(with: contentPath) {
                    contentDB.elements?
                        .compactMap({ $0 as? ElementDB })
                        .forEach {
                            contentDB.removeFromElements($0)
                            self.managedObjectContext?.delete($0)
                        }
                    self.saveContentList(contentDB, with: content, in: contentPath, expirationDate: expirationDate, contentVersion: contentVersion)
                    if let contentVersion = contentVersion {
                        self.updateSection(with: contentPath, contentVersion: contentVersion)
                    }
                } else {
                    let contentDB = self.createContentList()
                    self.saveContentList(contentDB, with: content, in: contentPath, expirationDate: expirationDate, contentVersion: contentVersion)
                    actionDB?.content = contentDB
                }
            }
        }
    }
    
    func append(content: JSON, in contentPath: String, expirationDate: Date?) {
        self.managedObjectContext?.saveAndWaitAfter {
            let actionDB = CoreDataObject<ActionDB>.from(self.managedObjectContext, with: "value CONTAINS %@", arguments: ["\"contentUrl\" : \"\(contentPath)\""])
            if actionDB != nil {
                if let contentFromDB = self.fetchContentListFromDB(with: contentPath) {
                    self.saveContentList(contentFromDB, with: content, in: contentPath, expirationDate: expirationDate, contentVersion: nil)
                }
            }
        }
    }
    
    func save(action: JSON, with identifier: String) {
        self.managedObjectContext?.saveAfter {
            if let actionDB = self.fetchActionFromDB(with: identifier), let elementDB = self.fetchElement(with: identifier) {
                actionDB.value = action.stringRepresentation()
                elementDB.action = actionDB
            } else {
                let elementDB = self.fetchElement(with: identifier)
                let actionDB = self.createAction()
                actionDB?.identifier = identifier
                actionDB?.value = action.stringRepresentation()
                elementDB?.action = actionDB
            }
        }
    }
    
    // MARK: - Load methods
    
    func loadMenus() -> [Menu] {
        var menus: [Menu] = []
        self.managedObjectContext?.performAndWait {
            menus = self.loadAllMenus()
                .compactMap({ $0 })
                .compactMap({ $0.toMenu() })
        }
        return menus
    }
    
    func loadAction(with identifier: String) -> Action? {
        guard let action = self.fetchActionFromDB(with: identifier) else { return nil }
        var actionValue: String?
        self.managedObjectContext?.performAndWait {
            actionValue = action.value
        }
        guard let json = JSON.fromString(actionValue ?? "") else { return nil }
        return ActionFactory.action(from: json, identifier: identifier)
    }
    
    func loadContentList(with path: String) -> ContentList? {
        guard let contentListDB = self.fetchContentListFromDB(with: path) else { return nil }
        var contentList: ContentList?
        self.managedObjectContext?.performAndWait {
            contentList = contentListDB.toContentList()
        }
        return contentList
    }
    
    func loadContentList(with path: String, validAt date: Date, page: Int, items: Int) -> ContentList? {
        guard let contentListDB = self.fetchContentListFromDB(with: path) else { return nil }
        var contentList: ContentList?
        self.managedObjectContext?.performAndWait {
            let elements = self.fetchElementsFromDB(with: contentListDB, validAt: date as NSDate, page: page, items: items)
            contentList = contentListDB.toContentList(with: elements)
        }
        return contentList
    }
    
    func loadContentPaths() -> [String] {
        let paths = self.fetchContentListFromDB().compactMap { (content) -> String? in
            var contentPath: String?
            self.managedObjectContext?.performAndWait {
                contentPath = content?.path
            }
            return contentPath
        }
        return paths
    }
    
    func loadSectionForContent(with path: String) -> Section? {
        guard let content = self.fetchContentListFromDB(with: path) else { logWarn("fechtContent with path: \(path) is nil"); return nil }
        var sectionValue: String?
        self.managedObjectContext?.performAndWait {
            sectionValue = content.actionOwner?.section?.value
        }
        guard let json = JSON.fromString(sectionValue ?? "") else { return nil }
        return Section.parseSection(json: json)
    }
    
    func loadSectionForAction(with identifier: String) -> Section? {
        guard let action = self.fetchActionFromDB(with: identifier) else { return nil }
        var sectionValue: String?
        self.managedObjectContext?.performAndWait {
            sectionValue = action.section?.value
        }
        guard let json = JSON.fromString(sectionValue ?? "") else { return nil }
        return Section.parseSection(json: json)
    }
    
    func loadContentVersion(with path: String) -> String? {
        guard let contentList = self.fetchContentListFromDB(with: path) else { return nil }
        var contentVersion: String?
        self.managedObjectContext?.performAndWait {
            contentVersion = contentList.contentVersion
        }
        return contentVersion
    }

    // MARK: - Delete methods
    
    func cleanDataBase() {
        // Delete all data in data base
        self.managedObjectContext?.saveAfter {
            self.loadAllMenus().compactMap { $0 }.forEach { self.managedObjectContext?.delete($0) }
            self.loadAllSections().compactMap { $0 }.forEach { self.managedObjectContext?.delete($0) }
            self.loadAllElements().compactMap { $0 }.forEach { self.managedObjectContext?.delete($0) }
            self.loadAllActions().compactMap { $0 }.forEach { self.managedObjectContext?.delete($0) }
            self.loadAllContentLists().compactMap { $0 }.forEach { self.managedObjectContext?.delete($0) }
        }
    }
}

private extension ContentCoreDataPersister {
    
    // MARK: - DataBase helpers
    
    func createMenu() -> MenuDB? {
        return CoreDataObject<MenuDB>.create(insertingInto: self.managedObjectContext)
    }
    
    func fetchMenuFromDB(with slug: String) -> MenuDB? {
        return CoreDataObject<MenuDB>.from(self.managedObjectContext, with: "identifier == %@", arguments: [slug])
    }
    
    func loadAllMenus() -> [MenuDB?] {
        return CoreDataArray<MenuDB>.from(self.managedObjectContext) ?? []
    }
    
    func loadAllActions() -> [ActionDB?] {
        return CoreDataArray<ActionDB>.from(self.managedObjectContext) ?? []
    }
    
    func loadAllContentLists() -> [ContentListDB?] {
        return CoreDataArray<ContentListDB>.from(self.managedObjectContext) ?? []
    }
    
    func loadAllSections() -> [SectionDB?] {
        return CoreDataArray<SectionDB>.from(self.managedObjectContext) ?? []
    }
    
    func loadAllElements() -> [ElementDB?] {
        return CoreDataArray<ElementDB>.from(self.managedObjectContext) ?? []
    }
    
    func fetchElement(with elementUrl: String) -> ElementDB? {
        return CoreDataObject<ElementDB>.from(self.managedObjectContext, with: "elementUrl == %@", arguments: [elementUrl])
    }
    
    func updateSection(with contentPath: String, contentVersion: String) {
        guard let content = self.fetchContentListFromDB(with: contentPath) else { return }
        self.managedObjectContext?.saveAfter {
            guard let section = content.actionOwner?.section, let sectionValue = section.value, let json = JSON.fromString(sectionValue), var sectionDictionary = json.toDictionary() else { return }
            sectionDictionary["contentVersion"] = contentVersion
            section.value = JSON(from: sectionDictionary).stringRepresentation()
        }
    }
    
    func createSection() -> SectionDB? {
        return CoreDataObject<SectionDB>.create(insertingInto: self.managedObjectContext)
    }
    
    func fetchSectionFromDB(with elementUrl: String) -> SectionDB? {
        return CoreDataObject<SectionDB>.from(self.managedObjectContext, with: "identifier == %@", arguments: [elementUrl])
    }
    
    func createAction() -> ActionDB? {
        return CoreDataObject<ActionDB>.create(insertingInto: self.managedObjectContext)
    }
    
    func fetchActionFromDB(with identifier: String) -> ActionDB? {
        return CoreDataObject<ActionDB>.from(self.managedObjectContext, with: "identifier == %@", arguments: [identifier])
    }
    
    func createContentList() -> ContentListDB? {
        return CoreDataObject<ContentListDB>.create(insertingInto: self.managedObjectContext)
    }
    
    func fetchContentListFromDB(with path: String) -> ContentListDB? {
        return CoreDataObject<ContentListDB>.from(self.managedObjectContext, with: "path == %@", arguments: [path])
    }
    
    func fetchContentListFromDB() -> [ContentListDB?] {
        return CoreDataArray<ContentListDB>.from(self.managedObjectContext) ?? []
    }
    
    func createElement() -> ElementDB? {
        return CoreDataObject<ElementDB>.create(insertingInto: self.managedObjectContext)
    }
    
    func fetchElementsFromDB(with contentList: ContentListDB, validAt date: NSDate, page: Int, items: Int) -> [ElementDB]? {
        let firstIndex = (page - 1) * items
        let lastIndex = (page * items) - 1
        return CoreDataArray<ElementDB>.from(self.managedObjectContext, with: "contentList == %@ AND orderIndex >= %@ AND orderIndex <= %@ AND (scheduleDates.@count == 0 OR ((ANY scheduleDates.start <= %@) AND (ANY scheduleDates.end >= %@)))", arguments: [contentList, firstIndex, lastIndex, date, date])
    }

    func createScheduleDate() -> ScheduleDateDB? {
        return CoreDataObject<ScheduleDateDB>.create(insertingInto: self.managedObjectContext)
    }
    
    private func saveContentList(_ contentListDB: ContentListDB?, with content: JSON, in contentPath: String, expirationDate: Date?, contentVersion: String?) {
        guard let contentListDB = contentListDB else { return }
        let nextOrderIndex = contentListDB.elements?.count ?? 0
        let contentList = try? ContentList.contentList(content)
        if let contentVersion = contentVersion {
            contentListDB.contentVersion = contentVersion
        }
        contentListDB.path = contentPath
        contentListDB.expirationDate = expirationDate as NSDate?
        contentListDB.slug = content["content.slug"]?.toString()
        contentListDB.type = content["content.type"]?.toString()
        contentListDB.tags = content["content.tags"]?.toString()?.data(using: .utf8) as NSData?
        contentListDB.layout = content["content.layout"]?.stringRepresentation()
        guard let contents = contentList?.contents else { return }
        for (index, content) in contents.enumerated() {
            let orderIndex = index + nextOrderIndex
            let elementsFromDB = contentListDB.elements?.compactMap({ $0 as? ElementDB })
            if let element = elementsFromDB?.first(where: {$0.slug == content.slug}) {
                self.elementFromContent(element: element, content: content, orderIndex: orderIndex)
            } else {
                if let element = self.createElement() {
                    self.elementFromContent(element: element, content: content, orderIndex: orderIndex)
                    contentListDB.addToElements(element)
                }
            }
        }
    }
    
    func elementFromContent(element: ElementDB, content: Content, orderIndex: Int) {
        element.orderIndex = Int64(orderIndex)
        element.name = content.name
        element.slug = content.slug
        element.elementUrl = content.elementUrl
        element.tags = NSKeyedArchiver.archivedData(withRootObject: content.tags) as NSData?
        element.sectionView = NSKeyedArchiver.archivedData(withRootObject: content.media) as NSData?
        if let customProperties = content.customProperties, !customProperties.isEmpty {
            element.customProperties = NSKeyedArchiver.archivedData(withRootObject: customProperties) as NSData?
        }
        if let dates = content.dates {
            dates.forEach { date in
                guard let scheduleDate = self.createScheduleDate() else { return }
                scheduleDate.start = date.start as NSDate?
                scheduleDate.end = date.end as NSDate?
                element.addToScheduleDates(scheduleDate)
            }
        }
    }
    
    // MARK: - Core Data Saving support
    
    func saveContext() {
        guard let managedObjectContext = self.managedObjectContext else { logWarn("managedObjectContext is nil"); return }
        managedObjectContext.perform {
            if managedObjectContext.hasChanges {
                managedObjectContext.save()
            }
        }
    }
    
    func initDataBase() {
        guard let managedObjectModel = self.managedObjectModel else { logWarn("managedObjectModel is nil"); return }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        let url = self.applicationDocumentsDirectory.appendingPathComponent("ContentDB.sqlite")
        let options = [ NSInferMappingModelAutomaticallyOption: true,
                        NSMigratePersistentStoresAutomaticallyOption: true]
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: options)
        } catch let error {
            print(error)
        }
        self.managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.managedObjectContext?.persistentStoreCoordinator = coordinator
        self.managedObjectContext?.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

extension NSManagedObjectContext {
    
    func saveAfter(_ completion: @escaping () -> Void) {
        self.perform {
            completion()
            if self.hasChanges {
                self.save()
            }
        }
    }
    
    func saveAndWaitAfter(_ completion: @escaping () -> Void) {
        self.performAndWait {
            completion()
            if self.hasChanges {
                self.save()
            }
        }
    }
}
