//
//  NetworkUpdate.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation

public enum NetworkUpdateType {
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
    case disconnected
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
    let type: NetworkUpdateType
    let level: NetworkUpdateLevel
    let error: NetworkUpdateError
}
