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
    
    var port: Int = 8333
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
        self.port = listenPort
        for address in addresses {
            if ConnectionsManager.isValidAddress(address: address) {
                let node = Node(address: address)
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
                
                try socket.listen(on: self.port)
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()

                    // Set how long we'll wait with no received
                    // data before we Ping the remote node
                    try newSocket.setReadTimeout(value: UInt(Constants.pingDuration))
                    
                    let node = Node(address: newSocket.remoteHostname, port: newSocket.remotePort)
                    node.connectionType = .inBound
                    node.socket = newSocket
                    self.nodes.append(node)
                    self.addNewConnection(node: node)
                    
                } while self.continueRunning
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error...")
                    return
                }
                
                if self.continueRunning {
                    
                    print("Error reported:\n \(socketError.description)")
                    
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
            let newNodeSocket = try Socket.create(family: .inet)
            // What buffer size shall we use ?
//            newNodeSocket.readBufferSize = 32768
            try newNodeSocket.connect(to: node.address, port: node.port, timeout: 10)

            var networkUpdate = NetworkUpdate(type: .connected, level: .information, error: .allFine)
            networkUpdate.node = node
            updateHandler?(["\(node.address):\(node.port)":networkUpdate], nil)

            // Set how long we'll wait with no received
            // data before we Ping the remote node
            try newNodeSocket.setReadTimeout(value: UInt(Constants.pingDuration))
            
            let node = Node(address: newNodeSocket.remoteHostname, port: newNodeSocket.remotePort)
            node.connectionType = .outBound
            node.socket = newNodeSocket
            nodes.append(node)
            addNewConnection(node: node)
        }
        catch let error {
            guard let socketError = error as? Socket.Error else {
                print("Unexpected error...")
                return
            }
            // is error reported on connection close ?
            print("Error reported:\n \(socketError.description)")
        }
    }
    
    // MARK: - Messages
    
    private func sendMessage(_ socket: Socket, _ message: Message) {
        let data = message.serialize()
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

    private func sendVersionMessage(_ socket: Socket) {
        let version = VersionMessage(version: protocolVersion,
                                     services: 0x00,
                                     timestamp: Int64(Date().timeIntervalSince1970),
                                     receivingAddress: NetworkAddress(services: 0x00,
                                                              address: "::ffff:127.0.0.1",
                                                              port: UInt16(port)),
                                     emittingAddress: NetworkAddress(services: 0x00,
                                                              address: "::ffff:127.0.0.1",
                                                              port: UInt16(port)),
                                     nonce: 0,
                                     userAgent: yourUserAgent,
                                     startHeight: -1,
                                     relay: false)
        let message = Message(command: .Version, payload: version.serialize())
        sendMessage(socket, message)
    }
    
    // MARK: -
    
    func addNewConnection(node: Node) {
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
            var readData = Data(capacity: EchoServer.bufferSize)
            
            do {
                var networkUpdate = NetworkUpdate(type: .connected, level: .information, error: .allFine)
                networkUpdate.node = node
                self.updateHandler?(["\(node.address)":networkUpdate], nil)
                
                repeat {
                    
                    // If we've never sent Version message, send it now
                    if node.sentVersion == false {
                        node.sentVersion = true
                        networkUpdate = NetworkUpdate(type: .sentVersion, level: .success, error: .allFine)
                        networkUpdate.node = node
                        self.updateHandler?(["\(node.address)":networkUpdate], nil)
                        
                        self.sendVersionMessage(socket)
                        continue
                    }
                    
                    // Send a Ping message periodically
                    // to check whether the remote node is still around
                    let elapsedTime = (NSDate().timeIntervalSince1970 - node.lastPingReceivedTimeInterval)
                    if node.receivedVerAck == true
                        && elapsedTime > (Constants.pingDuration / 1000) {
                        node.sentPing = true
                        node.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
                        networkUpdate = NetworkUpdate(type: .sentPing, level: .success, error: .allFine)
                        networkUpdate.node = node
                        self.updateHandler?(["\(node.address)":networkUpdate], nil)
                        try socket.write(from: "Ping")
                    }
                    
                    // Read incoming data
                    let bytesRead = try socket.read(into: &readData)
                    
                    if bytesRead > 0 {
//                        guard let response = String(data: readData, encoding: .utf8) else {
//                            print("Error decoding response...")
//                            readData.count = 0
//                            break
//                        }

//                        if response.hasPrefix(EchoServer.shutdownCommand) {
//                            print("Shutdown requested by connection at \(socket.remoteHostname):\(socket.remotePort)")
//                            // Shut things down...
//                            self.shutdownServer()
//                            DispatchQueue.main.sync {
//                                exit(0)
//                            }
//                        }
                        
                        // Extract Message data
                        let byteArray = Array([UInt8](readData))
                        let message = Message.deserialise(byteArray, length: UInt32(bytesRead))
                        
//                        let magic = readData.read(UInt32.self)
//                        let command = byteStream.read(Data.self, count: 12).to(type: String.self)
//                        let length = byteStream.read(UInt32.self)
//                        let checksum = byteStream.read(Data.self, count: 4)
                        
//                        let magic = byteStream.read(UInt32.self)
//                        let command = byteStream.read(Data.self, count: 12).to(type: String.self)
//                        let length = byteStream.read(UInt32.self)
//                        let checksum = byteStream.read(Data.self, count: 4)
                        
                        
                        
                        /*
                        if response.hasPrefix("Version") {
                            networkUpdate = NetworkUpdate(type: .receivedVersion, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            node.receivedNetworkUpdateType = .receivedVersion
                            if node.receivedVersion == true {
                                // Already received Version message from this node
                                // Should now begin to record bad remote node behaviour
                            }
                            node.receivedVersion = true
    
                            node.sentNetworkUpdateType = .sentVerAck
                            node.sentVerAck = true
                            networkUpdate = NetworkUpdate(type: .sentVerAck, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            try socket.write(from: "VerAck")
                        }
                        
                        if response.hasPrefix("VerAck") {
                            networkUpdate = NetworkUpdate(type: .receivedVerAck, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            node.receivedNetworkUpdateType = .receivedVerAck
                            if node.receivedVersion == true {
                                // Already received Version message from this node
                                // Should now begin to record bad remote node behaviour
                            }
                            node.receivedVerAck = true
                        }
                        
                        if response.hasPrefix("Ping") {
                            networkUpdate = NetworkUpdate(type: .receivedPing, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            node.receivedNetworkUpdateType = .receivedPing
                            node.receivedPing = true
                            
                            node.sentNetworkUpdateType = .sentPong
                            node.sentPong = true
                            networkUpdate = NetworkUpdate(type: .sentPong, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            try socket.write(from: "Pong")
                        }
                        
                        if response.hasPrefix("Pong") {
                            networkUpdate = NetworkUpdate(type: .receivedPong, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            node.receivedNetworkUpdateType = .receivedPong
                            node.receivedPong = true
                            
                            // Compare Nonce with the one we sent
                            // Only if this remote node uses Nonces with Ping/Pong
                        }
                        if response.hasPrefix(EchoServer.quitCommand) || response.hasSuffix(EchoServer.quitCommand) {
                            shouldKeepRunning = false
                        }
                        */
                    }
                    
                    if bytesRead == 0
                        && socket.remoteConnectionClosed == true {
                        shouldKeepRunning = false
                        break
                    }
                    
                    readData.count = 0
                    
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
                    print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
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
