//
//  ConnectionsManager.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//
// https://github.com/IBM-Swift/BlueSocket

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif
import Foundation
import Socket
import Dispatch
import Cryptor
//import CommonCrypto
//import CryptoKit

class ConnectionsManager {
    
    enum Constants {
        static let pingDuration: Double = 10000 // 10 seconds
    }
    
    var nodes = [Node]()
    
    static let quitCommand: String = "QUIT"
    static let shutdownCommand: String = "SHUTDOWN"
    static let bufferSize = 4096
    
    var listenPort: Int = 8333
    var listenSocket: Socket? = nil
    var continueRunningValue = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "hn.vu.outboundConnections.socketLockQueue")
    var continueRunning: Bool {
        set(newValue) {
            socketLockQueue.sync {
                self.continueRunningValue = newValue
            }
        }
        get {
            return socketLockQueue.sync {
                self.continueRunningValue
            }
        }
    }

    var updateHandler: (([String: NetworkUpdate],Error?) -> Void)?
    
    // MARK: -

    public init(addresses: [String], listenPort: Int = 8333, updateHandler: (([String: NetworkUpdate],Error?) -> Void)?) {
        self.updateHandler = updateHandler
        self.listenPort = listenPort
        for address in addresses {
            if ConnectionsManager.isValidAddress(address: address) {
                let node = Node(address: address)

                print("ConnectionsManager init  address  \(address)      node address  \(node.address) : \(node.port)       listenPort \(listenPort)")
                node.connectionType = .outBound
                nodes.append(node)
                var networkUpdate = NetworkUpdate(type: .addedNodeWithAddress, level: .information, error: .allFine)
                networkUpdate.node = node
                updateHandler?(["\(address)":networkUpdate], nil)
            }
        }
    }
        
    deinit {
        for socket in connectedSockets.values {
            socket.close()
        }
        self.listenSocket?.close()
    }
        
    func close() {
        shutdownServer()
    }
    
    // MARK: -
    
    func run() {
        
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        queue.async { [unowned self] in
            
            do {
                // Create an IPV4 socket...
                // VirtualBox running Ubuntu cannot see IPV6 local connections
                try self.listenSocket = Socket.create(family: .inet)
                
                guard let socket = self.listenSocket else {
                    print("Unable to unwrap socket...")
                    return
                }

                print("run() socket.listen self.listenPort  \(self.listenPort)")
                try socket.listen(on: self.listenPort)
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()

                    // Set how long we'll wait with no received
                    // data before we Ping the remote node
                    try newSocket.setReadTimeout(value: UInt(Constants.pingDuration))

                    print("run() newSocket.remoteHostname  \(newSocket.remoteHostname)    newSocket.remotePort  \(newSocket.remotePort)")
                    
                    let node = Node(address: newSocket.remoteHostname, port: UInt16(newSocket.remotePort))
                    node.connectionType = .inBound
                    node.socket = newSocket
                    self.nodes.append(node)
                    print("run() Other node connecting to us...")
                    print("calling addNewConnection from run()")
                    self.addNewConnection(node: node)
                    
                } while self.continueRunning
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("run Unexpected error...")
                    return
                }
                
                if self.continueRunning {
                    
                    print("run Error reported:\n \(socketError.description)")
                    
                }
            }
        }
        connectToAllNodes()
        dispatchMain()
    }
    
    func connectToAllNodes() {
        for node in nodes {
            connectToNode(node: node)
        }
    }
    
    func connectToNode(node: Node) {
        do {
            var family = Socket.ProtocolFamily.inet
            if node.address.contains(":") { family = Socket.ProtocolFamily.inet6 }
            print("Socket.ProtocolFamily = \(family)")
            let newNodeSocket = try Socket.create(family: family)
            // What buffer size shall we use ?
//            newNodeSocket.readBufferSize = 32768
            try newNodeSocket.connect(to: node.address, port: Int32(node.port), timeout: 10000)
//            try newNodeSocket.connect(to: node.address, port: Int32(node.port), timeout: 0)
            
            var networkUpdate = NetworkUpdate(type: .connected, level: .information, error: .allFine)
            networkUpdate.node = node
            updateHandler?(["\(node.address):\(node.port)":networkUpdate], nil)

            // Set how long we'll wait with no received
            // data before we Ping the remote node
//            try newNodeSocket.setReadTimeout(value: UInt(Constants.pingDuration))
            try newNodeSocket.setBlocking(mode: true)
            
//            let node = Node(address: newNodeSocket.remoteHostname, port: UInt16(newNodeSocket.remotePort))
            node.address = newNodeSocket.remoteHostname
            node.port = UInt16(newNodeSocket.remotePort)
            node.connectionType = .outBound
            node.socket = newNodeSocket
            nodes.append(node)
            print("calling addNewConnection from connectToNode()")
            addNewConnection(node: node)
        }
        catch let error {
            guard let socketError = error as? Socket.Error else {
                print("connectToNode Unexpected error...")
                return
            }
            // is error reported on connection close ?
            print("connectToNode Error reported:\n \(socketError.description)")
        }
    }
    
    // MARK: - Messages
    
    private func sendMessage(_ socket: Socket?, _ message: Message) {
        guard let socket = socket else { return }
        let data = message.serialize()
        let dataArray = [UInt8](data)
        do {
            try socket.write(from: data)
        } catch let error {
            guard let socketError = error as? Socket.Error else {
                print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                return
            }
            if self.continueRunning {
                print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
            }
        }
    }

    private func sendVersionMessage(_ node: Node) {
        node.sentNetworkUpdateType = .sentVersion
        node.sentVersion = true
        var networkUpdate = NetworkUpdate(type: .sentVersion, level: .success, error: .allFine)
        networkUpdate.node = node
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
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
        
        let message = Message(command: .Version, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        sendMessage(node.socket, message)
    }
    
    private func receiveVersionMessage(_ node: Node, dataByteArray: [UInt8], arrayLength: UInt32) {
        guard let versonMessage = VersionMessage.deserialise(dataByteArray, arrayLength: arrayLength) else { return }
        node.version = versonMessage.version
        node.theirUserAgent = versonMessage.userAgent
        node.emittingAddress = versonMessage.receivingAddress
        node.services = versonMessage.services
        node.startHeight = versonMessage.startHeight
        node.relay = versonMessage.relay
        
        node.receivedNetworkUpdateType = .receivedVersion
        node.receivedVersion = true
        var networkUpdate = NetworkUpdate(type: .receivedVersion, level: .success, error: .allFine)
        networkUpdate.node = node
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        if node.sentVerack == false {
            sendVerackMessage(node)
        }
    }

    private func receiveVerackMessage(_ node: Node) {
        node.receivedVerack = true
        node.receivedNetworkUpdateType = .receivedVerack
        var networkUpdate = NetworkUpdate(type: .receivedVerack, level: .success, error: .allFine)
        networkUpdate.node = node
        self.updateHandler?(["\(node.name)":networkUpdate], nil)

        node.receivedVerack = true
    }

    private func sendVerackMessage(_ node: Node) {
        node.sentNetworkUpdateType = .sentVerack
        node.sentVerack = true
        var networkUpdate = NetworkUpdate(type: .sentVerack, level: .success, error: .allFine)
        networkUpdate.node = node
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        let verackMessage = VerackMessage()
        let payload = verackMessage.serialize()
        let message = Message(command: .Verack, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        sendMessage(node.socket, message)
    }

    private func sendPingMessage(_ node: Node) {
        node.sentNetworkUpdateType = .sentPing
        node.sentPing = true
        node.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
        node.myPingNonce = generateNonce()
        
        var networkUpdate = NetworkUpdate(type: .sentPing, level: .success, error: .allFine)
        networkUpdate.node = node
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
        networkUpdate.message1 = "<\(NetworkUpdateType.sentPing)>"
        networkUpdate.message2 = "\(node.myPingNonce)"
        networkUpdate.node = node
        // self.updateHandler?(["information":networkUpdate], nil)
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        let pingMessage = PingMessage(nonce: node.myPingNonce)
        let payload = pingMessage.serialize()
        let message = Message(command: .Ping, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        sendMessage(node.socket, message)
    }
    
    private func receivePongMessage(_ node: Node, dataByteArray: [UInt8]) -> (expectedNonce: UInt64, receivedNonce: UInt64) {
        var networkUpdate = NetworkUpdate(type: .receivedPong, level: .success, error: .allFine)
        networkUpdate.node = node
        node.receivedNetworkUpdateType = .receivedPong
        node.receivedPong = true
        self.updateHandler?(["\(node.name)":networkUpdate], nil)

        // Compare Nonce with the one we sent
        // Only if this remote node uses Nonces with Ping/Pong
        let pongMessage = PongMessage.deserialise(dataByteArray)
        if let mine = node.myPingNonce,
            let theirs = pongMessage.nonce {//,
                networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
                networkUpdate.message1 = "<\(NetworkUpdateType.receivedPong)>"
                networkUpdate.message2 = "\(node.myPingNonce!)   littleEndian = \(node.myPingNonce!.littleEndian.toUInt8Array())   bigEndian = \(node.myPingNonce!.bigEndian.toUInt8Array())\n\(pongMessage.nonce!)   littleEndian = \(pongMessage.nonce!.littleEndian.toUInt8Array())   bigEndian = \(pongMessage.nonce!.bigEndian.toUInt8Array())"
                networkUpdate.node = node
                // self.updateHandler?(["information":networkUpdate], nil)
                self.updateHandler?(["\(node.name)":networkUpdate], nil)
            return (expectedNonce: mine, receivedNonce: theirs)
        }
        return (0, 1)
    }

    private func receivePingMessage(_ node: Node, dataByteArray: [UInt8]) {
        var networkUpdate = NetworkUpdate(type: .receivedPing, level: .success, error: .allFine)
        networkUpdate.node = node
        node.receivedNetworkUpdateType = .receivedPing
        node.receivedPing = true
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        let pingMessage = PingMessage.deserialise(dataByteArray)
        node.theirNodePingNonce = pingMessage.nonce

        networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
        networkUpdate.message1 = "<\(NetworkUpdateType.receivedPing)>"
        networkUpdate.message2 = "\(node.theirNodePingNonce)"
        networkUpdate.node = node
        // self.updateHandler?(["information":networkUpdate], nil)
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        sendPongMessage(node)
    }

    private func sendPongMessage(_ node: Node) {
        node.sentPong = true
        node.sentNetworkUpdateType = .sentPong
        var networkUpdate = NetworkUpdate(type: .sentPong, level: .success, error: .allFine)
        networkUpdate.node = node
        self.updateHandler?(["\(node.name)":networkUpdate], nil)

        networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
        networkUpdate.message1 = "<\(NetworkUpdateType.sentPong)>"
        networkUpdate.message2 = "\(node.theirNodePingNonce)"
        networkUpdate.node = node
        // self.updateHandler?(["information":networkUpdate], nil)
        self.updateHandler?(["\(node.name)":networkUpdate], nil)
        
        let pongMessage = PongMessage(nonce: node.theirNodePingNonce)
        let payload = pongMessage.serialize()
        let message = Message(command: .Pong, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        sendMessage(node.socket, message)
    }
    
    // MARK: -

    // Attempt to consume network packet data
    private func consumeNetworkPackets(_ node: Node) {
        // Extract data
        if node.packageData.count < 24 { return }
    
        while consumeMessage(node) { }
    }

    /// Attempt to consume message data.
    /// Returns whether message was consumed
    private func consumeMessage(_ node: Node) -> Bool {
        if let message = Message.deserialise(Array([UInt8](node.packageData)), arrayLength: UInt32(node.packageData.count)) {
            
            if message.payload.count < message.length {
                // We received the Message data but not the payload
                return false
            }
            let payload = message.payload
            node.packageData.removeFirst(Int(message.length + 24))
            
            // Confirm magic number is correct
            if message.magic != 0xe3e1f3e8 {
                print("magic != 0xe3e1f3e8\nmagic == \(message.magic)\nfor node with address \(node.address):\(node.port)")
                return false
            }

            // Only verify checksum if this packet sent payload
            // with message header
            if message.payload.count >= message.length {
                // Confirm checksum for message is correct
                let checksumFromPayload =  Array(payload.doubleSHA256ToData[0..<4])
                var checksumConfirmed = true
                for (index, element) in checksumFromPayload.enumerated() {
                    if message.checksum[index] != element { checksumConfirmed = false; break }
                }
                if checksumConfirmed != true { return false }
            } else {
                // Still more data to retrive for this message
                return false
            }

            let payloadByteArray = Array([UInt8](payload))
            let payloadArrayLength = payload.count

            var networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
            networkUpdate.message1 = "Incoming <\(message.command.onWireName)>"
            networkUpdate.message2 = "\(payloadByteArray)"
            networkUpdate.node = node
            self.updateHandler?(["\(node.name)":networkUpdate], nil)

            // MARK: - Message Check
            switch message.command {
            case .Unknown:
                // Need to set this node as bad
                break
            case .Version:
                self.receiveVersionMessage(node, dataByteArray: payloadByteArray, arrayLength: UInt32(payloadArrayLength))
            case .Verack:
                self.receiveVerackMessage(node)
            case .Ping:
                self.receivePingMessage(node, dataByteArray: payloadByteArray)
            case .Pong:
                let (expectedNonce, receivedNonce) = self.receivePongMessage(node, dataByteArray: payloadByteArray)
                if expectedNonce != receivedNonce {
                    // Nonces do not match
                    // Need to set this node as bad
                    networkUpdate = NetworkUpdate(type: .message, level: .information, error: .incorrectPingNonce)
                    networkUpdate.message1 = "<\(message.command.onWireName)>"
                    networkUpdate.message2 = "Nonce != \(node.myPingNonce!)"
                    networkUpdate.node = node
                    self.updateHandler?(["\(node.name)":networkUpdate], nil)
                } else {
                    networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
                    networkUpdate.message1 = "<\(message.command.onWireName)>"
                    networkUpdate.message2 = "Nonce == \(node.myPingNonce!)"
                    networkUpdate.node = node
                    self.updateHandler?(["\(node.name)":networkUpdate], nil)
                }
                                        
            case .Addr:
                break
            case .Inv:
                break
            case .Getheaders:
                break
            case .Sendheaders:
                break
            case .Sendcmpct:
                break
            }
            networkUpdate = NetworkUpdate(type: .message, level: .information, error: .allFine)
            networkUpdate.message1 = "<\(message.command.onWireName)>"
            networkUpdate.message2 = ""
            networkUpdate.node = node
            self.updateHandler?(["\(node.name)":networkUpdate], nil)
            return true
        }
        return false
    }
    
    func addNewConnection(node: Node) {
        print("addNewConnection \(node.address):\(node.port)")
        guard let socket = node.socket else {
            print("addNewConnection: No socket for this node \(node.address):\(node.port)")
            return
        }
        
        // Add the new socket to the list of connected sockets...
        socketLockQueue.sync { [unowned self, socket] in
            self.connectedSockets[socket.socketfd] = socket
        }
        
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .default)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in
            
            var shouldKeepRunning = true
//            var readData = Data(capacity: ConnectionsManager.bufferSize)
            
            do {
                var networkUpdate = NetworkUpdate(type: .connected, level: .information, error: .allFine)
                networkUpdate.node = node
                self.updateHandler?(["\(node.name)":networkUpdate], nil)

                var randomDuration = Double.random(in: 20 ... 40)
                print("randomDuration = \(randomDuration)")
                
                repeat {

                    // MARK: - <<<< Message pump
                    
                    // If we've never sent Version message, send it now
                    if node.sentVersion == false {
                        self.sendVersionMessage(node)
                        continue
                    }
                    
                    // Send a Ping message periodically
                    // to check whether the remote node is still around
                    let elapsedTime = (NSDate().timeIntervalSince1970 - node.lastPingReceivedTimeInterval)
                    if node.receivedVerack == true
                        && elapsedTime > (randomDuration) {
                        randomDuration = Double.random(in: 20 ... 40)
                        print("randomDuration = \(randomDuration)")
                        self.sendPingMessage(node)
                    }
                    
                    // MARK: - Read Data
                    
                    // Read incoming data
                    // We're looking for Messages and Payloads
                    // Once we have both, then the data is consumed
                    
                    // Some messages do not require a payload i.e. verack
//                    var bytesRead = try socket.read(into: &readData)

                    // https://github.com/IBM-Swift/BlueSocket/issues/117
                    var readData = Data(capacity: ConnectionsManager.bufferSize)
                    while try socket.isReadableOrWritable().readable {
                        let bytesRead = try socket.read(into: &readData)
                        if bytesRead == 0
                            && socket.remoteConnectionClosed == true {
                            shouldKeepRunning = false
                            break
                        }
                        if bytesRead > 0 {
                            node.packageData.append(readData)
                        }
                        readData.count = 0
                    }
                    
                    self.consumeNetworkPackets(node)
                } while shouldKeepRunning
                
                networkUpdate = NetworkUpdate(type: .socketClosing, level: .information, error: .allFine)
                networkUpdate.node = node
                self.updateHandler?(["information":networkUpdate], nil)
                socket.close()
                networkUpdate = NetworkUpdate(type: .socketClosed, level: .information, error: .allFine)
                networkUpdate.node = node
                self.updateHandler?(["information":networkUpdate], nil)

                self.socketLockQueue.sync { [unowned self, socket] in
                    self.connectedSockets[socket.socketfd] = nil
                }
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("addNewConnection Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("addNewConnection Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }
    
    func shutdownServer() {
        var networkUpdate = NetworkUpdate(type: .shuttingDown, level: .information, error: .allFine)
        updateHandler?(["information":networkUpdate], nil)
        print("shuttingDown...")
        self.continueRunning = false
        
        // Close all open sockets...
        for socket in connectedSockets.values {
            self.socketLockQueue.sync { [unowned self, socket] in
                self.connectedSockets[socket.socketfd] = nil
                networkUpdate = NetworkUpdate(type: .socketClosing, level: .information, error: .allFine)
                updateHandler?(["information":networkUpdate], nil)
                socket.close()
                networkUpdate = NetworkUpdate(type: .socketClosed, level: .information, error: .allFine)
                updateHandler?(["information":networkUpdate], nil)
            }
        }
        print("shutdown")
    }
    
    // MARK: -

    private static func isValidAddress(address: String) -> Bool {
        
        // Address must be
        //     IPV4 ( UInt8 + '.' + UInt8 + '.' + UInt8 + '.' + UInt8 )
        //     Or
        //     IPV6 ( UInt32hex + ':'UInt32hex + ':'UInt32hex + ':'UInt32hex + ':'UInt32hex + ':'UInt32hex )
        
        // port must be:
        //     an Unsigned Integer
        //     between 1-65535
        //     actually should be between 1024-65535
        
        return true
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

/*
public func testSha256Hashing() {
    guard let test1 = "hello".data(using: .utf8) else { print("test1 Error converting 'hello' into Data object"); return }
    print("hello")
    print("- sha256 = \(test1.sha256ToHexString)")
    print("- double sha256 = \(test1.sha256sha256ToHexString)\n")
    // 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 (first round of sha-256)
    // 9595c9df90075148eb06860365df33584b75bff782a510c6cd4883a419833d50 (second round of sha-256)
    
    guard let test2 = "abc".data(using: .utf8) else { print("test2 Error converting 'abc' into Data object"); return }
    print("abc")
    print("- sha256 = \(test2.sha256ToHexString)")
    print("- double sha256 = \(test2.sha256sha256ToHexString)\n")
    // ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad (first round of sha-256)
    // 4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358 (second round of sha-256)

    guard let test3 = "The quick brown fox jumps over the lazy dog".data(using: .utf8) else { print("test3 Error converting 'The quick brown fox jumps over the lazy dog' into Data object"); return }
    print("The quick brown fox jumps over the lazy dog")
    print("- sha256 = \(test3.sha256ToHexString)")
    print("- double sha256 = \(test3.sha256sha256ToHexString)\n")
    // d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592 (first round of sha-256)
    // 6d37795021e544d82b41850edf7aabab9a0ebe274e54a519840c4666f35b3937 (second round of sha-256)
}

private func hexString(_ iterator: Array<UInt8>.Iterator) -> String {
    return iterator.map { String(format: "%02x", $0) }.joined()
}

extension Data {

    public var sha256ToUint8Array: [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(self.count), &hash)
        }
        return hash
    }

    public var sha256ToData: Data {
//        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        self.withUnsafeBytes { bytes in
//            _ = CC_SHA256(bytes.baseAddress, CC_LONG(self.count), &hash)
//        }
        return Data(self.sha256ToUint8Array)
    }

    public var sha256ToHexString: String {
//        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = self.withUnsafeBytes { bytes in
//            _ = CC_SHA256(bytes.baseAddress, CC_LONG(self.count), &hash)
//        }
//        return hexString(hash.makeIterator())
        return hexString(self.sha256ToUint8Array.makeIterator())
    }

    public var sha256sha256ToData: Data {
//        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = self.withUnsafeBytes {
//            CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
//        }
//        var hash2 = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = Data(hash).withUnsafeBytes {
//            CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash2)
//        }
        
        return Data(self.sha256sha256ToUint8Array)
    }

    public var sha256sha256ToUint8Array: [UInt8] {
//        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = self.withUnsafeBytes {
//            CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
//        }
//        var hash2 = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = Data(hash).withUnsafeBytes {
//            CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash2)
//        }
        return Data(self.sha256ToUint8Array).sha256ToUint8Array
//        return hash2
    }

    public var sha256sha256ToHexString: String {
//        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = self.withUnsafeBytes {
//            CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
//        }
//        var hash2 = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        _ = Data(hash).withUnsafeBytes {
//            CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash2)
//        }
//        return hexString(hash2.makeIterator())
        return hexString(sha256sha256ToUint8Array.makeIterator())
    }
}
*/
