//
//  PathMonitorWrapper.swift
//  network_ios
//
//  Swift 封装：为 Objective-C 提供 NWPathMonitor 功能
//

import Foundation
import Network

@objcMembers
public final class PathMonitorWrapper: NSObject {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.network.ping.pathmonitor")
    private var handler: ((Bool, Bool) -> Void)?

    public override init() {
        monitor = NWPathMonitor()
        super.init()
    }

    public func startWithUpdate(_ onUpdate: @escaping (Bool, Bool) -> Void) {
        handler = onUpdate
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handler?(path.status == .satisfied, path.isExpensive)
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        handler = nil
    }
}
