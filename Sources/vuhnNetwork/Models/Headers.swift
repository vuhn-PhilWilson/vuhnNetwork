// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// Ask for block headers to be returned
public struct HeadersMessage {

    public init() { }
    
    public init(headers: [Header]) {
        self.blockHeaders = headers
    }
    
    /// The number of block headers
    // VarInt
    // 253, 208, 7 = 2,000 = 7*256 + 208
    var count: UInt64 = 0
    
    var blockHeaders = [Header]()

/*
    public func serialize() -> Data {

        var countOfBlockHeaders = blockHeaders.count
        if countOfBlockHeaders > 2000 { countOfBlockHeaders = 2000 }
        
        print("Number of Block Headers is \(countOfBlockHeaders)")
        
        var data = Data()
        data += withUnsafeBytes(of: version.littleEndian) { Data($0) }
        print("version = \(version)")
        
        
        if countOfBlockHeaders < 0xFD {
            data += withUnsafeBytes(of: UInt8(countOfBlockHeaders.littleEndian)) { Data($0) }
        } else if countOfBlockHeaders <= 0xFFFF {
            data += withUnsafeBytes(of: [UInt8(0xFD),UInt16(countOfBlockHeaders.littleEndian)]) { Data($0) }
        } else if countOfBlockHeaders <= 0xFFFFFFFF {
            data += withUnsafeBytes(of: [UInt8(0xFE),UInt32(countOfBlockHeaders.littleEndian)]) { Data($0) }
        } else {
            data += withUnsafeBytes(of: [UInt8(0xFF),UInt64(countOfBlockHeaders.littleEndian)]) { Data($0) }
        }
        
        for index in 0..<countOfBlockHeaders {
            let blockHeader = blockHeaders[index]
            data += blockHeader.serialize()
            
        }
        return data
    }
    */
    public static func deserialise(_ uint8Array: [UInt8]) -> HeadersMessage? {
        var offset = 0
        var size = MemoryLayout<UInt8>.size
        var countOfBlockHeaders: Int = 0
        let numOfBlockHeaders = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt8(byte)
        }
        countOfBlockHeaders = Int(numOfBlockHeaders)
        
        // Is varint greater than 252
        if countOfBlockHeaders == 0xFD {
            offset = 1
            size = MemoryLayout<UInt16>.size
            let numOfBlockHeaders = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt16(byte)
            }
            countOfBlockHeaders = Int(numOfBlockHeaders)
        } else if countOfBlockHeaders == 0xFE {
            offset = 1
            size = MemoryLayout<UInt32>.size
            let numOfBlockHeaders = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt32(byte)
            }
            countOfBlockHeaders = Int(numOfBlockHeaders)
        } else if countOfBlockHeaders == 0xFF {
            offset = 1
            size = MemoryLayout<UInt64>.size
            let numOfBlockHeaders = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt64(byte)
            }
            countOfBlockHeaders = Int(numOfBlockHeaders)
        }
        
        print("Number of Block Headers is \(countOfBlockHeaders)")

        offset += size
        var headers = [Header]()

        size = 81
        for _ in 0..<countOfBlockHeaders {

            let headerDataArray = [UInt8](uint8Array[offset..<(offset + size)])
            offset += size

            if let header = Header.deserialise(headerDataArray) {
                headers.append(header)
            }
        }
        return HeadersMessage(headers: headers)
    }
}
