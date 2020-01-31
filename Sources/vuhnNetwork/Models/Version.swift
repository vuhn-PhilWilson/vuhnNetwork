//
//  Version.swift
//  
//
//  Created by Phil Wilson on 29/1/20.
//

import Foundation

let protocolVersion: Int32 = 70_015
let yourUserAgent = "&/vuhnBitcoin:0.0.1(EB32.0; Vuhn; Pay; Vend)/"

/// When a node creates an outgoing connection, it will immediately advertise its version.
/// The remote node will respond with its version. No further communication is possible until both peers have exchanged their version.
public struct VersionMessage {

    /// Identifies protocol version being used by the node
    let version: Int32
    
    /// bitfield of features to be enabled for this connection
    let services: UInt64
    
    /// standard UNIX timestamp in seconds
    let timestamp: Int64
    
    /// The network address of the node receiving this message
    let receivingAddress: NetworkAddress
    
    // Fields below require version ≥ 106
    
    /// The network address of the node emitting this message
    let emittingAddress: NetworkAddress?
    
    /// Node random nonce, randomly generated every time a version packet is sent.
    /// This nonce is used to detect connections to self.
    let nonce: UInt64?
    
    /// User Agent (0x00 if string is 0 bytes long)
    /// The user agent that generated messsage.  This is a encoded as a varString
    /// on the wire.  This has a max length of MaxUserAgentLen.
    let userAgent: String?
    
    /// The last block received by the emitting node
    let startHeight: Int32?
    
    // Fields below require version ≥ 70001
    
    /// Whether the remote peer should announce relayed transactions or not, see BIP 0037
    let relay: Bool?

    public func serialize() -> Data {
        var data = Data()
        data += withUnsafeBytes(of: version.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: services.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: timestamp.littleEndian) { Data($0) }
        data += receivingAddress.serialize()
        data += emittingAddress?.serialize() ?? Data(count: 26)
        data += withUnsafeBytes(of: nonce?.littleEndian ?? UInt64(0)) { Data($0) }
        if let userAgent = userAgent {
            data += withUnsafeBytes(of: UInt8(userAgent.count)) { Data($0) }
            data += userAgent.data(using: .utf8) ?? Data([UInt8(0x00)])
        } else {
            data += withUnsafeBytes(of: Data([UInt8(0x00)])) { Data($0) }
        }
        data += withUnsafeBytes(of: startHeight?.littleEndian ?? Int32(0)) { Data($0) }
        if let relay = relay {
            data += relay == true ? Data([UInt8(0x01)]) : Data([UInt8(0x00)])
        } else {
            data += Data([UInt8(0x00)])
        }
        return data
    }
    
    public static func deserialise(_ data: Data) -> VersionMessage? {
        var offset = 0
        var size = MemoryLayout<Int32>.size
        
        let version = data[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | Int32(byte)
        }

        offset += size
        size = MemoryLayout<UInt64>.size
        let services = data[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }

        offset += size
        size = MemoryLayout<Int64>.size
        let timestamp = data[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | Int64(byte)
        }
        
        offset += size
        var (newAddress, updatedOffset) = NetworkAddress.deserialize(data: data, offset: offset)
        offset = updatedOffset
        let receivingAddress = newAddress
        
        guard data.count - offset > 0 else {
            return VersionMessage(version: version, services: services, timestamp: timestamp, receivingAddress: receivingAddress, emittingAddress: nil, nonce: nil, userAgent: nil, startHeight: nil, relay: nil)
        }
        
        (newAddress, updatedOffset) = NetworkAddress.deserialize(data: data, offset: offset)
        offset = updatedOffset
        let emittingAddress = newAddress
        
        size = MemoryLayout<UInt64>.size
        let nonce = data[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }
        
        offset += size
        size = MemoryLayout<UInt8>.size
        let userAgentSize = data[offset..<(offset + size)].withUnsafeBytes { $0.load(as: UInt8.self) }

        offset += size
        size = MemoryLayout<UInt8>.size * Int(userAgentSize)
        
        let userAgentData: Data = data.withUnsafeBytes { buf in
            let mbuf = UnsafeMutablePointer(mutating: buf.bindMemory(to: UInt8.self).baseAddress!)
            return Data(bytesNoCopy: mbuf.advanced(by: offset), count: size, deallocator: .none)
        }
        let userAgent = String(bytes: userAgentData, encoding: .utf8)!.trimmingCharacters(in: .whitespaces)
        
        offset += size
        size = MemoryLayout<Int32>.size
        let startHeight = data[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | Int32(byte)
        }
    
        guard data.count - offset > 0 else {
            return VersionMessage(version: version, services: services, timestamp: timestamp, receivingAddress: receivingAddress, emittingAddress: emittingAddress, nonce: nonce, userAgent: userAgent, startHeight: startHeight, relay: nil)
        }

        offset += size
        size = MemoryLayout<Bool>.size
        let relay = Array(data[offset..<(offset + size)]).first! != 0x00

        return VersionMessage(version: version, services: services, timestamp: timestamp, receivingAddress: receivingAddress, emittingAddress: emittingAddress, nonce: nonce, userAgent: userAgent, startHeight: startHeight, relay: relay)
    }
}
