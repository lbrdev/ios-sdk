//
//  MindBox.swift
//  MindBox
//
//  Created by Mikhail Barilov on 12.01.2021.
//  Copyright © 2021 Mikhail Barilov. All rights reserved.
//

import Foundation
import UIKit

public class MindBox {
    
    /// Singleton value for interaction with sdk
    /// - Warning: All calls which use DI containers objects, mast go through `MindBox.shared`
    public static let shared = MindBox()
    
    // MARK: - Elements
    private var persistenceStorage: PersistenceStorage?
    private var utilitiesFetcher: UtilitiesFetcher?
    private var guaranteedDeliveryManager: GuaranteedDeliveryManager?
    private var notificationStatusProvider: UNAuthorizationStatusProviding?
    private var databaseRepository: MBDatabaseRepository?
        
    /// Internal process controller
    var coreController: CoreController?
    var container: DependencyContainer? 
    
    /// Delegate for sending events
    weak var delegate: MindBoxDelegate? {
        didSet {
            guard let error = initError else { return }
            delegate?.mindBox(self, failedWithError: error)
        }
    }
    
    // MARK: - MindBox
    
    /// This function starting initialization case using `configuration`.
    /// - Parameter configuration: MBConfiguration struct with configuration
    public func initialization(configuration: MBConfiguration) {
        coreController?.initialization(configuration: configuration)
    }
    
    private var observeTokens: [UUID] = []
            
    public func getDeviceUUID(_ completion: @escaping (String) -> Void) {
        if let value = persistenceStorage?.deviceUUID {
            completion(value)
        } else {
            observe(value: self.persistenceStorage?.deviceUUID, with: completion)
        }
    }
    
    /// - Returns: apnsToken sent to the analytics system
    public func getAPNSToken(_ completion: @escaping (String) -> Void) {
        if let value = persistenceStorage?.apnsToken {
            completion(value)
        } else {
            observe(value: self.persistenceStorage?.apnsToken, with: completion)
        }
    }
    
    private func observe(value: @escaping @autoclosure () -> String?, with completion: @escaping (String)-> Void) {
        let token = UUID()
        persistenceStorage?.onDidChange = { [weak self] in
            guard let value = value(), let index = self?.observeTokens.firstIndex(of: token) else {
                return
            }
            self?.observeTokens.remove(at: index)
            completion(value)
        }
        observeTokens.append(token)
    }
    
    /// - Returns: version from bundle
    public var sdkVersion: String {
        utilitiesFetcher?.sdkVersion ?? "unknown"
    }
    
    /// Method for keeping apnsTokenUpdate actuality
    public func apnsTokenUpdate(token: String) {
        if let persistenceAPNSToken = persistenceStorage?.apnsToken {
            guard persistenceAPNSToken != token else {
                return
            }
            coreController?.apnsTokenDidUpdate(token: token)
        } else {
            coreController?.apnsTokenDidUpdate(token: token)
        }
    }
    
    public func notificationsRequestAuthorization(granted: Bool) {
        coreController?.checkNotificationStatus(granted: granted)
    }
    
    @discardableResult
    public func pushDelivered(request: UNNotificationRequest) -> Bool {
        coreController?.checkNotificationStatus()
        guard let container = container else { return false }
        let traker = DeliveredNotificationManager(
            persistenceStorage: container.persistenceStorage,
            databaseRepository: container.databaseRepository,
            eventRepository: container.instanceFactory.makeEventRepository()
        )
        do {
            return try traker.track(request: request)
        } catch {
            Log("Track UNNotificationRequest failed with error: \(error)")
                .category(.notification).level(.error).make()
            return false
        }
    }
    
    @discardableResult
    public func pushDelivered(uniqueKey: String) -> Bool {
        coreController?.checkNotificationStatus()
        guard let container = container else { return false }
        let traker = DeliveredNotificationManager(
            persistenceStorage: container.persistenceStorage,
            databaseRepository: container.databaseRepository,
            eventRepository: container.instanceFactory.makeEventRepository()
        )
        do {
            return try traker.track(uniqueKey: uniqueKey)
        } catch {
            Log("Track UNNotificationRequest failed with error: \(error)")
                .category(.notification).level(.error).make()
            return false
        }
    }
    
    public func pushClicked(uniqueKey: String, buttonUniqueKey: String? = nil) {
        let trackMobilePushClick = TrackClick(messageUniqueKey: uniqueKey, buttonUniqueKey: buttonUniqueKey)
        let event = Event(type: .trackClick, body: BodyEncoder(encodable: trackMobilePushClick).body)
        try? databaseRepository?.create(event: event)
    }
    
    @available(iOS 13.0, *)
    public func registerBGTasks() {
        guard let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] else {
            return
        }
        guard let appGDRefreshIdentifier = identifiers.first(where: { $0.contains("GDAppRefresh") }) else  {
            return
        }
        guard let appGDProcessingIdentifier = identifiers.first(where: { $0.contains("GDAppProcessing") }) else  {
            return
        }
        guard let appDBCleanProcessingIdentifier = identifiers.first(where: { $0.contains("DBCleanAppProcessing") }) else  {
            return
        }
        guaranteedDeliveryManager?.backgroundTaskManager.registerBGTasks(
            appGDRefreshIdentifier: appGDRefreshIdentifier,
            appGDProcessingIdentifier: appGDProcessingIdentifier,
            appDBCleanProcessingIdentifire: appDBCleanProcessingIdentifier
        )
    }
    
    public func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guaranteedDeliveryManager?.backgroundTaskManager.application(application, performFetchWithCompletionHandler: completionHandler)
    }
    
    private var initError: Error?
    
    private init() {
        do {
            let container = try DependencyProvider()
            self.container = container
            assembly(with: container)
        } catch {
            initError = error
        }
        persistenceStorage?.storeToFileBackgroundExecution()
    }
    
    func assembly(with container: DependencyContainer) {
        persistenceStorage = container.persistenceStorage
        utilitiesFetcher = container.utilitiesFetcher
        guaranteedDeliveryManager = container.guaranteedDeliveryManager
        notificationStatusProvider = container.authorizationStatusProvider
        databaseRepository = container.databaseRepository
        
        coreController = CoreController(
            persistenceStorage: container.persistenceStorage,
            utilitiesFetcher: container.utilitiesFetcher,
            notificationStatusProvider: container.authorizationStatusProvider,
            databaseRepository: container.databaseRepository,
            guaranteedDeliveryManager: container.guaranteedDeliveryManager
        )
    }
    
}
