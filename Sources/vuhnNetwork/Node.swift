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
    var sentVerAck = false
    var sentPing = false
    var sentPong = false
    
    var receivedVersion = false
    var receivedVerAck = false
    var receivedPing = false
    var receivedPong = false
    
    var lastPingReceivedTimeInterval: TimeInterval
    
    public var address: String
    public var port: Int32
    var socket: Socket?
    public var connectionType = ConnectionType.unknown
    
    public var sentNetworkUpdateType = NetworkUpdateType.unknown
    public var receivedNetworkUpdateType = NetworkUpdateType.unknown
    
    public init(address: String, port: Int32 = 8333) {
        let (anAddress, aPort) = NetworkAddress.extractAddress(address, andPort: port)
        self.address = anAddress
        self.port = aPort
        self.lastPingReceivedTimeInterval = NSDate().timeIntervalSince1970
    }
}
