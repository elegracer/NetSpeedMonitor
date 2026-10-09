import Darwin
import Foundation

struct NetworkStatisticsRouteSample: Equatable {
    let sourceID: Int
    let interfaceName: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct NetworkTrafficRate: Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

enum NetworkStatisticsRouteParser {
    static func isIPRoute(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let family = Int32(data[data.startIndex + 1])
        switch family {
        case AF_INET:
            return data.count >= MemoryLayout<sockaddr_in>.size
        case AF_INET6:
            return data.count >= MemoryLayout<sockaddr_in6>.size
        default:
            return false
        }
    }

    static func shouldInclude(flags: UInt32) -> Bool {
        flags & UInt32(RTF_WASCLONED) == 0
    }

    static func shouldRemoveSource(destination: Data?, flags: UInt32?) -> Bool {
        if let destination, !isIPRoute(destination) {
            return true
        }
        if let flags, !shouldInclude(flags: flags) {
            return true
        }
        return false
    }
}

struct NetworkStatisticsRateCalculator {
    private var previousSamples: [Int: NetworkStatisticsRouteSample] = [:]
    private var previousTimestamp: TimeInterval?

    mutating func update(
        samples: [NetworkStatisticsRouteSample],
        timestamp: TimeInterval
    ) -> [String: NetworkTrafficRate] {
        let interval = previousTimestamp.map { timestamp - $0 } ?? 0
        var totals: [String: (received: UInt64, sent: UInt64)] = [:]

        for sample in samples {
            var total = totals[sample.interfaceName] ?? (0, 0)
            if interval > 0,
               let previous = previousSamples[sample.sourceID],
               previous.interfaceName == sample.interfaceName {
                total.received = addingWithoutOverflow(
                    total.received,
                    counterDelta(current: sample.receivedBytes, previous: previous.receivedBytes)
                )
                total.sent = addingWithoutOverflow(
                    total.sent,
                    counterDelta(current: sample.sentBytes, previous: previous.sentBytes)
                )
            }
            totals[sample.interfaceName] = total
        }

        previousSamples = Dictionary(uniqueKeysWithValues: samples.map { ($0.sourceID, $0) })
        previousTimestamp = timestamp

        return totals.mapValues { total in
            guard interval > 0 else {
                return NetworkTrafficRate(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
            }
            return NetworkTrafficRate(
                downloadBytesPerSecond: Double(total.received) / interval,
                uploadBytesPerSecond: Double(total.sent) / interval
            )
        }
    }

    mutating func reset() {
        previousSamples.removeAll(keepingCapacity: false)
        previousTimestamp = nil
    }

    private func counterDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private func addingWithoutOverflow(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}

private typealias NStatManagerRef = UnsafeMutableRawPointer
private typealias NStatSourceRef = UnsafeMutableRawPointer

private final class NetworkStatisticsSymbols {
    typealias ManagerCreate = @convention(c) (
        CFAllocator?,
        DispatchQueue,
        @escaping @convention(block) (NStatSourceRef) -> Void
    ) -> NStatManagerRef?
    typealias ManagerDestroy = @convention(c) (NStatManagerRef) -> Void
    typealias ManagerAddAllRoutes = @convention(c) (NStatManagerRef) -> Void
    typealias ManagerQueryAllSources = @convention(c) (
        NStatManagerRef,
        @escaping @convention(block) () -> Void
    ) -> Void
    typealias SourceDictionaryBlock = @convention(c) (
        NStatSourceRef,
        @escaping @convention(block) (CFDictionary) -> Void
    ) -> Void
    typealias SourceRemovedBlock = @convention(c) (
        NStatSourceRef,
        @escaping @convention(block) () -> Void
    ) -> Void
    typealias SourceQuery = @convention(c) (NStatSourceRef) -> Void
    typealias SourceRemove = @convention(c) (NStatSourceRef) -> Void

    let handle: UnsafeMutableRawPointer
    let managerCreate: ManagerCreate
    let managerDestroy: ManagerDestroy
    let managerAddAllRoutes: ManagerAddAllRoutes
    let managerQueryAllSources: ManagerQueryAllSources
    let sourceSetDescriptionBlock: SourceDictionaryBlock
    let sourceSetCountsBlock: SourceDictionaryBlock
    let sourceSetRemovedBlock: SourceRemovedBlock
    let sourceQueryDescription: SourceQuery
    let sourceQueryCounts: SourceQuery
    let sourceRemove: SourceRemove
    let keyRouteDestination: CFString
    let keyRouteFlags: CFString
    let keyInterface: CFString
    let keyReceivedBytes: CFString
    let keySentBytes: CFString

    init(
        handle: UnsafeMutableRawPointer,
        managerCreate: @escaping ManagerCreate,
        managerDestroy: @escaping ManagerDestroy,
        managerAddAllRoutes: @escaping ManagerAddAllRoutes,
        managerQueryAllSources: @escaping ManagerQueryAllSources,
        sourceSetDescriptionBlock: @escaping SourceDictionaryBlock,
        sourceSetCountsBlock: @escaping SourceDictionaryBlock,
        sourceSetRemovedBlock: @escaping SourceRemovedBlock,
        sourceQueryDescription: @escaping SourceQuery,
        sourceQueryCounts: @escaping SourceQuery,
        sourceRemove: @escaping SourceRemove,
        keyRouteDestination: CFString,
        keyRouteFlags: CFString,
        keyInterface: CFString,
        keyReceivedBytes: CFString,
        keySentBytes: CFString
    ) {
        self.handle = handle
        self.managerCreate = managerCreate
        self.managerDestroy = managerDestroy
        self.managerAddAllRoutes = managerAddAllRoutes
        self.managerQueryAllSources = managerQueryAllSources
        self.sourceSetDescriptionBlock = sourceSetDescriptionBlock
        self.sourceSetCountsBlock = sourceSetCountsBlock
        self.sourceSetRemovedBlock = sourceSetRemovedBlock
        self.sourceQueryDescription = sourceQueryDescription
        self.sourceQueryCounts = sourceQueryCounts
        self.sourceRemove = sourceRemove
        self.keyRouteDestination = keyRouteDestination
        self.keyRouteFlags = keyRouteFlags
        self.keyInterface = keyInterface
        self.keyReceivedBytes = keyReceivedBytes
        self.keySentBytes = keySentBytes
    }

    deinit {
        dlclose(handle)
    }

    static func load() -> NetworkStatisticsSymbols? {
        let path = "/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }

        func function<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        func key(_ name: String) -> CFString? {
            dlsym(handle, name)?.load(as: CFString.self)
        }

        guard
            let managerCreate = function("NStatManagerCreate", as: ManagerCreate.self),
            let managerDestroy = function("NStatManagerDestroy", as: ManagerDestroy.self),
            let managerAddAllRoutes = function("NStatManagerAddAllRoutes", as: ManagerAddAllRoutes.self),
            let managerQueryAllSources = function("NStatManagerQueryAllSources", as: ManagerQueryAllSources.self),
            let sourceSetDescriptionBlock = function(
                "NStatSourceSetDescriptionBlock",
                as: SourceDictionaryBlock.self
            ),
            let sourceSetCountsBlock = function("NStatSourceSetCountsBlock", as: SourceDictionaryBlock.self),
            let sourceSetRemovedBlock = function("NStatSourceSetRemovedBlock", as: SourceRemovedBlock.self),
            let sourceQueryDescription = function("NStatSourceQueryDescription", as: SourceQuery.self),
            let sourceQueryCounts = function("NStatSourceQueryCounts", as: SourceQuery.self),
            let sourceRemove = function("NStatSourceRemove", as: SourceRemove.self),
            let keyRouteDestination = key("kNStatSrcKeyRouteDestination"),
            let keyRouteFlags = key("kNStatSrcKeyRouteFlags"),
            let keyInterface = key("kNStatSrcKeyInterface"),
            let keyReceivedBytes = key("kNStatSrcKeyRxBytes"),
            let keySentBytes = key("kNStatSrcKeyTxBytes")
        else {
            dlclose(handle)
            return nil
        }

        return NetworkStatisticsSymbols(
            handle: handle,
            managerCreate: managerCreate,
            managerDestroy: managerDestroy,
            managerAddAllRoutes: managerAddAllRoutes,
            managerQueryAllSources: managerQueryAllSources,
            sourceSetDescriptionBlock: sourceSetDescriptionBlock,
            sourceSetCountsBlock: sourceSetCountsBlock,
            sourceSetRemovedBlock: sourceSetRemovedBlock,
            sourceQueryDescription: sourceQueryDescription,
            sourceQueryCounts: sourceQueryCounts,
            sourceRemove: sourceRemove,
            keyRouteDestination: keyRouteDestination,
            keyRouteFlags: keyRouteFlags,
            keyInterface: keyInterface,
            keyReceivedBytes: keyReceivedBytes,
            keySentBytes: keySentBytes
        )
    }
}

final class NetworkStatisticsTrafficSource {
    typealias Completion = ([String: NetworkTrafficRate]?) -> Void

    private struct SourceState {
        var isIPRoute = false
        var shouldInclude = true
        var interfaceName: String?
        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var hasCounts = false
        var removalRequested = false
    }

    private let callbackQueue = DispatchQueue(
        label: "com.elegracer.NetSpeedMonitor.network-statistics",
        qos: .utility
    )
    private let symbols: NetworkStatisticsSymbols?
    private var manager: NStatManagerRef?
    private var sources: [Int: SourceState] = [:]
    private var rateCalculator = NetworkStatisticsRateCalculator()
    private var queryInFlight = false
    private var pendingCompletions: [Completion] = []

    init() {
        symbols = NetworkStatisticsSymbols.load()
        guard let symbols else { return }

        callbackQueue.sync {
            manager = symbols.managerCreate(kCFAllocatorDefault, callbackQueue) { [weak self] source in
                self?.handleNewSource(source)
            }
            if let manager {
                symbols.managerAddAllRoutes(manager)
            }
        }
    }

    var isAvailable: Bool {
        callbackQueue.sync { manager != nil }
    }

    func requestUpdate(completion: @escaping Completion) {
        callbackQueue.async { [weak self] in
            guard let self, let symbols = self.symbols, let manager = self.manager else {
                completion(nil)
                return
            }
            self.pendingCompletions.append(completion)
            guard !self.queryInFlight else { return }

            self.queryInFlight = true
            symbols.managerQueryAllSources(manager) { [weak self] in
                self?.callbackQueue.async {
                    self?.finishQuery()
                }
            }
        }
    }

    func reset() {
        callbackQueue.async { [weak self] in
            self?.rateCalculator.reset()
        }
    }

    func stop() {
        callbackQueue.sync {
            guard let manager, let symbols else { return }
            symbols.managerDestroy(manager)
            self.manager = nil
            sources.removeAll(keepingCapacity: false)
            rateCalculator.reset()
            queryInFlight = false
            let completions = pendingCompletions
            pendingCompletions.removeAll(keepingCapacity: false)
            completions.forEach { $0(nil) }
        }
    }

    private func handleNewSource(_ source: NStatSourceRef) {
        guard let symbols else { return }
        let sourceID = Int(bitPattern: source)
        sources[sourceID] = SourceState()

        symbols.sourceSetDescriptionBlock(source) { [weak self] dictionary in
            self?.handleDescription(sourceID: sourceID, sourceRef: source, dictionary: dictionary)
        }
        symbols.sourceSetCountsBlock(source) { [weak self] dictionary in
            self?.handleCounts(sourceID: sourceID, dictionary: dictionary)
        }
        symbols.sourceSetRemovedBlock(source) { [weak self] in
            self?.sources.removeValue(forKey: sourceID)
        }
        symbols.sourceQueryDescription(source)
        symbols.sourceQueryCounts(source)
    }

    private func handleDescription(
        sourceID: Int,
        sourceRef: NStatSourceRef,
        dictionary: CFDictionary
    ) {
        guard let symbols, var source = sources[sourceID] else { return }
        let values = dictionary as NSDictionary
        let destination = values[symbols.keyRouteDestination] as? Data
        let flags = (values[symbols.keyRouteFlags] as? NSNumber)?.uint32Value
        if let destination {
            source.isIPRoute = NetworkStatisticsRouteParser.isIPRoute(destination)
        }
        if let flags {
            source.shouldInclude = NetworkStatisticsRouteParser.shouldInclude(flags: flags)
        }
        if let interfaceIndex = values[symbols.keyInterface] as? NSNumber {
            source.interfaceName = interfaceName(for: interfaceIndex.uint32Value)
        }
        let shouldRemove = !source.removalRequested
            && NetworkStatisticsRouteParser.shouldRemoveSource(destination: destination, flags: flags)
        source.removalRequested = source.removalRequested || shouldRemove
        sources[sourceID] = source
        if shouldRemove {
            symbols.sourceRemove(sourceRef)
        }
    }

    private func handleCounts(sourceID: Int, dictionary: CFDictionary) {
        guard let symbols, var source = sources[sourceID] else { return }
        let values = dictionary as NSDictionary
        if let receivedBytes = values[symbols.keyReceivedBytes] as? NSNumber {
            source.receivedBytes = receivedBytes.uint64Value
        }
        if let sentBytes = values[symbols.keySentBytes] as? NSNumber {
            source.sentBytes = sentBytes.uint64Value
        }
        source.hasCounts = true
        sources[sourceID] = source
    }

    private func finishQuery() {
        let samples = sources.compactMap { sourceID, source -> NetworkStatisticsRouteSample? in
            guard
                source.isIPRoute,
                source.shouldInclude,
                source.hasCounts,
                let interfaceName = source.interfaceName
            else {
                return nil
            }
            return NetworkStatisticsRouteSample(
                sourceID: sourceID,
                interfaceName: interfaceName,
                receivedBytes: source.receivedBytes,
                sentBytes: source.sentBytes
            )
        }
        let rates = rateCalculator.update(samples: samples, timestamp: ProcessInfo.processInfo.systemUptime)
        queryInFlight = false
        let completions = pendingCompletions
        pendingCompletions.removeAll(keepingCapacity: true)
        completions.forEach { $0(rates) }
    }

    private func interfaceName(for index: UInt32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard if_indextoname(index, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}
