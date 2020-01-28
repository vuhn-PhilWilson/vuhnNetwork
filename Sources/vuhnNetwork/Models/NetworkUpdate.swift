//
//  NetworkUpdate.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation

public enum NetworkUpdateType {
    case unknown
    
    case addedNodeWithAddress
    case connecting
    case connected
    
    case sentVersion
    case sentVerAck
    case sentPing
    case sentPong
    
    case receivedVersion
    case receivedVerAck
    case receivedPing
    case receivedPong
    
    case awaitingVersion
    case awaitingVerAck
    case awaitingPing
    case awaitingPong
    
    case socketClosing
    case socketClosed
    case socketDisconnected
    
    case receivedInterruptSignal
    case shuttingDown
    case shutDown
    
    public func displayText() -> String {
        switch self {
        case .unknown: return "unknown"
        
        case .addedNodeWithAddress: return "added node with address"
        case .connecting: return "connecting"
        case .connected: return "connected"
            
        case .sentVersion: return "sent Version"
        case .sentVerAck: return "sent VerAck"
        case .sentPing: return "sent Ping"
        case .sentPong: return "sent Pong"
            
        case .receivedVersion: return "received Version"
        case .receivedVerAck: return "received VerAck"
        case .receivedPing: return "received Ping"
        case .receivedPong: return "received Pong"
            
        case .awaitingVersion: return "awaiting Version"
        case .awaitingVerAck: return "awaiting VerAck"
        case .awaitingPing: return "awaiting Ping"
        case .awaitingPong: return "awaiting Pong"
            
        case .socketClosing: return "socket closing"
        case .socketClosed: return "socket closed"
        case .socketDisconnected: return "socket disconnected"
            
        case .receivedInterruptSignal: return "received interrupt signal"
        case .shuttingDown: return "shutting down"
        case .shutDown: return "shutdown"
        }
    }
}

public enum NetworkUpdateLevel {
    case information
    case success
    case warning
    case error
}

public enum NetworkUpdateError {
    case allFine
    case invalidAddress
    case invalidPort
    case invalidNetwork
    case connectionFailure
    case connectionTimeOut
    case receivedMalformedMessage
}

public struct NetworkUpdate {
    public var node: Node? = nil
    public let type: NetworkUpdateType
    let level: NetworkUpdateLevel
    let error: NetworkUpdateError
}
