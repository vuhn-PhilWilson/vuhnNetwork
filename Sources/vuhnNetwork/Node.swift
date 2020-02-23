//
//  Node.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation
import Socket

// https://www.raywenderlich.com/3437391-real-time-communication-with-streams-tutorial-for-ios

public class Node: NSObject, StreamDelegate {
    
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
            let nameData = self.name.data(using: .utf8) ?? Data([UInt8(0x00)])
            let hash = [UInt8](nameData.doubleSHA256ToData[0..<8]).reduce(0) { soFar, byte in
                return soFar << 8 | UInt64(byte)
            }
            return hash
        }
    }

    private let maxReadLength = 4096
    public var inputStream: InputStream?
    public var outputStream: OutputStream?
    
    var randomDuration = Double.random(in: 20 ... 40)
    
    // MARK: -
    
    public func connect() {
        if socket == nil {
            print("Outgoing connection")
            Stream.getStreamsToHost(withName: address, port: Int(port), inputStream: &inputStream, outputStream: &outputStream)
            if inputStream == nil || outputStream == nil {
                print("\(name) getStreamsToHost failed")
                return
            }
            
            inputStream?.delegate = self
            outputStream?.delegate = self
            
            inputStream?.schedule(in: .current, forMode: .default)
            outputStream?.schedule(in: .current, forMode: .default)
            
            inputStream?.open()
            outputStream?.open()

        } else if let socket = socket {
            print("Incoming connection")
            let queue = DispatchQueue.global(qos: .default)
            queue.async { [unowned self, socket] in
                do {
                    
                    repeat {
                        if self.sentVersion == false {
                            self.sendVersionMessage(self)
                        }
                        
                        self.checkForPing()

                        var readData = Data(capacity: self.maxReadLength)
                        while try socket.isReadableOrWritable().readable {
                            let bytesRead = try socket.read(into: &readData)
                            if bytesRead == 0
                                && socket.remoteConnectionClosed == true {
                                self.shouldKeepRunning = false
                                break
                            }
                            if bytesRead > 0 {
                                self.packetData.append(readData)
                            }
                            readData.count = 0
                        }
                        if self.packetData.count == 0 { continue }
                        print("\(self.name) packetData.count \(self.packetData.count)")
                        self.processData()
                        
                    } while self.shouldKeepRunning
                    
                    print("\(self.name) closing socket \(socket.remoteHostname):\(socket.remotePort)...")
                    socket.close()
                }
                catch let error {
                    guard let socketError = error as? Socket.Error else {
                        print("\(self.name) addNewConnection Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                        return
                    }
                    print("\(self.name) addNewConnection Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }

        print("Connected to \(name) \(connectionType)")
    }
    
    public func disconnect() {
        print("\(name) \(connectionType) disconnected")
        if socket == nil {
            socket?.close()
            socket = nil
        }
        inputStream?.delegate = nil
        outputStream?.delegate = nil
        inputStream?.remove(from: .current, forMode: .default)
        outputStream?.remove(from: .current, forMode: .default)
        inputStream?.close()
        outputStream?.close()
    }
    
    public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        switch stream {
        case let stream as InputStream:
            switch eventCode {
            case .openCompleted:
                print("open completed")
            case .hasBytesAvailable:
//                print("has bytes available")
                readAvailableBytes(stream: stream)
            case .endEncountered,.errorOccurred:
                print("end or error occurred")
                disconnect()
            default:
                print("some other event...")
            }
        case _ as OutputStream:
            switch eventCode {
            case .openCompleted:
                print("open completed")
            case .hasSpaceAvailable:
//                print("has space available")
                if sentVersion == false {
                    sendVersionMessage(self)
                }
            case .endEncountered,.errorOccurred:
                print("end or error occurred")
                disconnect()
            default:
                print("some other event...")
            }
        default:
            print("\(name) \(connectionType) Unknown stream type")
        }
    }
    private func checkForPing() {
//        print("\(name) <<<< checkForPing")
        
        // Send a Ping message periodically
        // to check whether the remote node is still around
        let elapsedTime = (NSDate().timeIntervalSince1970 - lastPingReceivedTimeInterval)
        // If we've already sent a ping and haven't received a pong,
        // then disconnect from this node
        if receivedVerack == true
            && elapsedTime > (randomDuration)
            && sentPing == true
            && receivedPong == false {
            print("\(name) sent Ping but did not receive Pong")
            shouldKeepRunning = false
            disconnect()
            return
        }
        
        if receivedVerack == true
            && elapsedTime > (randomDuration) {
            randomDuration = Double.random(in: 20 ... 40)
            print("\(name) randomDuration = \(randomDuration)")
            sendPingMessage(self)
        }
//        print("\(name) >>>> checkForPing")
    }
    private func readAvailableBytes(stream: InputStream) {
        
        checkForPing()

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxReadLength)
        defer { buffer.deallocate() }
        
        while stream.hasBytesAvailable {
            guard let numberOfBytesRead = inputStream?.read(buffer, maxLength: maxReadLength) else { return }
            
            if numberOfBytesRead > 0 {
                packetData += Data(bytesNoCopy: buffer, count: numberOfBytesRead, deallocator: .none)
            } else {
                if let error = stream.streamError { print(error); break }
            }
        }
        
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
                self.receiveVerackMessage(self)
            case .ping:
                self.receivePingMessage(self, dataByteArray: payloadByteArray)
            case .pong:
                let (expectedNonce, receivedNonce) = self.receivePongMessage(self, dataByteArray: payloadByteArray)
                if expectedNonce != receivedNonce {
                    // Nonces do not match
                    // Need to set this node as bad
                } else {
                }
                
            case .addr:
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
    
    var lastPingReceivedTimeInterval: TimeInterval
    
    public var packetData: Data
    
    public var address: String
    public var port: UInt16
    var socket: Socket?
    public var connectionType = ConnectionType.unknown
    
    /// Identifies protocol version being used by the node
    var version: Int32
    
    /// The network address of this node
    var emittingAddress: NetworkAddress
    
    /// bitfield of features to be enabled for this connection
    public var services: UInt64
    
    var theirNodePingNonce: UInt64?
    var myPingNonce: UInt64?
    
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
    
    public init(address: String, port: UInt16 = 8333) {
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
    
    public func sendVersionMessage(_ node: Node) {
        node.sentCommand = .version
        print("\(node.name) sent \(node.sentCommand)")
        node.sentNetworkUpdateType = .sentVersion
        node.sentVersion = true
        
        let version = VersionMessage(version: protocolVersion,
                                     services: 0x425, // (1061)
            //services: 0x125, // (293) SFNodeNetwork|SFNodeBloom|SFNodeBitcoinCash|SFNodeCF == 37 1 0 0 0 0 0 0
            timestamp: Int64(Date().timeIntervalSince1970),
            receivingAddress: NetworkAddress(services: 0x00,
                                             address: "::ffff:\(node.address)",
                port: UInt16(node.port)),
            emittingAddress: nil,
            nonce: 16009251466998072645,
            userAgent: yourUserAgent,
            startHeight: 621193,//0,//-1,
            relay: true)
        
        let payload = version.serialize()
        
        let message = Message(command: .version, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        if node.socket != nil {
            networkService.sendMessage(node.socket, message)
        } else {
            networkService.sendMessage(self, message)
        }
    }
    
    public func receiveVersionMessage(_ node: Node, dataByteArray: [UInt8], arrayLength: UInt32) {
        //        print("received \(node.receivedCommand)")
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
    
    public func receiveVerackMessage(_ node: Node) {
        //        print("received \(node.receivedCommand)")
        node.receivedVerack = true
        node.receivedNetworkUpdateType = .receivedVerack
        
        node.receivedVerack = true
    }
    
    public func sendVerackMessage(_ node: Node) {
        node.sentCommand = .verack
        node.sentNetworkUpdateType = .sentVerack
        node.sentVerack = true
        
        let verackMessage = VerackMessage()
        let payload = verackMessage.serialize()
        let message = Message(command: .verack, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)

        if node.socket != nil {
            networkService.sendMessage(node.socket, message)
        } else {
            networkService.sendMessage(self, message)
        }
    }
    
    public func sendPingMessage(_ node: Node) {
        node.sentCommand = .ping
        print("sent \(node.sentCommand)")
        node.sentNetworkUpdateType = .sentPing
        node.sentPing = true
        node.receivedPong = false
        node.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
        node.myPingNonce = generateNonce()
        
        let pingMessage = PingMessage(nonce: node.myPingNonce)
        let payload = pingMessage.serialize()
        let message = Message(command: .ping, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        if node.socket != nil {
            networkService.sendMessage(node.socket, message)
        } else {
            networkService.sendMessage(self, message)
        }
    }
    
    public func receivePongMessage(_ node: Node, dataByteArray: [UInt8]) -> (expectedNonce: UInt64, receivedNonce: UInt64) {
        //        print("received \(node.receivedCommand)")
        node.receivedNetworkUpdateType = .receivedPong
        node.receivedPong = true
        
        // Compare Nonce with the one we sent
        // Only if this remote node uses Nonces with Ping/Pong
        let pongMessage = PongMessage.deserialise(dataByteArray)
        if let mine = node.myPingNonce,
            let theirs = pongMessage.nonce {
            return (expectedNonce: mine, receivedNonce: theirs)
        }
        return (0, 1)
    }
    
    public func receivePingMessage(_ node: Node, dataByteArray: [UInt8]) {
        //        print("received \(node.receivedCommand)")
        node.receivedNetworkUpdateType = .receivedPing
        node.receivedPing = true
        
        let pingMessage = PingMessage.deserialise(dataByteArray)
        node.theirNodePingNonce = pingMessage.nonce
        
        sendPongMessage(node)
    }
    
    public func sendPongMessage(_ node: Node) {
        node.sentCommand = .pong
        print("sent \(node.sentCommand)")
        node.sentPong = true
        node.sentNetworkUpdateType = .sentPong
        
        let pongMessage = PongMessage(nonce: node.theirNodePingNonce)
        let payload = pongMessage.serialize()
        let message = Message(command: .pong, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        
        if node.socket != nil {
            networkService.sendMessage(node.socket, message)
        } else {
            networkService.sendMessage(self, message)
        }
    }
}
