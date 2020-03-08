// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation
import Cryptor

// Known fourCC values:
//
// Network      FourCC value    Sent over wire as
// main         0xD9B4BEF9      F9 BE B4 D9
// testnet      0xDAB5BFFA      FA BF B5 DA
// testnet3     0x0709110B      0B 11 09 07
// namecoin     0xFEB4BEF9      F9 BE B4 FE
    

// > fourCC
//      |
//      └── UInt32 ( four bytes )
//      |
//      └── commands
//             |
//             └── command1 ( version )
//             |
//             └── command2 ( verack )
//             |
//             └── command3 ( ping )
//             |
//             └── command4 ( pong )
//             |
//             └── command5 ( xx1 )
//             |
//             └── command5 ( xx2 )
//             |
//             └── command5 ( xx3 )

public struct FourCC: Codable {
    var characterCode = [UInt8](repeating: 0x00, count: 4)

    public enum Command: String, Codable {
        case unknown, version, verack, ping, pong
        case getaddr, addr, inv, getheaders, sendheaders, sendcmpct
        case feefilter, protoconf, xversion, xverack
        
        // Command string is a maximum 12 characters long
        // Needs to pad with 0x00, not " "
        var toData: Data {
            let nameWithPaddingSpaces = self.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0).trimmingCharacters(in: .whitespaces)
            var nameData = nameWithPaddingSpaces.data(using: .utf8)!
            nameData.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            nameData.removeLast(nameData.count - 12)
            return nameData
        }
    }
    
    var command = Command.unknown
}

public struct Message: Codable {

    /// FOURCC:
    /// Class of Message
    var fourCC: FourCC = FourCC(characterCode: [0xe3, 0xe1, 0xf3, 0xe8], command: .unknown)
    
    /// TYPE
    /// ASCII string identifying the message type for the given class
    var command: FourCC.Command
    
    /// LENGTH
    /// Size of payload in bytes
    var length: UInt32
    
    /// CHECKSUM
    /// First 4 bytes of sha256(sha256(payload))
    /// Computed from value data
     var checksum: Data
    
    /// VALUE
    /// The actual payload data
    var payload: Data
    
    func serialize() -> Data {
        var data = Data()
        let characterCode = fourCC.characterCode.reduce(0) { soFar, byte in return soFar << 8 | UInt32(byte) }
        data += characterCode.bigEndian.data
        data += command.toData
        data += withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Data($0) }
        data += checksum
        data += payload
        return data
    }
    
    static func deserialise(_ uint8Array: [UInt8], arrayLength: UInt32) -> Message? {
        if uint8Array.count < 24 { return nil }
        var offset = 0
        var size = MemoryLayout<UInt32>.size
        
        let fourBytes = Array(uint8Array[offset..<(offset + size)])
        let fourCC = FourCC(characterCode: fourBytes, command: .unknown)
        
        guard fourCC.characterCode == [0xe3, 0xe1, 0xf3, 0xe8] else {
            return nil
        }
        
        offset += size
        size = MemoryLayout<UInt8>.size * 12
        var commandType: FourCC.Command? = FourCC.Command.unknown
        let commandArray = uint8Array[offset..<(offset + size)].filter { $0 != 0 }
        if let commandString = String(bytes: commandArray, encoding: .utf8) {
            // print("\(commandString)")
            commandType = FourCC.Command(rawValue: commandString)
            if commandType == nil {
                commandType = .unknown
            }
        }
        
        offset += size
        size = MemoryLayout<UInt32>.size
        let length = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        if arrayLength < length {
            return nil
        }
        
        offset += size
        size = MemoryLayout<UInt8>.size * 4
        let checksum = Array(uint8Array[offset..<(offset + size)])
        
        if length == 0 {
            return Message(fourCC: fourCC, command: commandType ?? .unknown, length: UInt32(length), checksum: Data(checksum), payload: Data())
        }

        var payload = Data()
        offset += size
        if length > 0
            && (UInt32(offset) + length) <= arrayLength {
            size = Int(length)
            let payloadArray = Array(uint8Array[offset..<(offset + size)])
            payload = Data(payloadArray)
        } else {
            return nil
        }
        
        // Confirm checksum is correct
        let checksumFromPayload =  Array(payload.doubleSHA256ToData[0..<4])
        var checksumConfirmed = true
        for (index, element) in checksumFromPayload.enumerated() {
            if checksum[index] != element { checksumConfirmed = false; break }
        }

        if checksumConfirmed == false {
            return nil
        }

        let newMessage = Message(fourCC: fourCC, command: commandType ?? .unknown, length: UInt32(length), checksum: Data(checksum), payload: payload)
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

