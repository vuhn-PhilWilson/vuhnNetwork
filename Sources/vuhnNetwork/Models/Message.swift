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
    case Verack
    case Ping
    case Pong
    case Addr
    case Inv
    case Getheaders
    case Sendheaders
    case Sendcmpct
    
    var onWireName: String {
        get {
            return self.rawValue.lowercased()
        }
    }
    
    static func offWireName(text: String) -> String {
        return text.lowercased().capitalized
    }
    
    // Command string is a maximum 12 characters long
    // Needs to pad with 0x00, not " "
    var toData: Data {
        let nameWithPaddingSpaces = self.onWireName.padding(toLength: 12, withPad: " ", startingAt: 0).trimmingCharacters(in: .whitespaces)
        var nameData = nameWithPaddingSpaces.data(using: .utf8)!
        nameData.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        nameData.removeLast(nameData.count - 12)
        return nameData
    }
}

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
    public var length: UInt32
    
    /// First 4 bytes of sha256(sha256(payload))
    /// Computed from payload data
    public var checksum: Data
    
    /// The actual data
    public var payload: Data
    
    public func serialize() -> Data {
        var data = Data()
        data += magic.bigEndian.data
        data += command.toData
        data += withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Data($0) }
        data += checksum
        data += payload
        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8], arrayLength: UInt32) -> Message? {
        if uint8Array.count < 24 { return nil }
        var offset = 0
        var size = MemoryLayout<UInt32>.size
        
        let magic = uint8Array[offset..<(offset + size)].reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        guard magic == 0xe3e1f3e8 else { return nil }
        
        offset += size
        size = MemoryLayout<UInt8>.size * 12
        var commandType: CommandType? = CommandType.Unknown
        let commandArray = uint8Array[offset..<(offset + size)].filter { $0 != 0 }
        if let commandString = String(bytes: commandArray, encoding: .utf8) {
            commandType = CommandType(rawValue: CommandType.offWireName(text: commandString))
            if commandType == nil {
                commandType = .Unknown
            }
        }
        
        offset += size
        size = MemoryLayout<UInt32>.size
        let length = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        offset += size
        size = MemoryLayout<UInt8>.size * 4
        let checksum = Array(uint8Array[offset..<(offset + size)])
        
        if arrayLength <= 24 {
            return Message(magic: magic, command: commandType ?? .Unknown, length: UInt32(length), checksum: Data(checksum), payload: Data())
        }

        var payload = Data()
        if (offset + size) < arrayLength {
            offset += size
            size = Int(length)
            let payloadArray = Array(uint8Array[offset..<(offset + size)])
            payload = Data(payloadArray)
        }
        
        // Confirm checksum is correct
        let checksumFromPayload =  Array(payload.doubleSHA256ToData[0..<4])
        var checksumConfirmed = true
        for (index, element) in checksumFromPayload.enumerated() {
            if checksum[index] != element { checksumConfirmed = false; break }
        }
        if checksumConfirmed == false { return nil }

        let newMessage = Message(magic: magic, command: commandType ?? .Unknown, length: UInt32(length), checksum: Data(checksum), payload: payload)
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

