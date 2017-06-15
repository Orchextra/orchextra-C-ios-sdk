//
//  ImageCacheManager.swift
//  OCM
//
//  Created by Jerilyn Goncalves on 07/06/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import UIKit

/// Error for image caching
enum ImageCacheError: Error {
    
    case invalidUrl
    case retryLimitExceeded
    case downloadFailed
    case cachingFailed
    case cachingCancelled
    case unknown
    
    func description() -> String {
        switch self {
        case .invalidUrl:
            return "The provided URL is invalid, unable to download expected image"
        case .retryLimitExceeded:
            return "Unable to download expected image after 3 attempts"
        case .downloadFailed:
            return "Unable to download expected image"
        case .cachingCancelled:
            return "Caching process aborted, unable to cache the expected image"
        case .cachingFailed:
            return "Unable to cache on disk the expected image"
        case .unknown:
            return "Unable to cache image, unknown error"
        }
    }
}

/// Image caching on completion receives the expected image or an error
typealias ImageCacheCompletion = (UIImage?, ImageCacheError?) -> Void

/**
 Handles image caching, responsible for:
 
 - ...
 - !!! Document
 */
class ImageCacheManager {
        
    // MARK: Private properties
    private var cachedImages: Set<CachedImage>
    private var backgroundDownloadManager: BackgroundDownloadManager

    private var downloadPaused: Bool = false
    private let downloadLimit: Int = 3
    private var downloadsInProgress: Set<CachedImage>
    private var lowPriorityQueue: [CachedImage]
    private var highPriorityQueue: [CachedImage]
    
    // MARK: - Initializers
    
    init() {
        self.cachedImages = []
        self.lowPriorityQueue = []
        self.highPriorityQueue = []
        self.downloadsInProgress = []
        self.backgroundDownloadManager = BackgroundDownloadManager()
        self.backgroundDownloadManager.configure(backgroundSessionCompletionHandler: Config.backgroundSessionCompletionHandler)
    }
    
    // MARK: - Public methods

    /**
     Caches an image, retrieving it from disk if already cached or downloading if not.
     
     - parameter imagePath: `String` representation of the image's `URL`.
     - parameter associatedContent: `Content` associated to the cached image, evaluated for garbage collection.
     - parameter priority: Caching priority,`.high` only for those that will be shown on display.
     - parameter completion: Completion handler to fire when caching is completed, reciving the expected image or an error.
     */
    func cachedImage(for imagePath: String, with associatedContent: Content, priority: ImageCachePriority, completion: ImageCacheCompletion?) {
        
        // Check if it exists already
        guard let cachedImage = self.cachedImage(with: imagePath) else {
            // If it doesn't exist, then download
            let cachedImage = CachedImage(imagePath: imagePath, location: .none, priority: .low, associatedContent: associatedContent, completion: completion)
            self.enqueueForDownload(cachedImage)
            return
        }
        
        if let location = cachedImage.location {
            if let image = self.image(for: location) {
                // If it exists, associate content and return image
                cachedImage.associate(with: associatedContent)
                cachedImage.complete(image: image, error: .none)
            } else {
                // If it exists but can't be loaded, return error
                cachedImage.complete(image: .none, error: .unknown)
            }
        } else {
            // If it's being downloaded, associate content and add it's completion handler
            cachedImage.associate(with: associatedContent)
            if let completionHandler = completion {
                cachedImage.addCompletionHandler(completion: completionHandler)
            }
        }
        
    }

    /**
     Pauses the image caching process.
     All image downloads are paused, except those with a high a priority that were already in progress.
     */
    func pauseCaching() {
        self.downloadPaused = true
        for download in self.downloadsInProgress where download.priority == .low {
            // Only pause active downloads that have a low priority
            self.backgroundDownloadManager.pauseDownload(downloadPath: download.imagePath)
        }
    }
    
    /**
     Resumes the image caching process.
     All image downloads that were paused are resumed in the expected order.
     */
    func resumeCaching() {
        self.downloadPaused = false
        if self.downloadsInProgress.count > 0 {
            // Resume paused downloads if any
            self.backgroundDownloadManager.resumeDownloads()
        } else {
            // If no downloads are paused, dequeue those that are pending for download
            self.dequeueForDownload()
        }
    }
    
    /**
     Cancels the image caching process.
     Completion handlers for images being cached are fired with a cancellation error.
     */
    func cancelCaching() {
        self.backgroundDownloadManager.cancelDownloads()
        
        let downloads  = self.lowPriorityQueue + self.highPriorityQueue + self.downloadsInProgress
        for download in downloads {
            download.complete(image: .none, error: .cachingCancelled)
        }
        self.lowPriorityQueue.removeAll()
        self.highPriorityQueue.removeAll()
        self.downloadsInProgress.removeAll()
    }

//    func clean() {
//
//        // TODO: Perform garbage collection
//    }
    
    // MARK: - Private methods
    
    // MARK: Download helpers
    
    private func downloadImageForCaching(cachedImage: CachedImage) {
        
        self.backgroundDownloadManager.startDownload(downloadPath: cachedImage.imagePath, completion: { (location, error) in
            
            if error == .none, let location = location, let image = self.image(for: location) {
                self.downloadsInProgress.remove(cachedImage)
                self.cachedImages.update(with: cachedImage)
                cachedImage.cache(location: location)
                cachedImage.complete(image: image, error: .none)
                if !self.downloadPaused { self.dequeueForDownload() }
            } else {
                self.downloadsInProgress.remove(cachedImage)
                cachedImage.complete(image: .none, error: self.translateError(error: error))
            }
        })
    }
    
    // MARK: Download queues helpers 
    
    private func enqueueForDownload(_ cachedImage: CachedImage) {
    
        switch cachedImage.priority {
        case .low:
            self.enqueueLowPriorityDownload(cachedImage)
            break
        case .high:
            self.enqueueHighPriorityDownload(cachedImage)
            break
        }
    }
    
    private func dequeueForDownload() {
        
        guard self.dequeueHighPriorityDownload() else {
            _ = self.dequeueLowPriorityDownload()
            return
        }
    }
    
    private func enqueueLowPriorityDownload(_ cachedImage: CachedImage) {
        
        if self.downloadsInProgress.count < self.downloadLimit {
            // Download if there's place on the download queue
            self.downloadsInProgress.insert(cachedImage)
            self.downloadImageForCaching(cachedImage: cachedImage)
        } else {
            // Add to low priority download queue
            self.lowPriorityQueue.append(cachedImage)
        }
    }
    
    private func dequeueLowPriorityDownload() -> Bool {
        
        if let download = self.highPriorityQueue.first {
            self.lowPriorityQueue.remove(at: 0)
            self.enqueueForDownload(download)
            return true
        }
        return false
    }
    
    private func enqueueHighPriorityDownload(_ cachedImage: CachedImage) {
        
        if let lowPriorityDownload = self.lowPriorityDownloadInProgress() {
            // If there's a low priority download in progress
            // Pause low priority download and move to the low priority queue
            self.backgroundDownloadManager.pauseDownload(downloadPath: lowPriorityDownload.imagePath)
            self.downloadsInProgress.remove(lowPriorityDownload)
            self.lowPriorityQueue.append(lowPriorityDownload)
            // Start high priority download
            self.downloadsInProgress.insert(cachedImage)
            self.downloadImageForCaching(cachedImage: cachedImage)
        } else {
            // If there's only high priority downloads in progress
            if self.downloadsInProgress.count < self.downloadLimit {
                // Download if there's place on the download queue
                self.downloadsInProgress.insert(cachedImage)
                self.downloadImageForCaching(cachedImage: cachedImage)
            } else {
                // Add to high priority download queue
                self.highPriorityQueue.append(cachedImage)
            }
        }
    }
    
    private func dequeueHighPriorityDownload() -> Bool {
        
        if let download = self.highPriorityQueue.first {
            self.highPriorityQueue.remove(at: 0)
            self.enqueueForDownload(download)
            return true
        }
        return false
    }
    
    // MARK: Handy helpers
    
    private func lowPriorityDownloadInProgress() -> CachedImage? {
        
        let downloadInProgress = self.downloadsInProgress.first { (download) -> Bool in
            download.priority == .low
        }
        return downloadInProgress
    }
    
    private func cachedImage(with imagePath: String) -> CachedImage? {
        
        return self.cachedImages.first(where: { (cachedImage) -> Bool in
            return cachedImage.imagePath == imagePath
        })
    }
    
    private func image(for location: URL) -> UIImage? {
        
        guard let data = try? Data(contentsOf: location) else { return .none }
        return UIImage(data: data)
    }
    
    private func translateError(error: BackgroundDownloadError?) -> ImageCacheError {
        
        guard let error = error else {
            return .cachingFailed
        }
        switch error {
        case .invalidUrl:
            return .invalidUrl
        case .retryLimitExceeded:
            return .retryLimitExceeded
        case .unknown:
            return .downloadFailed
        }
    }

}