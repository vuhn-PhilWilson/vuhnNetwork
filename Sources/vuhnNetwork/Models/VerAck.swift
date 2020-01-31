//
//  VerAck.swift
//  
//
//  Created by Phil Wilson on 31/1/20.
//
// https://en.bitcoin.it/wiki/Protocol_documentation#verack

import Foundation

/// The verack message is sent in reply to version.
/// This message consists of only a message header with the command string "verack".
public struct VerAckMessage {
//    Hexdump of the verack message:
//
//    0000   F9 BE B4 D9 76 65 72 61  63 6B 00 00 00 00 00 00   ....verack......
//    0010   00 00 00 00 5D F6 E0 E2                            ........
//
//    Message header:
//     F9 BE B4 D9                          - Main network magic bytes
//     76 65 72 61  63 6B 00 00 00 00 00 00 - "verack" command
//     00 00 00 00                          - Payload is 0 bytes long
//     5D F6 E0 E2                          - Checksum (little endian)
    
    public func serialize() -> Data {
        return Data()
    }
    
}
