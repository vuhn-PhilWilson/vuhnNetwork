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
        listeningSocket?.close()
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
        task.launchPath = "/usr/bin/env"
        task.arguments = ["dig",
                          "+short"]
        for seed in dnsSeeds {
            task.arguments?.append(seed)
        }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
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
                let node = Node(address: address)
                node.connectionType = .outBound
                nodes.append(node)
            }
        }
    }
    
    public func startListening() {
        if listeningPort == -1 { return }

        let queue = concurrentQueue
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
                    print("calling node.connect from startListening()")

                    node.connectionType = .inBound
                    node.connect()
                    
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
        if node.socket != nil {
            node.socket?.close()
            node.socket = nil
        }
        node.connectionType = .outBound
        node.connect()
    }

    func shutdownServer() {
        print("shuttingDown...")
        self.continueRunning = false
        
        for node in nodes {
            node.disconnect()
        }
        listeningSocket?.close()
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
