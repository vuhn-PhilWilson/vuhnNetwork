//
//  Node.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation
import Socket

public class Node {
    
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

    var sentVersion = false
    var sentVerack = false
    var sentPing = false
    var sentPong = false
    
    var receivedVersion = false
    var receivedVerack = false
    var receivedPing = false
    var receivedPong = false
    
    var lastPingReceivedTimeInterval: TimeInterval
    
    public var packageData: Data
    
    public var address: String
    public var port: UInt16
    var socket: Socket?
    public var connectionType = ConnectionType.unknown
    
    /// Identifies protocol version being used by the node
    var version: Int32
    
    /// The network address of this node
    var emittingAddress: NetworkAddress
    
    /// bitfield of features to be enabled for this connection
    var services: UInt64
    
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
    
    public var name: String {
        get {
            return "\(address):\(port)"
        }
    }
    
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
        self.packageData = Data()
    }
}
