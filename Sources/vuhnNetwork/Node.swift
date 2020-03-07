//
//  Node.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation
import CoreFoundation
#if os(Linux)
    import Glibc
#else
    import Darwin
#endif
import NIO
// https://github.com/apple/swift-nio/blob/master/Sources/NIOChatClient/main.swift

// https://www.raywenderlich.com/3437391-real-time-communication-with-streams-tutorial-for-ios

public protocol NodeDelegate {
    func didConnectNode(_ node: Node)
    func didDisconnectNode(_ node: Node)
    
    func didReceiveNetworkAddresses(_ node: Node, _ addresses: [(TimeInterval, NetworkAddress)])
}

public class NodeInboundHandler: ChannelInboundHandler {
    
    var node: Node
    
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    init(with node: Node) {
        self.node = node
    }
    
    private func printByte(_ byte: UInt8) {
        #if os(Android)
        print(Character(UnicodeScalar(byte)),  terminator:"")
        #else
        fputc(Int32(byte), stdout)
        #endif
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        node.packetData.append(contentsOf: buffer.readableBytesView)
        node.handleInboundChannelData()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        context.close(promise: nil)
    }
}

public class Node: NSObject {
    
    public enum ConnectionType {
        case outBound
        case inBound
        case unknown
        
        public func displayText() -> String {
            switch self {
            case .outBound: return "outBound"
            case .inBound: return " inBound"
            case .unknown: return "unknown"
            }
        }
    }
    
    public var nodeID: UInt64 {
        get {
            // If no name then node is invalid ?
            let nameData = self.name.data(using: .utf8) ?? Data([UInt8(0x00)])
            let hash = [UInt8](nameData.doubleSHA256ToData[0..<8]).reduce(0) { soFar, byte in
                return soFar << 8 | UInt64(byte)
            }
            return hash
        }
    }
    
    public var outputChannel: Channel?
    public var inputChannel: Channel?
    private let maxReadLength = 4096
    
    var randomDuration = Double.random(in: 10 ... 40)
    
    // MARK: -
    
    public func connect() {
        print("Outgoing NIO connection")
        if !connectUsingNIO() {
            print("Failed to connect to \(name) \(connectionType)")
            return
        }
        print("Connected to \(name) \(connectionType)")
        nodeDelegate?.didConnectNode(self)
    }
    
    public func disconnect() {
        print("\(name) \(connectionType) disconnected")
        shutDownPingTimer()
        shutDownGetAddrTimer()
        _ = self.inputChannel?.close()
        _ = self.outputChannel?.close()
        nodeDelegate?.didDisconnectNode(self)
    }
    
    private func checkForGetAddr() {

        if receivedVerack == true
            && sentGetAddr == true
            && receivedGetAddrResponse == false {
            print("\(name) sent GetAddr but did not receive Addr")
            shouldKeepRunning = false
            disconnect()
            return
        }
        
        if receivedVerack == true
            && sentGetAddr == false
            && receivedGetAddrResponse == false {
            sendGetAddrMessage()
        }
    }

    private func checkForPing() {

        // If we've already sent a ping and haven't received a pong,
        // then disconnect from this node
        if receivedVerack == true
            && sentPing == true
            && receivedPong == false {
            print("\(name) sent Ping but did not receive Pong")
            shouldKeepRunning = false
            disconnect()
            return
        }
        
        if receivedVerack == true {
            sendPingMessage()
        }
    }
    
    public func handleInboundChannelData() {
        processData()
    }

    private func processData() {

        if packetData.count >= 24,
            let message = networkService.consumeMessage(self) {
            receivedCommand = message.command

            let payloadByteArray = Array([UInt8](message.payload))
            let payloadArrayLength = message.payload.count
            
            switch message.command {
            case .unknown:
                // Need to set this node as bad
                print("\(name) payload length:\(payloadArrayLength) data:\(payloadByteArray)")
                
                break
            case .version:
                self.receiveVersionMessage(self, dataByteArray: payloadByteArray, arrayLength: UInt32(payloadArrayLength))
            case .verack:
                self.receiveVerackMessage()
            case .ping:
                self.receivePingMessage(dataByteArray: payloadByteArray)
            case .pong:
                let (expectedNonce, receivedNonce) = self.receivePongMessage(dataByteArray: payloadByteArray)
                if expectedNonce != receivedNonce {
                    // Nonces do not match
                    // Need to set this node as bad
                } else {
                }
                
            case .addr:
                receivedAddr = true
                if sentGetAddr == true
                    && receivedGetAddrResponse == false {
                    receivedGetAddrResponse = true
                    shutDownGetAddrTimer()
                    print("received GetAddr Response")
                }
                receiveAddrMessage(dataByteArray: payloadByteArray, arrayLength: UInt32(payloadArrayLength))
                break
            case .inv:
                break
            case .getheaders:
                break
            case .sendheaders:
                break
            case .sendcmpct:
                break
            case .feefilter:
                break
            case .protoconf:
                break
            case .xversion:
                break
            case .xverack:
                break
            case .getaddr:
                break
            }
        }
    }
    
    // MARK: -
    
    let networkService = NetworkService()
    var shouldKeepRunning = true
    
    var sentVersion = false
    var sentVerack = false
    var sentPing = false
    var sentPong = false
    
    var receivedVersion = false
    var receivedVerack = false
    var receivedPing = false
    var receivedPong = false
    
    var sentGetAddr = false
    var receivedAddr = false
    
    var lastPingReceivedTimeInterval: TimeInterval
    
    public var packetData: Data
    
    public var address: String
    public var port: UInt16
//    var socket: Socket?
    public var connectionType = ConnectionType.unknown
    
    /// Identifies protocol version being used by the node
    var version: Int32
    
    /// The network address of this node
    var emittingAddress: NetworkAddress
    
    /// bitfield of features to be enabled for this connection
    public var services: UInt64
    
    var theirNodePingNonce: UInt64?
    var myPingNonce: UInt64?
    private var pingTimer : DispatchSourceTimer?
    
    var receivedGetAddrResponse = false
    var getAddrRandomDuration = Double.random(in: 10 ... 40)
    var connectionFirstMadeTimeInterval: TimeInterval
    private var getAddrTimer : DispatchSourceTimer?

    
    /// User Agent (0x00 if string is 0 bytes long)
    /// The user agent that generated messsage.
    /// This is a encoded as a varString
    /// on the wire.
    /// This has a max length of MaxUserAgentLen.
    var theirUserAgent: String?
    
    /// The last block received by the emitting node
    var startHeight: Int32?
    
    /// Whether the remote peer should announce relayed transactions or not, see BIP 0037
    var relay: Bool?
    
    public var sentNetworkUpdateType = NetworkUpdateType.unknown
    public var receivedNetworkUpdateType = NetworkUpdateType.unknown
    
    
    public var sentCommand = FourCC.Command.unknown
    public var receivedCommand = FourCC.Command.unknown
    
    public var name: String {
        get {
            return "\(address):\(port)"
        }
    }
    
    public var attemptsToConnect: UInt32 = 0
    public var lastAttempt: UInt64 = 0
    public var lastSuccess: UInt64 = 0
    public var location: String = "¯\\_(ツ)_/¯"
    public var latency: UInt32 = UInt32.max
    public var src: String?
    public var srcServices: UInt64?
    
    public var nodeDelegate: NodeDelegate?
    
    public init(address: String, port: UInt16 = 8333, nodeDelegate: NodeDelegate? = nil) {
        self.nodeDelegate = nodeDelegate
        let (anAddress, aPort) = NetworkAddress.extractAddress(address, andPort: port)
        self.version = 0x00
        self.address = anAddress
        self.port = aPort
        self.services = 0x00
        self.emittingAddress = NetworkAddress(services: services, address: anAddress, port: aPort)
        self.theirNodePingNonce = 0x00
        self.myPingNonce = 0x00
        self.theirUserAgent = nil
        self.startHeight = nil
        self.relay = nil
        self.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
        self.packetData = Data()
        self.randomDuration = Double.random(in: 10 ... 40)
        self.connectionFirstMadeTimeInterval = NSDate().timeIntervalSince1970
        self.getAddrRandomDuration = Double.random(in: 10 ... 40)
        super.init()
        print("\(name) randomDuration = \(randomDuration)")
    }
    
    public func serializeForDisk() -> Data {
        var data = Data()
        data += "\(name),".data(using: .utf8) ?? Data([UInt8(0x00)])
        data += "\(attemptsToConnect),".data(using: .utf8) ?? Data()
        data += "\(lastAttempt),".data(using: .utf8) ?? Data()
        data += "\(lastSuccess),".data(using: .utf8) ?? Data()
        data += "\(location),".data(using: .utf8) ?? Data()
        data += "\(latency),".data(using: .utf8) ?? Data()
        data += "\(services),".data(using: .utf8) ?? Data()
        data += "\(src ?? "unknown"),".data(using: .utf8) ?? Data()
        data += "\(srcServices ?? 0),".data(using: .utf8) ?? Data()
        data += "\(UInt64(Date().timeIntervalSince1970))\n".data(using: .utf8) ?? Data()
        return data
    }
    
    
    // MARK: - Messages
    
    public func sendVersionMessage() {
        sentCommand = .version
        print("\(name) sent \(sentCommand)")
        sentNetworkUpdateType = .sentVersion
        sentVersion = true
        
        let version = VersionMessage(version: protocolVersion,
                                     services: 0x425, // (1061)
            //services: 0x125, // (293) SFNodeNetwork|SFNodeBloom|SFNodeBitcoinCash|SFNodeCF == 37 1 0 0 0 0 0 0
            timestamp: Int64(Date().timeIntervalSince1970),
            receivingAddress: NetworkAddress(services: 0x00,
                                             address: "::ffff:\(address)",
                port: UInt16(port)),
            emittingAddress: nil,
            nonce: 16009251466998072645,
            userAgent: yourUserAgent,
            startHeight: 621193,//0,//-1,
            relay: true)
        
        let payload = version.serialize()
        
        let message = Message(command: .version, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        networkService.sendMessage(
            connectionType == .inBound
                ? inputChannel
                : outputChannel,
            message)
    }
    
    public func receiveVersionMessage(_ node: Node, dataByteArray: [UInt8], arrayLength: UInt32) {
        print("received \(node.receivedCommand)")
        guard let versonMessage = VersionMessage.deserialise(dataByteArray, arrayLength: arrayLength) else { return }
        node.version = versonMessage.version
        node.theirUserAgent = versonMessage.userAgent
        node.emittingAddress = versonMessage.receivingAddress
        node.services = versonMessage.services
        node.startHeight = versonMessage.startHeight
        node.relay = versonMessage.relay
        
        node.receivedNetworkUpdateType = .receivedVersion
        node.receivedVersion = true
        
        if node.sentVerack == false {
            sendVerackMessage(node)
        }
    }
    
    public func receiveVerackMessage() {
        print("received \(receivedCommand)")
        receivedVerack = true
        receivedNetworkUpdateType = .receivedVerack
        receivedVerack = true

        
        // Start timer for checking PING
        startPingTimer()
        
        // Start timer for sending GetAddr and checking its associated Addr
        startGetAddrTimer()
    }
    
    public func sendVerackMessage(_ node: Node) {
        node.sentCommand = .verack
        node.sentNetworkUpdateType = .sentVerack
        node.sentVerack = true
        
        let verackMessage = VerackMessage()
        let payload = verackMessage.serialize()
        let message = Message(command: .verack, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)

//        if node.socket != nil {
//            networkService.sendMessage(node.socket, message)
//        } else {
    networkService.sendMessage(
        node.connectionType == .inBound
            ? node.inputChannel
            : node.outputChannel,
        message)
//        }
    }
    
    public func sendPingMessage() {
        sentCommand = .ping
        print("\(name) sent \(sentCommand)  PING   >>>>>>>>>  PING   >>>>>>>>>  PING   >>>>>>>>>  PING   >>>>>>>>>  PING   >>>>>>>>>  ")
        sentNetworkUpdateType = .sentPing
        sentPing = true
        receivedPong = false
        lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
        myPingNonce = generateNonce()
        
        let pingMessage = PingMessage(nonce: myPingNonce)
        let payload = pingMessage.serialize()
        let message = Message(command: .ping, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        networkService.sendMessage(
            connectionType == .inBound
                ? inputChannel
                : outputChannel,
            message)
    }
    
    public func receivePongMessage(dataByteArray: [UInt8]) -> (expectedNonce: UInt64, receivedNonce: UInt64) {
        print("\(name) received \(receivedCommand)  PONG   <<<<<<<<<  PONG   <<<<<<<<<  PONG   <<<<<<<<<  PONG   <<<<<<<<<  PONG   <<<<<<<<<  ")
        receivedNetworkUpdateType = .receivedPong
        receivedPong = true
        
        // Compare Nonce with the one we sent
        // Only if this remote node uses Nonces with Ping/Pong
        let pongMessage = PongMessage.deserialise(dataByteArray)
        if let mine = myPingNonce,
            let theirs = pongMessage.nonce {
            return (expectedNonce: mine, receivedNonce: theirs)
        }
        return (0, 1)
    }
    
    public func receivePingMessage(dataByteArray: [UInt8]) {
        print("received \(receivedCommand)")
        receivedNetworkUpdateType = .receivedPing
        receivedPing = true
        
        let pingMessage = PingMessage.deserialise(dataByteArray)
        theirNodePingNonce = pingMessage.nonce
        sendPongMessage()
    }
    
    public func sendPongMessage() {
        sentCommand = .pong
        print("sent \(sentCommand)")
        sentPong = true
        sentNetworkUpdateType = .sentPong
        
        let pongMessage = PongMessage(nonce: theirNodePingNonce)
        let payload = pongMessage.serialize()
        let message = Message(command: .pong, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        networkService.sendMessage(
            connectionType == .inBound
                ? inputChannel
                : outputChannel,
            message)
    }

    public func sendGetAddrMessage() {
        sentCommand = .getaddr
        print("\(name) sent \(sentCommand)  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  ")
        sentNetworkUpdateType = .sentGetAddr
        sentGetAddr = true
        receivedGetAddrResponse = false

        let payload = GetAddrMessage().serialize()
        let message = Message(command: sentCommand, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        networkService.sendMessage(
            connectionType == .inBound
                ? inputChannel
                : outputChannel,
            message)
    }
    
    public func receiveAddrMessage(dataByteArray: [UInt8], arrayLength: UInt32) {
        guard let addrMessage = AddrMessage.deserialise(dataByteArray) else {
            print("receiveAddrMessage \(name) failed to extract addresses 😢")
            return
        }
        let addresses: [(TimeInterval, NetworkAddress)] = addrMessage.networkAddresses
        let numberOfAddresses = addresses.count
        print("\(name): received \(numberOfAddresses) addresses")
        
        nodeDelegate?.didReceiveNetworkAddresses(self, addresses)
    }
        
    // MARK: - NIO

    public func connectUsingNIO() -> Bool {
        
        let nodeInboundHandler = NodeInboundHandler(with: self)
        let bootstrap = ClientBootstrap(group: NodeManager.eventLoopGroup)
            .connectTimeout(TimeAmount.seconds(5))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
            channel.pipeline.addHandler(nodeInboundHandler)
        }
        
        do {
            outputChannel = try { () -> Channel in
                return try bootstrap.connect(host: address, port: Int(port)).wait()
                }()
        }
        catch let error {
            // is error reported on connection close ?
            print("Error connecting to output channel:\n \(error.localizedDescription)")
            return false
        }
        if let outputChannel = outputChannel {
            print("This Client connected to Remote Server: \(outputChannel.remoteAddress!)\n. Press ^C to exit.")

            connectionFirstMadeTimeInterval = NSDate().timeIntervalSince1970
            if sentVersion == false {
                sendVersionMessage()
            }
            
            return true
        }
        return false
    }
    
    public func startPingTimer() {
        pingTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
        
        let delay: DispatchTime = .now() + .seconds(Int(randomDuration))
        pingTimer?.schedule(deadline: delay, repeating: .seconds(Int(randomDuration)))
        pingTimer?.setEventHandler
        {
            if self.shouldKeepRunning == false {
                self.shutDownPingTimer()
                return
            }
            self.checkForPing()
        }
        pingTimer?.resume()
    }

    public func startGetAddrTimer() {
        getAddrTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
        
        let delay: DispatchTime = .now() + .seconds(Int(getAddrRandomDuration))
        getAddrTimer?.schedule(deadline: delay, repeating: .seconds(Int(getAddrRandomDuration)))
        getAddrTimer?.setEventHandler
        {
            if self.shouldKeepRunning == false {
                self.shutDownGetAddrTimer()
                return
            }
            self.checkForGetAddr()
        }
        getAddrTimer?.resume()
    }
    
    private func shutDownPingTimer() {
        print("shutDown Ping Timer")
        pingTimer?.cancel()
        pingTimer?.setEventHandler {}
    }
    
    private func shutDownGetAddrTimer() {
        print("shutDown GetAddr Timer")
        getAddrTimer?.cancel()
        getAddrTimer?.setEventHandler {}
    }
}
