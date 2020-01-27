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
        print("listenPort = \(listenPort)")
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
                print("Listening on port: \(socket.listeningPort)")
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()
                    
                    print("Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")
                    print("Socket Signature: \(String(describing: newSocket.signature?.description))")

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
        print("connectToAllNodes")
        for node in nodes {
            connectToNode(node: node)
        }
    }
    
    func connectToNode(node: Node) {
        print("connect to node \(node.address):\(node.port)")

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
                // Write the welcome string...
                //try socket.write(from: "Hello, type 'QUIT' to end session\nor 'SHUTDOWN' to stop server.\n")

                var networkUpdate = NetworkUpdate(type: .connected, level: .information, error: .allFine)
                networkUpdate.node = node
                self.updateHandler?(["\(node.address)":networkUpdate], nil)
                
                repeat {
                    
                    // If we've never sent Version message, send it now
                    if node.sentVersion == false {
                        node.sentVersion = true
//                        print("Sending Version")
                        networkUpdate = NetworkUpdate(type: .sentVersion, level: .success, error: .allFine)
                        networkUpdate.node = node
                        self.updateHandler?(["\(node.address)":networkUpdate], nil)
                        try socket.write(from: "Version")
                        continue
                    }
                    
                    // Send a Ping message periodically
                    // to check whether the remote node is still around
                    let elapsedTime = (NSDate().timeIntervalSince1970 - node.lastPingReceivedTimeInterval)
                    if node.receivedVerAck == true
                        && elapsedTime > (Constants.pingDuration / 1000) {
                        node.sentPing = true
                        node.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
//                        print("Sending Ping")
                        networkUpdate = NetworkUpdate(type: .sentPing, level: .success, error: .allFine)
                        networkUpdate.node = node
                        self.updateHandler?(["\(node.address)":networkUpdate], nil)
                        try socket.write(from: "Ping")
                        // continue
                    }
                    
                    // Read incoming data
                    let bytesRead = try socket.read(into: &readData)
                    
                    if bytesRead > 0 {
                        guard let response = String(data: readData, encoding: .utf8) else {
                            
                            print("Error decoding response...")
                            readData.count = 0
                            break
                        }

                        if response.hasPrefix(EchoServer.shutdownCommand) {
                            
                            print("Shutdown requested by connection at \(socket.remoteHostname):\(socket.remotePort)")
                            
                            // Shut things down...
                            self.shutdownServer()

                            DispatchQueue.main.sync {
                                exit(0)
                            }
                        }

//                        print("Server received from connection at \(socket.remoteHostname):\(socket.remotePort): \(response) ")
                        
                        if response.hasPrefix("Version") {
//                            print("Received Version")
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
//                            print("Sending VerAck")
                            networkUpdate = NetworkUpdate(type: .sentVerAck, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            try socket.write(from: "VerAck")
                        }
                        
                        if response.hasPrefix("VerAck") {
//                            print("Received VerAck")
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
                            print("Received Ping")
                            networkUpdate = NetworkUpdate(type: .receivedPing, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            node.receivedNetworkUpdateType = .receivedPing
                            node.receivedPing = true
                            
                            node.sentNetworkUpdateType = .sentPong
                            node.sentPong = true
                            print("Sending Pong")
                            networkUpdate = NetworkUpdate(type: .sentPong, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            try socket.write(from: "Pong")
                        }
                        
                        if response.hasPrefix("Pong") {
                            print("Received Pong")
                            networkUpdate = NetworkUpdate(type: .receivedPong, level: .success, error: .allFine)
                            networkUpdate.node = node
                            self.updateHandler?(["\(node.address)":networkUpdate], nil)
                            node.receivedNetworkUpdateType = .receivedPong
                            node.receivedPong = true
                            
                            // Compare Nonce with the one we sent
                            // Only if this remote node uses Nonces with Ping/Pong
                        }
                        
//                        let reply = "Server response: \n\(response)\n"
//                        try socket.write(from: reply)
                        
//                        if (response.uppercased().hasPrefix(EchoServer.quitCommand) || response.uppercased().hasPrefix(EchoServer.shutdownCommand)) &&
//                            (!response.hasPrefix(EchoServer.quitCommand) && !response.hasPrefix(EchoServer.shutdownCommand)) {
//
//                            try socket.write(from: "If you want to QUIT or SHUTDOWN, please type the name in all caps. 😃\n")
//                        }
                        
                        if response.hasPrefix(EchoServer.quitCommand) || response.hasSuffix(EchoServer.quitCommand) {
                            
                            shouldKeepRunning = false
                        }
                    }
                    
                    if bytesRead == 0
                        && socket.remoteConnectionClosed == true {
                        shouldKeepRunning = false
                        break
                    }
                    
                    readData.count = 0
                    
                } while shouldKeepRunning
                
                print("Socket: \(socket.remoteHostname):\(socket.remotePort) closed...")
                socket.close()
                
                print("Removing this socket from socket array")
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
