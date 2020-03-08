// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

let protocolVersion: Int32 = 70_015
let yourUserAgent = "&/vuhnBitcoin:0.0.1(EB32.0; Vuhn; Pay; Vend)/"
//let yourUserAgent = "/Bitcoin ABC:0.19.11(EB32.0)/"


extension UInt64 {
    func toUInt8Array() -> [UInt8] {
        var temp = self
        let count = MemoryLayout<UInt64>.size
        let bytePtr = withUnsafePointer(to: &temp) {
            $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            }
        }
        return Array(bytePtr)
    }
}

func generateNonce() -> UInt64 {
    var returnValue: UInt64 = 1
    let size = MemoryLayout<UInt64>.size
    for shift in (0..<size-1).reversed() {
        let randomByte = UInt8.random(in: 1 ... 255)
        returnValue |= UInt64(randomByte) << (shift * 8)
    }
    return returnValue
}

/// When a node creates an outgoing connection, it will immediately advertise its version.
/// The remote node will respond with its version. No further communication is possible until both peers have exchanged their version.
public struct VersionMessage {

    /// Identifies protocol version being used by the node
    var version: Int32
    
    /// bitfield of features to be enabled for this connection
    var services: UInt64
    
    /// standard UNIX timestamp in seconds
    let timestamp: Int64
    
    /// The network address of the node receiving this message
    let receivingAddress: NetworkAddress
    
    // Fields below require version ≥ 106
    
    /// The network address of the node emitting this message
    var emittingAddress: NetworkAddress?
    
    /// Node random nonce, randomly generated every time a version packet is sent.
    /// This nonce is used to detect connections to self.
    let nonce: UInt64?
    
    /// User Agent (0x00 if string is 0 bytes long)
    /// The user agent that generated messsage.
    /// This is a encoded as a varString
    /// on the wire.
    /// This has a max length of MaxUserAgentLen.
    var userAgent: String?
    
    /// The last block received by the emitting node
    var startHeight: Int32?
    
    // Fields below require version ≥ 70001
    
    /// Whether the remote peer should announce relayed transactions or not, see BIP 0037
    var relay: Bool?

    public func serialize() -> Data {
        var data = Data()
        data += withUnsafeBytes(of: version.littleEndian) { Data($0) }
        print("version = \(version)")
        data += withUnsafeBytes(of: services.littleEndian) { Data($0) }
        print("services = \(services)")
        data += withUnsafeBytes(of: timestamp.littleEndian) { Data($0) }
        print("timestamp = \(timestamp)")
        data += receivingAddress.serialize()
        print("receivingAddress = \(receivingAddress)")
        data += emittingAddress?.serialize() ?? Data(count: 26)
        print("emittingAddress = \(emittingAddress ?? NetworkAddress(services: 0, address: "unknown", port: 0))")
        data += withUnsafeBytes(of: nonce?.littleEndian ?? UInt64(0)) { Data($0) }
        print("nonce = \(nonce ?? 0)")
        if let userAgent = userAgent {
            data += withUnsafeBytes(of: UInt8(userAgent.count)) { Data($0) }
            data += userAgent.data(using: .utf8) ?? Data([UInt8(0x00)])
        } else {
            data += withUnsafeBytes(of: Data([UInt8(0x00)])) { Data($0) }
        }
        print("userAgent = \(userAgent ?? "unknown")")
        data += withUnsafeBytes(of: startHeight?.littleEndian ?? Int32(0)) { Data($0) }
        print("startHeight = \(startHeight ?? -2)")
        if let relay = relay {
            data += relay == true ? Data([UInt8(0x01)]) : Data([UInt8(0x00)])
        } else {
            data += Data([UInt8(0x00)])
        }
        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8], arrayLength: UInt32) -> VersionMessage? {
        var offset = 0
        var size = MemoryLayout<Int32>.size
        
        let version = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | Int32(byte)
        }
        print("version = \(version)")

        offset += size
        size = MemoryLayout<UInt64>.size
        let services = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }
        print("services = \(services)")

        offset += size
        size = MemoryLayout<Int64>.size
        let timestamp = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | Int64(byte)
        }
        print("timestamp = \(timestamp)")
        
        offset += size
        var (newAddress, updatedOffset) = NetworkAddress.deserialise(uint8Array, offset: offset)
        offset = updatedOffset
        let receivingAddress = newAddress
        print("receivingAddress = \(receivingAddress)")
        
        guard Int(arrayLength) - offset > 0 else {
            return VersionMessage(version: version, services: services, timestamp: timestamp, receivingAddress: receivingAddress, emittingAddress: nil, nonce: nil, userAgent: nil, startHeight: nil, relay: nil)
        }
        
        (newAddress, updatedOffset) = NetworkAddress.deserialise(uint8Array, offset: offset)
        offset = updatedOffset
        let emittingAddress = newAddress
        print("emittingAddress = \(emittingAddress)")
        
        size = MemoryLayout<UInt64>.size
        let nonce = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }
        print("nonce = \(nonce)")
        
        offset += size
        size = MemoryLayout<UInt8>.size
        let userAgentSize = uint8Array[offset..<(offset + size)].withUnsafeBytes { $0.load(as: UInt8.self) }

        offset += size
        size = MemoryLayout<UInt8>.size * Int(userAgentSize)
        
        let userAgentData: Data = uint8Array.withUnsafeBytes { buf in
            let mbuf = UnsafeMutablePointer(mutating: buf.bindMemory(to: UInt8.self).baseAddress!)
            return Data(bytesNoCopy: mbuf.advanced(by: offset), count: size, deallocator: .none)
        }
        let userAgent = String(bytes: userAgentData, encoding: .utf8)!.trimmingCharacters(in: .whitespaces)
        print("userAgent = \(userAgent)")
        
        offset += size
        size = MemoryLayout<Int32>.size
        let startHeight = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | Int32(byte)
        }
        print("startHeight = \(startHeight)")
    
        guard Int(arrayLength) - offset > 0 else {
            return VersionMessage(version: version, services: services, timestamp: timestamp, receivingAddress: receivingAddress, emittingAddress: emittingAddress, nonce: nonce, userAgent: userAgent, startHeight: startHeight, relay: nil)
        }

        offset += size
        size = MemoryLayout<Bool>.size
        let relay = Array(uint8Array[offset..<(offset + size)]).first! != 0x00

        return VersionMessage(version: version, services: services, timestamp: timestamp, receivingAddress: receivingAddress, emittingAddress: emittingAddress, nonce: nonce, userAgent: userAgent, startHeight: startHeight, relay: relay)
    }
}
