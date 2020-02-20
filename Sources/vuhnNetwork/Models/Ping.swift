// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// The ping message is sent primarily to confirm that the TCP/IP connection is still valid.
/// An error in transmission is presumed to be a closed connection and the address is removed as a current peer.
public struct PingMessage {
    /// random nonce
    public let nonce: UInt64?
    
    public func serialize() -> Data {
        var data = Data()
        data += withUnsafeBytes(of: nonce?.littleEndian ?? UInt64(0)) { Data($0) }
        return data
    }
    
//    public static func deserialise(_ data: Data) -> PingMessage {
//        let size = MemoryLayout<UInt64>.size
//        let nonce = data[0..<size].reversed().reduce(0) { soFar, byte in
//            return soFar << 8 | UInt64(byte)
//        }
//        return PingMessage(nonce: nonce)
//    }
    
    public static func deserialise(_ uint8Array: [UInt8]) -> PingMessage {
        let offset = 0
        let size = MemoryLayout<UInt64>.size
        
        let nonce = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }
        return PingMessage(nonce: nonce)
    }
}
