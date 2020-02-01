//
//  Message.swift
//  
//
//  Created by Phil Wilson on 29/1/20.
//

import Foundation
import Cryptor

public enum CommandType: String, Codable {
    case Unknown
    case Version
    case VerAck
    case Ping
    case Pong
    
    // Command string is a maximum 12 characters long
    // Needs to pad with 0x00, not " "
    var toData: Data {
        return self.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0).data(using: .utf8)!
//        return Data(self.rawValue.padding(toLength: 12, withPad: "", startingAt: 0))
    }
}


// Command string is a maximum 12 characters long
//var toCommandString: String? {
//    return String(bytes: self, encoding: .utf8)?.padding(toLength: 12, withPad: "", startingAt: 0)
//}

// Known magic values:
//
// Network      Magic value     Sent over wire as
// main         0xD9B4BEF9      F9 BE B4 D9
// testnet      0xDAB5BFFA      FA BF B5 DA
// testnet3     0x0709110B      0B 11 09 07
// namecoin     0xFEB4BEF9      F9 BE B4 FE
    

public struct Message: Codable {
    /// Magic value indicating message origin network,
    /// and used to seek to next message when stream state is unknown
    public var magic: UInt32 = 0xe3e1f3e8
    
    /// ASCII string identifying the packet content, NULL padded
    /// (non-NULL padding results in packet rejected)
    public var command: CommandType
    
    /// Length of payload in number of bytes
    /// Computed from payload data
    public var length: UInt32 {
        return UInt32(payload.count)
    }
    
    /// First 4 bytes of sha256(sha256(payload))
    /// Computed from payload data
    public var checksum: Data {
        return payload.doubleSHA256ToData[0..<4]
    }
    
    /// The actual data
    public var payload: Data
    
    public func serialize() -> Data {
        var data = Data()
        data += magic.bigEndian.data
        data += command.toData
        data += withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Data($0) }
        data += checksum
//        print("checksum = <\(Array([UInt8](checksum)))>")

        
        data += payload
        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8], arrayLength: UInt32) -> Message? {
        var offset = 0
        var size = MemoryLayout<UInt32>.size
        
        let magic = uint8Array[offset..<(offset + size)].reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        guard magic == 0xe3e1f3e8 else {
            print("magic != 0xe3e1f3e8\nmagic == \(magic)")
            return nil
        }
//        print("magic == 0xe3e1f3e8")
        
        offset += size
        size = MemoryLayout<UInt8>.size * 12
        let commandData = uint8Array[offset..<(offset + size)]
        let command = String(bytes: commandData, encoding: .utf8)!.trimmingCharacters(in: .whitespaces)

        offset += size
        size = MemoryLayout<UInt32>.size
        let length = Array(uint8Array[offset..<(offset + size)]).first!
        
        offset += size
        size = MemoryLayout<UInt8>.size * 4
        var checksum = Array(uint8Array[offset..<(offset + size)])
//        print("checksum = <\(checksum)>")
//        checksum[2] = 0xee
//        print("checksum changed = <\(checksum)>")
        
        offset += size
        size = Int(length)
        let payloadArray = Array(uint8Array[offset..<(offset + size)])
        let payload = Data(payloadArray)
        
        // Confirm checksum is correct
        let checksumFromPayload =  Array(payload.doubleSHA256ToData[0..<4])
//        print("checksumFromPayload = <\(checksumFromPayload)>")
        var checksumConfirmed = true
        for (index, element) in checksumFromPayload.enumerated() {
            if checksum[index] != element { checksumConfirmed = false; break }
        }
//        print("checksumConfirmed = <\(checksumConfirmed)>")
        
        let newMessage = Message(magic: magic, command: CommandType(rawValue: command) ?? .Unknown, payload: payload)
        return newMessage
    }
}

protocol DataConvertible {
    init?(data: Data)
    var data: Data { get }
}

extension DataConvertible where Self: ExpressibleByIntegerLiteral{
    init?(data: Data) {
        var value: Self = 0
        guard data.count == MemoryLayout.size(ofValue: value) else { return nil }
        _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
        self = value
    }

    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt32 : DataConvertible { }
extension Int : DataConvertible { }
extension Float : DataConvertible { }
extension Double : DataConvertible { }
extension String : DataConvertible {
    init?(data: Data) {
        self.init(data: data, encoding: .utf8)
    }
    var data: Data {
        // Note: a conversion to UTF-8 cannot fail.
        return Data(self.utf8)
    }
}
