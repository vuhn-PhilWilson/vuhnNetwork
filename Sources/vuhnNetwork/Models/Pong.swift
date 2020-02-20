// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// The pong message is sent in response to a ping message.
/// In modern protocol versions, a pong response is generated using a nonce included in the ping.
public struct PongMessage {
    /// nonce from ping
    public let nonce: UInt64?
    
    public func serialize() -> Data {
        var data = Data()
        data += withUnsafeBytes(of: nonce?.littleEndian ?? UInt64(0)) { Data($0) }
        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8]) -> PongMessage {
        let offset = 0
        let size = MemoryLayout<UInt64>.size
        
        let nonce = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }
        return PongMessage(nonce: nonce)
    }
}
