//
//  DeliveredNotificationManager.swift
//  MindBox
//
//  Created by Maksim Kazachkov on 20.02.2021.
//  Copyright © 2021 Mikhail Barilov. All rights reserved.
//

import Foundation
import UserNotifications


final class DeliveredNotificationManager {
    
    @Injected private var persistenceStorage: PersistenceStorage
    @Injected private var configurationStorage: ConfigurationStorage
    
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "MindBox-DeliveredNotificationQueue"
        return queue
    }()
    
    private let semaphore = DispatchSemaphore(value: 0)
    
    private let timeout: TimeInterval = 5.0
    
    private let mindBoxIdentifireKey = "uniqueKey"

    @discardableResult
    func track(request: UNNotificationRequest) throws -> Bool {
        guard let userInfo = (request.content.mutableCopy() as? UNMutableNotificationContent)?.userInfo else {
            throw DeliveredNotificationManagerError.unableToFetchUserInfo
        }
        guard userInfo[mindBoxIdentifireKey] != nil else {
            Log("Push notification is not from MindBox")
                .inChanel(.notification).withType(.info).make()
            return false
        }
        Log("Track started")
            .inChanel(.notification).withType(.info).make()
        if let configuration = persistenceStorage.configuration {
            configurationStorage.setConfiguration(configuration)
        }
        let parseEventOperation = ParseEventOperation(userInfo: userInfo)
        parseEventOperation.onCompleted = { [weak self] result in
            guard let self = self else {
                return
            }
            do {
                let event = try result.get()
                self.track(event: event)
            } catch {
                Log("Track failed with error: \(error.localizedDescription)")
                    .inChanel(.notification).withType(.info).make()
            }
        }
        queue.addOperations([parseEventOperation], waitUntilFinished: false)
        switch semaphore.wait(wallTimeout: .now() + timeout) {
        case .success:
            Log("Track succeeded")
                .inChanel(.notification).withType(.info).make()
            return true
        case .timedOut:
            queue.cancelAllOperations()
            Log("Track time expired")
                .inChanel(.notification).withType(.info).make()
            return false
        }
    }
    
    private func track(event: Event) {
        let isConfigurationSet = persistenceStorage.configuration != nil
        let saveOperation = SaveEventOperation(event: event)
        saveOperation.onCompleted = { [weak self] result in
            if !isConfigurationSet {
                self?.semaphore.signal()
            }
        }
        let deliverOperation = DeliveryOperation(event: event)
        deliverOperation.addDependency(saveOperation)
        deliverOperation.onCompleted = { [weak self] (_, _) in
            self?.semaphore.signal()
        }
        Log("Started DeliveryOperation")
            .inChanel(.notification).withType(.info).make()
        var operations: [Operation] = [saveOperation]
        if isConfigurationSet {
            operations.append(deliverOperation)
        }
        self.queue.addOperations(operations, waitUntilFinished: false)
    }
    
}
