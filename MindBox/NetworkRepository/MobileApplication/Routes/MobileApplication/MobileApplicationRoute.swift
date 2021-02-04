//
//  MobileApplication.swift
//  MindBox
//
//  Created by Maksim Kazachkov on 02.02.2021.
//  Copyright © 2021 Mikhail Barilov. All rights reserved.
//

import Foundation

enum MobileApplicationRoute: Route {
    
    case installed(MobileApplicationInstalledWrapper), infoUpdated(MobileApplicationInfoUpdatedWrapper)
    
    var method: HTTPMethod {
        switch self {
        case .installed,
             .infoUpdated:
            return .post
        }
    }
    
    var path: String {
        switch self {
        case .installed,
             .infoUpdated:
            return "/v3/operations/sync"
        }
    }
    
    var headers: HTTPHeaders? {
        return nil
    }
    
    var queryParameters: QueryParameters {
        switch self {
        case let .installed(wrapper):
            let query = wrapper.query
            return [
                "endpointId": query.endpointId,
                "operation": query.operation,
                "deviceUUID": query.deviceUUID
            ]
            
        case let .infoUpdated(wrapper):
            let query = wrapper.query
            return [
                "endpointId": query.endpointId,
                "operation": query.operation,
                "deviceUUID": query.deviceUUID
            ]
        }
    }
    
    var body: Data? {
        switch self {
        case let .installed(wrapper):
            return try? JSONEncoder().encode(wrapper.body)
        case let .infoUpdated(wrapper):
            return try? JSONEncoder().encode(wrapper.body)
        }
    }
    
    
}