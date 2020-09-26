//
//  Node.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation
import Cryptor
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
    func didFailToConnectNode(_ node: Node)
    func didFailToReceiveVerAckForNode(_ node: Node)
    func didFailToReceivePongForNode(_ node: Node)
    func didFailToReceiveGetAddrForNode(_ node: Node)
    func didDisconnectNode(_ node: Node)
    
    func didReceiveNetworkAddresses(_ node: Node, _ addresses: [(TimeInterval, NetworkAddress)])
    func didReceiveBlockHeaders(_ node: Node, _ headers: [Header])
    func getBlockHeaders(_ node: Node) -> [Header]
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
        print("Outgoing NIO connection to \(name)")
        if !connectUsingNIO() {
            print("Failed to connect to \(name) \(connectionType)")
            nodeDelegate?.didFailToConnectNode(self)
            return
        }
        print("Connected to \(name) \(connectionType)")
        nodeDelegate?.didConnectNode(self)
    }
    
    public func disconnect() {
        print("\(nameShortened) \(connectionType) disconnected")
        shutDownPingTimer()
        shutDownGetAddrTimer()
        _ = self.inputChannel?.close()
        _ = self.outputChannel?.close()
        nodeDelegate?.didDisconnectNode(self)
    }
    
    private func checkForGetHeaders() {
        print("\(nameShortened) checkForGetHeaders")
        
        // Send GetHeaders message
        if receivedVerack == true
            && sentGetHeaders == true
            && receivedGetHeadersResponse == false {
            print("\(nameShortened) sent GetHeaders but did not receive Headers")
            return
        }
        
        if receivedVerack == true
            && sentGetHeaders == false
            && receivedGetHeadersResponse == false {
            sendGetHeadersMessage()
        }
    }
    
    private func checkForVerAck() {

        // If we've already sent a Version and haven't received a VerAck,
        // then disconnect from this node
        if receivedVerack == false
            && sentVersion == true {
            print("\(nameShortened) sent Version but did not receive VerAck")
            shouldKeepRunning = false
            failedToReceiveVerAck += 1
            nodeDelegate?.didFailToReceiveVerAckForNode(self)
            disconnect()
            return
        }
//        print("Received VerAck message from \(name) in time")
    }
    
    private func checkForGetAddr() {

        if receivedVerack == true
            && sentGetAddr == true
            && receivedGetAddrResponse == false {
            print("\(nameShortened) sent GetAddr but did not receive Addr")
//            shouldKeepRunning = false
            failedToReceiveGetAddrResponse += 1
            nodeDelegate?.didFailToReceiveGetAddrForNode(self)
//            disconnect()
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
            print("\(nameShortened) sent Ping but did not receive Pong")
            shouldKeepRunning = false
            failedToReceivePong += 1
            nodeDelegate?.didFailToReceivePongForNode(self)
            if failedToReceivePong > 3 {
                disconnect()
            }
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
                print("\(nameShortened) <unknown> payload length:\(payloadArrayLength) data:\(payloadByteArray)")
                
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
// TODO: -               process inv messages next
                break
            case .getheaders:
                print("\(nameShortened) <getheaders> payload length:\(payloadArrayLength) data:\(payloadByteArray)")
                break
            case .sendheaders:
                break
            case .headers:
            print("\(nameShortened) <headers> payload length:\(payloadArrayLength)")
                receiveHeadersMessage(dataByteArray: payloadByteArray, arrayLength: UInt32(payloadArrayLength))
                break
            case .sendcmpct:
                break
            case .feefilter:
                break
            case .protoconf:
                break
            case .xversion:
                self.receiveXVersionMessage(self, dataByteArray: payloadByteArray, arrayLength: UInt32(payloadArrayLength))
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
    
    var receivedXVersion = false
    var sentXVerack = false
    var sentXVersion = false
    var receivedXVerack = false
    
    var sentGetHeaders = false
    var receivedHeaders = false
    var receivedGetHeadersResponse = false
    
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
    
    private var getHeadersTimer : DispatchSourceTimer?
    

    
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
    
    public var nameShortened: String {
        get {
            let prefix = "0000:0000:0000:0000:0000:ffff:"
            var shortenedAddress = address
            if address.contains(prefix) {
                shortenedAddress.removeFirst(prefix.count)
            }
            return "\(shortenedAddress):\(port):\(theirUserAgent ?? "")"
        }
    }
    
    public var addressShortened: String {
        get {
            let prefix = "0000:0000:0000:0000:0000:ffff:"
            var shortenedAddress = address
            if address.contains(prefix) {
                shortenedAddress.removeFirst(prefix.count)
            }
            return "\(shortenedAddress):\(port)"
        }
    }
    
    public var attemptsToConnect: UInt32 = 0
    public var lastAttempt: UInt64 = 0
    public var lastSuccess: UInt64 = 0
    public var location: String = "¯\\_(ツ)_/¯"
    public var latency: UInt32 = UInt32.max
    public var src: String?
    public var srcServices: UInt64?
    public var failedToConnect: UInt32 = 0
    public var failedToReceiveVerAck: UInt32 = 0
    public var failedToReceivePong: UInt32 = 0
    public var failedToReceiveGetAddrResponse: UInt32 = 0
    
    public var nodeDelegate: NodeDelegate?
    
    // MARK: -
    
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
        self.attemptsToConnect = 0
        
        super.init()
    }
    
    public func serializeForDisk() -> Data {
        var data = Data()
        data += "\(addressShortened),".data(using: .utf8) ?? Data([UInt8(0x00)])
        data += "\(theirUserAgent ?? ""),".data(using: .utf8) ?? Data([UInt8(0x00)])
        data += "\(attemptsToConnect),".data(using: .utf8) ?? Data()
        data += "\(lastAttempt),".data(using: .utf8) ?? Data()
        data += "\(lastSuccess),".data(using: .utf8) ?? Data()
        data += "\(location),".data(using: .utf8) ?? Data()
        data += "\(latency),".data(using: .utf8) ?? Data()
        data += "\(services),".data(using: .utf8) ?? Data()
        data += "\(src ?? "unknown"),".data(using: .utf8) ?? Data()
        data += "\(srcServices ?? 0),".data(using: .utf8) ?? Data()
        data += "\(UInt64(Date().timeIntervalSince1970)),".data(using: .utf8) ?? Data()
        data += "\(failedToConnect),".data(using: .utf8) ?? Data()
        data += "\(failedToReceiveVerAck),".data(using: .utf8) ?? Data()
        data += "\(failedToReceivePong),".data(using: .utf8) ?? Data()
        data += "\(failedToReceiveGetAddrResponse)\n".data(using: .utf8) ?? Data()
        
        return data
    }
    
    
    // MARK: - Messages
    
    public func sendVersionMessage() {
        sentCommand = .version
        print("\(nameShortened) sent \(sentCommand)")
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
        
        startGetHeadersTimer()
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
    
    public func receiveXVersionMessage(_ node: Node, dataByteArray: [UInt8], arrayLength: UInt32) {
        print("\(nameShortened) received \(node.receivedCommand)")
//        guard let xversonMessage = XVersionMessage.deserialise(dataByteArray, arrayLength: arrayLength) else { return }
//        node.version = versonMessage.version
//        node.theirUserAgent = versonMessage.userAgent
//        node.emittingAddress = versonMessage.receivingAddress
//        node.services = versonMessage.services
//        node.startHeight = versonMessage.startHeight
//        node.relay = versonMessage.relay
//
        node.receivedNetworkUpdateType = .receivedXVersion
        node.receivedXVersion = true
        
        if node.sentXVerack == false {
            sendXVerackMessage(node)
        }
    }

    public func sendXVerackMessage(_ node: Node) {
        node.sentCommand = .xverack
        node.sentNetworkUpdateType = .sentXVerack
        node.sentXVerack = true
        
        print("\(nameShortened) send XVerack Message")
        
        let xverackMessage = XVerackMessage()
        let payload = xverackMessage.serialize()
        let message = Message(command: .xverack, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        networkService.sendMessage(
            node.connectionType == .inBound
                ? node.inputChannel
                : node.outputChannel,
            message)
    }
    
    public func sendPingMessage() {
        sentCommand = .ping
//        print("\(nameShortened) sent \(sentCommand)  PING   >>>>>>>>>  PING   >>>>>>>>>  PING   >>>>>>>>>  PING   >>>>>>>>>  PING   >>>>>>>>>  ")
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
//        print("\(nameShortened) received \(receivedCommand)  PONG   <<<<<<<<<  PONG   <<<<<<<<<  PONG   <<<<<<<<<  PONG   <<<<<<<<<  PONG   <<<<<<<<<  ")
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
//        print("received \(receivedCommand)")
        receivedNetworkUpdateType = .receivedPing
        receivedPing = true
        
        let pingMessage = PingMessage.deserialise(dataByteArray)
        theirNodePingNonce = pingMessage.nonce
        sendPongMessage()
    }
    
    public func sendPongMessage() {
        sentCommand = .pong
//        print("sent \(sentCommand)")
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
//        print("\(nameShortened) sent \(sentCommand)  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  getaddr   >>>>>>>>>  ")
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
        print("\(nameShortened): received \(numberOfAddresses) addresses")
        
        nodeDelegate?.didReceiveNetworkAddresses(self, addresses)
    }
    
    public func sendGetHeadersMessage() {
        print("\(nameShortened) sendGetHeadersMessage")
        sentCommand = .getheaders
        sentNetworkUpdateType = .sentGetHeaders
        sentGetHeaders = true
        receivedGetHeadersResponse = false
        
        var lastHeaderBlockHash = GetHeadersMessage.genesisBlockHash
        if let lastHeader = nodeDelegate?.getBlockHeaders(self).last {
            lastHeaderBlockHash = lastHeader.blockHash
        }
        let hexString = CryptoUtils.hexString(from: [UInt8](lastHeaderBlockHash).reversed())
        print("\(#function) [\(#line)] lastHeaderBlockHash = \(hexString)")
        
        let payload = GetHeadersMessage(
            blockLocatorHashes: [lastHeaderBlockHash]
        ).serialize()
        
//        let payload = GetHeadersMessage(version: UInt32(version), blockLocatorHashes: [""]).serialize()
        let message = Message(command: sentCommand, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        networkService.sendMessage(
            connectionType == .inBound
                ? inputChannel
                : outputChannel,
            message)
    }
    
    public func receiveHeadersMessage(dataByteArray: [UInt8], arrayLength: UInt32) {
        guard let headersMessage = HeadersMessage.deserialise(dataByteArray) else {
            print("👤 \(#function) [\(#line)] \(name) failed to extract headers 😢")
            return
        }
        let headers: [Header] = headersMessage.blockHeaders
        let numberOfHeaders = headers.count
        print("\(nameShortened): 👤 received \(numberOfHeaders) headers")
        
        if numberOfHeaders == 0 {
            return
        }

        // Headers only point back to the previous block via its block hash.
        // We can only traverse backwards from any particular block
        // This is fine when you have a block header and want to confirm
        // it links all the way back to the genesis block or any other
        // previous block that's been locked in ( checkmarked )
        // This isn't so fine if you have an arbitrary block and
        // want to know if it links forward to a future known block
        
        // If you have an array of block headers,
        // if they're ordered by timestamp,
        // then each prevBlock should be the hash
        // of the previous block header
        
        // Due to timestamps being allowed up to 2 hours in future
        // a timestamp between blocks may not be in the same order
        // as they're linked together
        // So any sorting should be done via
        // block prevBlock hashes pointing to a blocks hash
        
        guard let allHeaders = nodeDelegate?.getBlockHeaders(self)
            else {
                print("\(nameShortened): Error: allHeaders is nil")
                return
        }

        // The last block should point to the previous block
        // The first block should point back to either
        // the genesis block ( if this is the first set of blocks received )
        // or to the last block in the total list
        
        // 6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000
        // 000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f
        let genesisBlockHash = "6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000"
        var bestBlockHash = genesisBlockHash
        
        if allHeaders.count > 0,
            let allHeadersLast = allHeaders.last {
            bestBlockHash = CryptoUtils.hexString(from: [UInt8](allHeadersLast.blockHash))
        }
        print("\(nameShortened): allHeaders.count = \(allHeaders.count)")
        print("\(nameShortened): bestBlockHash = \(bestBlockHash)")
        
        // We're only interested in a new list of headers which also link to
        // the current best block
        
        var sortedArray = [Header]()
        var nextBlock: Header?
        if !headers.contains(where: { (arg0) -> Bool in
            
            if CryptoUtils.hexString(from: [UInt8](arg0.prevBlock)) == bestBlockHash {
                nextBlock = arg0
                sortedArray.append(arg0)
                return true
            }
            return false
        }) {
            print("\(nameShortened): New headers do not contain bestBlockHash \(bestBlockHash)")
            print("\(nameShortened): Not adding these headers")
            
            print("\(nameShortened): \(CryptoUtils.hexString(from: [UInt8](headers.first!.prevBlock)))")
            return
        }
        
        
        print("\(#function) [\(#line)]  \(nameShortened): sortedArray.count \(sortedArray.count)")
        
        
        print("\(nameShortened): New headers contain bestBlockHash \(bestBlockHash)")
        if let nextBlock = nextBlock {
            print("\(nameShortened): nextBlock \(CryptoUtils.hexString(from: [UInt8](nextBlock.blockHash)))     its prevBlock = \(CryptoUtils.hexString(from: [UInt8](nextBlock.prevBlock)))")
            print("\(nameShortened): nextBlock \(CryptoUtils.hexString(from: [UInt8](nextBlock.blockHash).reversed()))     its prevBlock = \(CryptoUtils.hexString(from: [UInt8](nextBlock.prevBlock).reversed()))")
        }
        
        print("\(nameShortened): Sorting new headers")

        for _ in headers {
            
            let foundNextBlock = headers.filter({ (header) -> Bool in
                header.prevBlock == nextBlock?.blockHash
            })
            if let foundNextBlock = foundNextBlock.first {
                sortedArray.append(foundNextBlock)
                nextBlock = foundNextBlock
            } else {
                break
            }
        }
        print("\(nameShortened): Completed Sorting new headers")
        print("   sortedArray.count = \(sortedArray.count) ")

        nodeDelegate?.didReceiveBlockHeaders(self, sortedArray)

        // Restart timer to obtain next batch of headers
        sentGetHeaders = false
        receivedGetHeadersResponse = false
        startGetHeadersTimer()
    }
        
    // MARK: - NIO

    public func connectUsingNIO() -> Bool {
        
        let timestamp = NSDate().timeIntervalSince1970
        lastAttempt = UInt64(timestamp)
        attemptsToConnect += 1
        
        let nodeInboundHandler = NodeInboundHandler(with: self)
        let bootstrap = ClientBootstrap(group: NodeManager.eventLoopGroup)
            .connectTimeout(TimeAmount.seconds(1))
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
            failedToConnect += 1
            return false
        }
        if let outputChannel = outputChannel,
            let remoteAddress = outputChannel.remoteAddress {
            print("This Client connected to Remote Server: \(remoteAddress)\n. Press ^C to exit.")
            lastSuccess = UInt64(timestamp)
            connectionFirstMadeTimeInterval = NSDate().timeIntervalSince1970
            if sentVersion == false {
                sendVersionMessage()
                // Need to make sure we receive VerAck message from their node
                startVerAckTimer()
            }
            return true
        }
        failedToConnect += 1
        return false
    }

    // If we haven't received a VerAck by the time this timer expires
    // Then disconnect from their node
    public func startVerAckTimer() {
        let verAckTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
        
        let deadline: DispatchTime = .now() + .seconds(10)
        verAckTimer.schedule(deadline: deadline)
        verAckTimer.setEventHandler
        {
//            print("verAckTimer fired for \(self.name)")
            verAckTimer.cancel()
            verAckTimer.setEventHandler {}
            self.checkForVerAck()
        }
        verAckTimer.resume()
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
        if self.shouldKeepRunning == false {
            self.shutDownGetAddrTimer()
            return
        }
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

    public func startGetHeadersTimer() {
        let getHeadersTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
        
//        let deadline: DispatchTime = .now() + .seconds(Int(Double.random(in: 10 ... 300)))
//        let deadline: DispatchTime = .now() + .seconds(Int(Double.random(in: 10 ... 40)))
        let deadline: DispatchTime = .now() + .seconds(Int(Double.random(in: 5 ... 10)))
        
        getHeadersTimer.schedule(deadline: deadline)
        getHeadersTimer.setEventHandler
        {
            getHeadersTimer.cancel()
            getHeadersTimer.setEventHandler {}
            self.checkForGetHeaders()
        }
        getHeadersTimer.resume()
    }
    
    private func shutDownPingTimer() {
//        print("shutDown Ping Timer")
        pingTimer?.cancel()
        pingTimer?.setEventHandler {}
    }
    
    private func shutDownGetAddrTimer() {
//        print("shutDown GetAddr Timer")
        getAddrTimer?.cancel()
        getAddrTimer?.setEventHandler {}
    }
}
