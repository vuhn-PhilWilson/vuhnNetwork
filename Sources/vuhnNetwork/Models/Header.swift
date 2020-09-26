// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation
import Cryptor

/// Ask for block headers to be returned
public struct Header {
    
    public init() { }
    
    public init(
        version: UInt32,
        prevBlock: Data,
        merkleRoot: Data,
        timestamp: UInt32,
        bits: UInt32,
        nonce: UInt32,
        txnCount: UInt8) {
        self.version = version
        self.prevBlock = prevBlock
        self.merkleRoot = merkleRoot
        self.timestamp = timestamp
        self.bits = bits
        self.nonce = nonce
        self.txnCount = txnCount

        self.blockHash = self.hashSha256D()
    }

    public func serializeForDisk() -> Data {
        var data = Data()
        data += "\(blockHeight),".data(using: .utf8) ?? Data()
        data += "\(version.littleEndian),".data(using: .utf8) ?? Data()
        data += "\(CryptoUtils.hexString(from: [UInt8](prevBlock).reversed())),".data(using: .utf8) ?? Data()
        data += "\(CryptoUtils.hexString(from: [UInt8](merkleRoot).reversed())),".data(using: .utf8) ?? Data()
        data += "\(timestamp.littleEndian),".data(using: .utf8) ?? Data()
        data += "\(bits.littleEndian),".data(using: .utf8) ?? Data()
        data += "\(nonce.littleEndian),".data(using: .utf8) ?? Data()
        data += "\(txnCount),".data(using: .utf8) ?? Data()
        data += "\(CryptoUtils.hexString(from: [UInt8](blockHash).reversed()))\n".data(using: .utf8) ?? Data()

        return data
    }

    public var description: String {
        var result = "\n...............................\n"
        result += "\(#function) [\(#line)] "
        result += "👤 Header\n"
        result += "    version = \(version)\n"
        result += "    prevBlock = \(Array([UInt8](prevBlock)))\n"
        var hexString = CryptoUtils.hexString(from: Array([UInt8](prevBlock)))
        result += "    prevBlock = \(hexString)\n"
        result += "    merkleRoot = \(Array([UInt8](merkleRoot)))\n"
        hexString = CryptoUtils.hexString(from: Array([UInt8](merkleRoot)))
        result += "    merkleRoot = \(hexString)\n"
        result += "    timestamp = \(timestamp)\n"
        result += "    bits = \(bits)\n"
        result += "    nonce = \(nonce)\n"
        result += "    txnCount = \(txnCount)\n"
        result += "...............................\n\n"
        return result
    }

// shown on https://pypi.org/project/spruned/
//    "nextblockhash": "000000006a625f06636b8bb6ac7b960a8d03705d1ace08b1a19da3fdcc99ddbd",
//    "tx": [
//      "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098"
//    ],
//    "previousblockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
//    "merkleroot": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
//    "hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
    
    var key: String {
        return "\(version)\([UInt8](prevBlock))\([UInt8](merkleRoot))\(timestamp)\(bits)\(nonce)"
    }
    
    public func hashSha256D() -> Data {//}[UInt8] {
        var result = [UInt8]()
        
        let data = serialize()
        
        if let sha256 = Digest(using: .sha256).update(data: data)?.final() {

            // Doubled
            if let sha256D = Digest(using: .sha256).update(byteArray: sha256)?.final() {
                result = Array([UInt8](sha256D))
            }
        }
        return Data(Array(result))
    }

    
//    4    version     int32_t     Block version information (note, this is signed)
//    32    prev_block  char[32]    The hash value of the previous block this particular block references
//    32    merkle_root char[32]    The reference to a Merkle tree collection which is a hash of all transactions related to this block
//    4     timestamp   uint32_t    A timestamp recording when this block was created (Will overflow in 2106[2])
//    4     bits        uint32_t    The calculated difficulty target being used for this block
//    4     nonce       uint32_t    The nonce used to generate this block… to allow variations of the header and compute different hashes
//    1+    txn_count   var_int     Number of transaction entries, this value is always 0
    
    
    public var blockHeight: UInt32 = 0
    
    // 1, 0, 0, 0 = 0001
    var version: UInt32 = 0
    
    /// The protocol version
    var prevBlock: Data = Data()
    var merkleRoot: Data = Data()
    var timestamp: UInt32 = 0
    var bits: UInt32 = 0
    var nonce: UInt32 = 0
    
    // VarInt normally
    // For only header ( no tx ) then always 0
    // txnCount is a varint,
    // so any value less than 253 is a byte
    var txnCount: UInt8 = 0
    var transactionData: Data = Data()
    
    // Hash of this block
    public var blockHash: Data = Data()

    public func serialize() -> Data {

        var data = Data()
        data += withUnsafeBytes(of: version.littleEndian) { Data($0) }
        data += prevBlock
        data += merkleRoot
        data += withUnsafeBytes(of: timestamp.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: bits.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: nonce.littleEndian) { Data($0) }
        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8]) -> Header? {
        var offset = 0
        var size = MemoryLayout<UInt32>.size
        let version = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }

        offset += size
        size = MemoryLayout<UInt8>.size * 32

        let prevBlock = Data(Array(uint8Array[offset..<(offset + size)]))

        offset += size
        size = MemoryLayout<UInt8>.size * 32
        let merkleRoot = Data(Array(uint8Array[offset..<(offset + size)]))
        
        offset += size
        size = MemoryLayout<UInt32>.size
        let timestamp = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        offset += size
        size = MemoryLayout<UInt32>.size
        let bits = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        offset += size
        size = MemoryLayout<UInt32>.size
        let nonce = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        
        offset += size
        size = MemoryLayout<UInt8>.size
        let txnCount: UInt8 = 0
        if offset + size <= uint8Array.count {
            let txnCount = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt8(byte)
            }
            if txnCount != 0 {
                print("🔺 Header returned which includes attached transaction count")
                // Not dealing with full block data yet
                return nil
            }
        }
        
        return Header(
            version: version,
            prevBlock: prevBlock,
            merkleRoot: merkleRoot,
            timestamp: timestamp,
            bits: bits,
            nonce: nonce,
            txnCount: txnCount)
    }
}
