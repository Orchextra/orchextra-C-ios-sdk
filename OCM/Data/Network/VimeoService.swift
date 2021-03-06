//
//  VimeoService.swift
//  OCM
//
//  Created by eduardo parada pardo on 6/10/17.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation
import GIGLibrary


protocol VimeoServiceInput {
    func getVideo(with idVideo: String, completion: @escaping (Result<Video, NSError>) -> Void)
}

struct VimeoService {
    
    let accessToken: String
    
}


// MARK: - VimeoServiceInput

extension VimeoService: VimeoServiceInput {
    
    func getVideo(with idVideo: String, completion: @escaping (Result<Video, NSError>) -> Void) {
        
        let request = Request(
            method: "GET",
            baseUrl: "https://api.vimeo.com/videos/",
            endpoint: "\(idVideo)",
            headers: ["Authorization": "Bearer \(self.accessToken)"],
            urlParams: ["fields": "files,pictures.uri"],
            verbose: true,
            standard: .basic
        )
        request.fetch(renewingSessionIfExpired: true) { response in
            switch response.status {
            case .success:
                do {
                    let json = try response.json()
                    let video = try Vimeo.parseVideo(identifier: idVideo, json: json)
                    completion(.success(video))
                } catch {
                    let error = NSError.unexpectedError("Error parsing json")
                    logError(error)
                    completion(.error(error))
                }
            default:
                let error = NSError.OCMBasicResponseErrors(response)
                logError(error.error)
                completion(.error(error.error))
            }
        }
    }
}
