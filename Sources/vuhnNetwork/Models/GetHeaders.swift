// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// Ask for block headers to be returned
public struct GetHeadersMessage {
//    4    version    uint32_t    the protocol version
//    1+    hash count    var_int    number of block locator hash entries
//    32+    block locator hashes    char[32]    block locator object; newest back to genesis block (dense to start, but then sparse)
//    32    hash_stop    char[32]    hash of the last desired block header; set to zero to get as many blocks as possible (2000)
    
    public static let genesisBlockHash = Data([111, 226, 140, 10, 182, 241, 179, 114, 193, 166, 162, 70, 174, 99, 247, 79, 147, 30, 131, 101, 225, 90, 8, 156, 104, 214, 25, 0, 0, 0, 0, 0])
    
    public init() { }
    
    public init(blockLocatorHashes: [Data] = [GetHeadersMessage.genesisBlockHash]) {
        self.blockLocatorHashes = blockLocatorHashes
    }
    
    /// The protocol version
    var version: UInt32 = UInt32(protocolVersion)
    
    /// Block locator object; newest back to genesis block (dense to start, but then sparse)
    // Default to Genesis block hash
//    var blockLocatorHashes: [String] = ["000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"]
    // 6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000
    
//var blockLocatorHashes: [Data] = [Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])]
    
    
//    var blockLocatorHashes: [Data] = [Data([0x00,0x00,0x00,0x00,0x00,0x19,0xd6,0x68,0x9c,0x08,0x5a,0xe1,0x65,0x83,0x1e,0x93,0x4f,0xf7,0x63,0xae,0x46,0xa2,0xa6,0xc1,0x72,0xb3,0xf1,0xb6,0x0a,0x8c,0xe2,0x6f])]
//    var blockLocatorHashes: [Data] = [Data([111, 226, 140, 10, 182, 241, 179, 114, 193, 166, 162, 70, 174, 99, 247, 79, 147, 30, 131, 101, 225, 90, 8, 156, 104, 214, 25, 0, 0, 0, 0, 0])]
    var blockLocatorHashes: [Data] = [GetHeadersMessage.genesisBlockHash]
    
    
    
    /// Hash of the last desired block header; set to zero to get as many blocks as possible (2000)
    let hasStop: String = ""

    public func serialize() -> Data {
        
        // Genesis block header hash
//        000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f
        
        // On the wire:
//        111, 226, 140, 10, 182, 241, 179, 114, 193, 166, 162, 70, 174, 99, 247, 79, 147, 30, 131, 101, 225, 90, 8, 156, 104, 214, 25, 0, 0, 0, 0, 0
        
        
        var countOfBlockLocatorHashes = 1
        
        print("\(#function) [\(#line)] 🍔 blockLocatorHashes.count == \(blockLocatorHashes.count)")

        let testData = blockLocatorHashes[0];
        print("\(#function) [\(#line)] 🍔 blockLocatorHashes[0].count == \(testData.count)")

        
        if blockLocatorHashes.count > 0 {
            countOfBlockLocatorHashes = blockLocatorHashes.count
            if countOfBlockLocatorHashes > 2000 { countOfBlockLocatorHashes = 2000 }
        }
        print("\(#function) [\(#line)] 🍔")
        print("Number of Block Locator Hashes is \(countOfBlockLocatorHashes)")
        
        var data = Data()
        data += withUnsafeBytes(of: version.littleEndian) { Data($0) }
        print("version = \(version)")
        
        
        if countOfBlockLocatorHashes < 0xFD {
            data += withUnsafeBytes(of: UInt8(countOfBlockLocatorHashes.littleEndian)) { Data($0) }
        } else if countOfBlockLocatorHashes <= 0xFFFF {
            data += withUnsafeBytes(of: [UInt8(0xFD),UInt16(countOfBlockLocatorHashes.littleEndian)]) { Data($0) }
        } else if countOfBlockLocatorHashes <= 0xFFFFFFFF {
            data += withUnsafeBytes(of: [UInt8(0xFE),UInt32(countOfBlockLocatorHashes.littleEndian)]) { Data($0) }
        } else {
            data += withUnsafeBytes(of: [UInt8(0xFF),UInt64(countOfBlockLocatorHashes.littleEndian)]) { Data($0) }
        }
        
//        if let blockLocatorHashes = blockLocatorHashes {
            for blockLocatorHash in blockLocatorHashes {
//                data += blockLocatorHash.data(using: .utf8) ?? Data([UInt8(0x00)])
                data += blockLocatorHash
                print("blockLocatorHash = \(blockLocatorHash)")
            }
//        } else {
//            // Load in the Genesis hash
//            let blockLocatorHash = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
//            data += blockLocatorHash.data(using: .utf8) ?? Data([UInt8(0x00)])
//            print("blockLocatorHash = \(blockLocatorHash)")
//        }

        data += Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

//        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8], arrayLength: UInt32) -> GetHeadersMessage? {
        var offset = 0
        var size = MemoryLayout<UInt32>.size
        
        let version = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        print("version = \(version)")
        

        offset += size
        size = MemoryLayout<UInt8>.size
        var countOfBlockLocatorHashes: Int = 0
        let numOfBlockLocatorHashes = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt8(byte)
        }
        countOfBlockLocatorHashes = Int(numOfBlockLocatorHashes)
        
        // Is varint greater than 252
        if countOfBlockLocatorHashes == 0xFD {
            offset = 1
            size = MemoryLayout<UInt16>.size
            let numOfBlockLocatorHashes = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt16(byte)
            }
            countOfBlockLocatorHashes = Int(numOfBlockLocatorHashes)
        } else if countOfBlockLocatorHashes == 0xFE {
            offset = 1
            size = MemoryLayout<UInt32>.size
            let numOfBlockLocatorHashes = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt32(byte)
            }
            countOfBlockLocatorHashes = Int(numOfBlockLocatorHashes)
        } else if countOfBlockLocatorHashes == 0xFF {
            offset = 1
            size = MemoryLayout<UInt64>.size
            let numOfBlockLocatorHashes = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt64(byte)
            }
            countOfBlockLocatorHashes = Int(numOfBlockLocatorHashes)
        }
        
        print("Number of Block Locator Hashes is \(countOfBlockLocatorHashes)")
        
//        offset += size
//        size = MemoryLayout<UInt8>.size * 32
        
//        let userAgentData: Data = uint8Array.withUnsafeBytes { buf in
//            let mbuf = UnsafeMutablePointer(mutating: buf.bindMemory(to: UInt8.self).baseAddress!)
//            return Data(bytesNoCopy: mbuf.advanced(by: offset), count: size, deallocator: .none)
//        }
//        let userAgent = String(bytes: userAgentData, encoding: .utf8)!.trimmingCharacters(in: .whitespaces)
//        print("userAgent = \(userAgent)")
        
        offset += size
        var extractedBlockLocatorHashes = [Data]()
        for _ in 0..<countOfBlockLocatorHashes {
            size = MemoryLayout<UInt8>.size * 32

            let blockLocatorHashData = Data(Array(uint8Array[offset..<(offset + size)]))
            
            
//            let blockLocatorHashData: Data = uint8Array.withUnsafeBytes { buf in
//                let mbuf = UnsafeMutablePointer(mutating: buf.bindMemory(to: UInt8.self).baseAddress!)
//                return Data(bytesNoCopy: mbuf.advanced(by: offset), count: size, deallocator: .none)
//            }
//            let blockLocatorHash = String(bytes: blockLocatorHashData, encoding: .utf8)!.trimmingCharacters(in: .whitespaces)
//            print("blockLocatorHash = \(blockLocatorHash)")
            
            
//            let blockLocatorHash = uint8Array[offset..<(offset + size)].reversed()
            extractedBlockLocatorHashes.append(blockLocatorHashData)
            offset += size
        }
        
        return GetHeadersMessage(blockLocatorHashes: extractedBlockLocatorHashes)
    }
}
