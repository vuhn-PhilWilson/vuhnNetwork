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
import Socket
import Cryptor

public class NodeManager {
    
    enum Constants {
        static let pingDuration: Double = 10000 // 10 seconds
    }
    
    // MARK: - Public Properties
    
    public var nodes = [Node]()
    
    let networkService = NetworkService()
    
    // MARK: - Private Properties
    
    static let bufferSize = 4096
    
    var listeningPort: Int = -1
    var listeningSocket: Socket? = nil
    var continueRunningValue = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "hn.vu.outboundConnections.socketLockQueue")
    var continueRunning: Bool {
        set(newValue) {
            networkService.stillRunning = newValue
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
    
    // MARK: - Public
    
    public init() { }
        
    deinit {
        for socket in connectedSockets.values {
            socket.close()
        }
        self.listeningSocket?.close()
    }
        
    public func close() {
        shutdownServer()
    }
    
    public func configure(with addresses: [String], and listeningPort: Int = 8333) {

        self.listeningPort = listeningPort
        for address in addresses {
            if NetworkAddress.isValidAddress(address: address) {
                let node = Node(address: address)
                node.connectionType = .outBound
                nodes.append(node)
            }
        }
    }
    
    public func startListening() {
        if listeningPort == -1 { return }
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        queue.async { [unowned self] in
            
            do {
                // Create an IPV4 socket...
                // VirtualBox running Ubuntu cannot see IPV6 local connections
                try self.listeningSocket = Socket.create(family: .inet)
                
                guard let socket = self.listeningSocket else {
                    print("Unable to unwrap socket...")
                    return
                }

                print("startListening() socket.listen self.listenPort  \(self.listeningPort)")
                try socket.listen(on: self.listeningPort)
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()

                    // Set how long we'll wait with no received
                    // data before we Ping the remote node
                    try newSocket.setReadTimeout(value: UInt(Constants.pingDuration))

                    print("startListening() newSocket.remoteHostname  \(newSocket.remoteHostname)    newSocket.remotePort  \(newSocket.remotePort)")
                    
                    let node = Node(address: newSocket.remoteHostname, port: UInt16(newSocket.remotePort))
                    node.connectionType = .inBound
                    node.socket = newSocket
                    self.nodes.append(node)
                    print("startListening() Other node connecting to us...")
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
    }
        
    public func connectToOutboundNodes() {
        for node in nodes {
            if node.connectionType == .outBound {
                connectToNode(node: node)
            }
        }
    }
    
    // MARK: - Private
    
    private func connectToNode(node: Node) {
        do {
            var family = Socket.ProtocolFamily.inet
            if node.address.contains(":") { family = Socket.ProtocolFamily.inet6 }
            print("Socket.ProtocolFamily = \(family)")
            let newNodeSocket = try Socket.create(family: family)
            // What buffer size shall we use ?
//            newNodeSocket.readBufferSize = 32768
            try newNodeSocket.connect(to: node.address, port: Int32(node.port), timeout: 10000)
//            try newNodeSocket.connect(to: node.address, port: Int32(node.port), timeout: 0)
            

            // Set how long we'll wait with no received
            // data before we Ping the remote node
//            try newNodeSocket.setReadTimeout(value: UInt(Constants.pingDuration))
            try newNodeSocket.setBlocking(mode: true)
            
//            let node = Node(address: newNodeSocket.remoteHostname, port: UInt16(newNodeSocket.remotePort))
//            node.address = newNodeSocket.remoteHostname
//            node.port = UInt16(newNodeSocket.remotePort)
            node.connectionType = .outBound
            node.socket = newNodeSocket
//            nodes.append(node)
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

    private func sendVersionMessage(_ node: Node) {
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
        networkService.sendMessage(node.socket, message)
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
        
        if node.sentVerack == false {
            sendVerackMessage(node)
        }
    }

    private func receiveVerackMessage(_ node: Node) {
        node.receivedVerack = true
        node.receivedNetworkUpdateType = .receivedVerack

        node.receivedVerack = true
    }

    private func sendVerackMessage(_ node: Node) {
        node.sentNetworkUpdateType = .sentVerack
        node.sentVerack = true
        
        let verackMessage = VerackMessage()
        let payload = verackMessage.serialize()
        let message = Message(command: .verack, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        networkService.sendMessage(node.socket, message)
    }

    private func sendPingMessage(_ node: Node) {
        node.sentNetworkUpdateType = .sentPing
        node.sentPing = true
        node.receivedPong = false
        node.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
        node.myPingNonce = generateNonce()
        
        let pingMessage = PingMessage(nonce: node.myPingNonce)
        let payload = pingMessage.serialize()
        let message = Message(command: .ping, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        networkService.sendMessage(node.socket, message)
    }
    
    private func receivePongMessage(_ node: Node, dataByteArray: [UInt8]) -> (expectedNonce: UInt64, receivedNonce: UInt64) {
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

    private func receivePingMessage(_ node: Node, dataByteArray: [UInt8]) {
        node.receivedNetworkUpdateType = .receivedPing
        node.receivedPing = true
        
        let pingMessage = PingMessage.deserialise(dataByteArray)
        node.theirNodePingNonce = pingMessage.nonce
        
        sendPongMessage(node)
    }

    private func sendPongMessage(_ node: Node) {
        node.sentPong = true
        node.sentNetworkUpdateType = .sentPong

        let pongMessage = PongMessage(nonce: node.theirNodePingNonce)
        let payload = pongMessage.serialize()
        let message = Message(command: .pong, length: UInt32(payload.count), checksum: payload.doubleSHA256ToData[0..<4], payload: payload)
        networkService.sendMessage(node.socket, message)
    }
    
    // MARK: -

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
                    // If we've already sent a ping and haven't received a pong,
                    // then disconnect from this node
                    if node.receivedVerack == true
                        && elapsedTime > (randomDuration)
                        && node.sentPing == true
                        && node.receivedPong == false {
                        print("sent Ping but did not receive Pong")
                        shouldKeepRunning = false
                        break
                    }
                    
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
                    
                    if let message = self.networkService.consumeNetworkPackets(node) {
                        let payloadByteArray = Array([UInt8](message.payload))
                        let payloadArrayLength = message.payload.count
                        switch message.command {
                        case .unknown:
                            // Need to set this node as bad
                            break
                        case .version:
                            self.receiveVersionMessage(node, dataByteArray: payloadByteArray, arrayLength: UInt32(payloadArrayLength))
                        case .verack:
                            self.receiveVerackMessage(node)
                        case .ping:
                            self.receivePingMessage(node, dataByteArray: payloadByteArray)
                        case .pong:
                            let (expectedNonce, receivedNonce) = self.receivePongMessage(node, dataByteArray: payloadByteArray)
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
                        }
                    }
                } while shouldKeepRunning

                print("closing socket \(socket.remoteHostname):\(socket.remotePort)...")
                socket.close()
                self.socketLockQueue.sync { [unowned self, socket] in
                    self.connectedSockets[socket.socketfd] = nil
                    self.nodes.removeAll { (thisNode) -> Bool in
                        return thisNode.address == node.address
                            && thisNode.port == node.port
                    }
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
        print("shuttingDown...")
        self.continueRunning = false
        
        // Close all open sockets...
        for socket in connectedSockets.values {
            self.socketLockQueue.sync { [unowned self, socket] in
                self.connectedSockets[socket.socketfd] = nil
                socket.close()
            }
        }
        print("shutdown")
    }
    
    // MARK: -

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
