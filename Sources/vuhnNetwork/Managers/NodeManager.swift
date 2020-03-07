// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif
import Foundation
import Cryptor
import NIO
// https://github.com/apple/swift-nio/blob/master/Sources/NIOChatClient/main.swift

final class ServerInboundHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    // All access to channels is guarded by channelsSyncQueue.
    private let channelsSyncQueue = DispatchQueue(label: "channelsQueue")
    private var channels: [ObjectIdentifier: Channel] = [:]
    
    private var nodeManager: NodeManager?
    
    init(with nodeManager: NodeManager) {
        self.nodeManager = nodeManager
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        print("server channelActive \(context.remoteAddress!) => \(context.localAddress!)")
        let remoteAddress = context.remoteAddress!
        let channel = context.channel
        channels[ObjectIdentifier(channel)] = channel
        
        if let ipAddress = remoteAddress.ipAddress,
            let port = remoteAddress.port {
            let node = Node(address: ipAddress, port: UInt16(port), nodeDelegate: nodeManager)
            node.connectionType = .inBound
            node.inputChannel = channel
            nodeManager?.nodes.append(node)
            nodeManager?.didConnectNode(node)
            node.sendVersionMessage()
            node.startPingTimer()
            print("server channelActive inBound node added: \(context.remoteAddress!) => \(context.localAddress!)")
        }
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        print("server channelInactive \(context.remoteAddress!) => \(context.localAddress!)")
        let channel = context.channel
        channels.removeValue(forKey: ObjectIdentifier(channel))
        if let node = nodeManager?.nodes.filter({
            if let channelToCheck = $0.inputChannel,
                channelToCheck.remoteAddress == context.channel.remoteAddress {
                return true
            }
            return false
        }).first {
            nodeManager?.nodes.removeAll(where: { (nodeToCheck) -> Bool in
                nodeToCheck.name == node.name
            })
            node.disconnect()
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("server channelRead \(context.remoteAddress!) => \(context.localAddress!)")
        let buffer = self.unwrapInboundIn(data)
        
        // Find which node this channel belongs to
        if let node = nodeManager?.nodes.filter({
            if let channelToCheck = $0.inputChannel,
                channelToCheck.remoteAddress == context.channel.remoteAddress {
                return true
            }
            return false
        }).first {
            node.packetData.append(contentsOf: buffer.readableBytesView)

            print("server channelRead \(node.name)  \(context.remoteAddress!) => \(context.localAddress!) node.packetData count \(node.packetData.count)")
            node.handleInboundChannelData()
        } else {
            print("server channelRead \(context.remoteAddress!) => \(context.localAddress!) node not found")
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }

    private func writeToAll(channels: [ObjectIdentifier: Channel], allocator: ByteBufferAllocator, message: String) {
        var buffer =  allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        self.writeToAll(channels: channels, buffer: buffer)
    }

    private func writeToAll(channels: [ObjectIdentifier: Channel], buffer: ByteBuffer) {
        channels.forEach { $0.value.writeAndFlush(buffer, promise: nil) }
    }
}

public class NodeManager: NodeDelegate {
    
    // MARK: - NodeDelegate

    public func didConnectNode(_ node: Node) {
        // serialize/ deserialize to have v4 addresses prepended with
        // "0000:0000:0000:0000:0000:ffff"
        var networkAddress = node.emittingAddress
        if NetworkAddress.isIPv4(node.emittingAddress.address) {
            let address = "0000:0000:0000:0000:0000:ffff:" + node.emittingAddress.address
            networkAddress = NetworkAddress(services: node.emittingAddress.services, address: address, port: node.emittingAddress.port)
            node.emittingAddress = networkAddress
            print("🥝  updated node.emittingAddress \(node.emittingAddress)")
        }
        let timestamp = NSDate().timeIntervalSince1970
        if !networkAddresses.contains(where: { (arg0) -> Bool in
            let (_, networkAddressToCheck) = arg0
            return networkAddressToCheck.address == networkAddress.address
                && networkAddressToCheck.port == networkAddress.port
        }) {
            networkAddresses.append((timestamp, networkAddress))
//            print("networkAddresses array added \(networkAddress.address):\(networkAddress.port)       count = \(networkAddresses.count)")
        } else {
//            print("networkAddresses array already contains \(networkAddress.address):\(networkAddress.port)       count = \(networkAddresses.count)")
        }
    }

    public func didDisconnectNode(_ node: Node) {
        nodes.removeAll(where: { (nodeToCheck) -> Bool in
            nodeToCheck.name == node.name
        })
    }

    public func didReceiveNetworkAddresses(_ node: Node, _ addresses: [(TimeInterval, NetworkAddress)]) {

        DispatchQueue.main.async {
            var additionsCount = 0
            for index in 0..<addresses.count {
                let (timestamp, networkAddress) = addresses[index]
                if !self.networkAddresses.contains(where: { (arg0) -> Bool in
                    let (_, networkAddressToCheck) = arg0
                    return networkAddressToCheck.address == networkAddress.address
//                        && networkAddressToCheck.port == networkAddress.port
                }) {
                    self.networkAddresses.append((timestamp, networkAddress))
                    additionsCount += 1
//                    print("networkAddresses array added \(networkAddress.address):\(networkAddress.port)       count = \(self.networkAddresses.count)")
                } else {
//                    print("networkAddresses array already contains \(networkAddress.address):\(networkAddress.port)       count = \(self.networkAddresses.count)")
                }
            }
            print("Added \(additionsCount) to networkAddresses")
            let alladdresses = self.networkAddresses.map {
                $0.1
            }
            let addressesSet: Set<NetworkAddress> = Set(alladdresses)
            print("addressesSet unique count \(addressesSet.count)")
        }
    }
    
    // MARK: -
    
    static let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    static var serverChannel: Channel?
    
    enum Constants {
        static let pingDuration: Double = 10000 // 10 seconds
    }
    
    // MARK: - Public Properties
    
    public var nodes = [Node]()
    
    let networkService = NetworkService()
    
    // MARK: - Private Properties
    
    
    public var networkAddresses = [(TimeInterval, NetworkAddress)]()
    
    static let bufferSize = 4096
    
    var listeningPort: Int = -1
    var continueRunningValue = true
    private let serialQueue = DispatchQueue(label: "hn.vu.serial.queue")
    private let concurrentQueue = DispatchQueue(label: "hn.vu.concurrent.queue", attributes: .concurrent)
    
    var continueRunning: Bool {
        set(newValue) {
            networkService.stillRunning = newValue
            serialQueue.sync {
                self.continueRunningValue = newValue
            }
        }
        get {
            return serialQueue.sync {
                self.continueRunningValue
            }
        }
    }
    
    // MARK: - Public
    
    public init() { }
        
    deinit {
        close()
    }
        
    public func close() {
        shutdownServer()
    }
    
    // MARK: - DNS Seeding
    
    public func dnsSeedAddresses() -> [String]? {
        let dnsSeeds = [
            "seed.bitcoinabc.org",                      // - Bitcoin ABC seeder
            "seed-abc.bitcoinforks.org",                // - bitcoinforks seeders
            "btccash-seeder.bitcoinunlimited.info",     // - BU seeder  uses xversion/xverack
            "seed.bchd.cash",                           // - BCHD
        ]

        let maxLength = dnsSeeds.map { Int($0.count) }.max() ?? 0
        for hostName in dnsSeeds {
            let remoteHostEntry = gethostbyname2(hostName, AF_INET)
            let remoteAddr = UnsafeMutableRawPointer(remoteHostEntry?.pointee.h_addr_list[0])
            var ipAddress = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET, remoteAddr, &ipAddress, socklen_t(INET6_ADDRSTRLEN))
            print("\(hostName.padding(toLength: maxLength, withPad: " ", startingAt: 0)) = \(String(cString: ipAddress))")
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["dig",
                          "+short"]
        for seed in dnsSeeds {
            task.arguments?.append(seed)
        }
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        }
        catch let error {
            print("task.run Error reported:\n \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let addressData = String(data: data, encoding: .utf8) {
            let seedAddresses: [String] = addressData.split(separator: "\n").removingDuplicates().map { String($0) }
            print("\n\(seedAddresses.count) seed addresses")
//            for (index, address) in seedAddresses.enumerated() {
//                print("\(index)\t\(address)")
//            }
            return seedAddresses
        }
        return nil
    }
    
    // MARK: - Start
    
    public func configure(with addresses: [String], and listeningPort: Int = 8333) {
        self.listeningPort = listeningPort
        for address in addresses {
            if NetworkAddress.isValidAddress(address: address) {
                let node = Node(address: address, nodeDelegate: self)
                node.connectionType = .outBound
                nodes.append(node)
            }
        }
    }
    
    public func startListening() {
        print("System core count \(System.coreCount)")
        
        let serverInboundHandler = ServerInboundHandler(with: self)
        let bootstrap = ServerBootstrap(group: NodeManager.eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                // Add handler that will buffer data until a \n is received
                channel.pipeline.addHandler(serverInboundHandler)
        }
            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(1))
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        
        do {
            NodeManager.serverChannel = try { () -> Channel in
                return try bootstrap.bind(host: "::1", port: listeningPort).wait()
                }()
        }
        catch let error {
            // is error reported on connection close ?
            print("Error binding to listening channel:\n \(error.localizedDescription)")
        }
        
        guard let serverChannel = NodeManager.serverChannel,
            let localAddress = serverChannel.localAddress else {
                fatalError("Address was unable to bind. Please check that the socket was not closed or that the address family was understood.")
        }
        print("Server started and listening on \(localAddress)")
    }

    public func connectToOutboundNodes() {
        for node in nodes {
            if node.connectionType == .outBound {
                node.nodeDelegate = self
                node.connect()
            }
        }
    }
    
    // MARK: - Private
    
    func shutdownServer() {
        print("shuttingDown...")
        self.continueRunning = false
        
        for node in nodes {
            node.disconnect()
        }
        try? NodeManager.eventLoopGroup.syncShutdownGracefully()
        _ = NodeManager.serverChannel?.closeFuture
        print("shutdown")
    }
}

// MARK: -

public func testSha256Hashing() {
    if let digest = Digest(using: .sha256).update(string: "abc")?.final(),
        let digest2 = Digest(using: .sha256).update(data: Data(digest))?.final() {
        print(CryptoUtils.hexString(from: digest))
        print(CryptoUtils.hexString(from: digest2))
    }
}

public func testSha256HashingData() {

    print("")
    if let data = "abc".data(using: .utf8),
        let digest = Digest(using: .sha256).update(data: data)?.final(),
        let digest2 = Digest(using: .sha256).update(data: Data(digest))?.final() {
        print(CryptoUtils.hexString(from: digest))
        print(CryptoUtils.hexString(from: digest2))
    }
}

extension Data {
    public var SHA256ToData: Data {
        guard
            let digest = Digest(using: .sha256).update(data: self)?.final()
            else { return Data() }
        return Data(digest)
    }

    public var doubleSHA256ToData: Data {
        guard
            let digest = Digest(using: .sha256).update(data: self)?.final(),
            let digest2 = Digest(using: .sha256).update(data: Data(digest))?.final()
            else { return Data() }
        return Data(digest2)
    }
    
    public var SHA256ToUInt8: [UInt8] {
        guard
            let digest = Digest(using: .sha256).update(data: self)?.final()
            else { return [UInt8]() }
        return digest
    }

    public var doubleSHA256ToUInt8: [UInt8] {
        guard
            let digest = Digest(using: .sha256).update(data: self)?.final(),
            let digest2 = Digest(using: .sha256).update(data: Data(digest))?.final()
            else { return [UInt8]() }
        return digest2
    }
    
}
