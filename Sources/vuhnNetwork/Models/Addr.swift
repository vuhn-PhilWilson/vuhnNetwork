// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// Provide information on known nodes of the network. Non-advertised nodes should be forgotten after typically 3 hours
public struct AddrMessage {

    public let networkAddresses: [(TimeInterval, NetworkAddress)]
    
    public func serialize() -> Data {
        var countOfAddresses = networkAddresses.count
        if countOfAddresses > 1000 { countOfAddresses = 1000 }
        
        print("Number of serialised addresses is \(countOfAddresses)")
        
        var data = Data()
        
        if countOfAddresses < 0xFD {
            data += withUnsafeBytes(of: UInt8(countOfAddresses.littleEndian)) { Data($0) }
        } else if countOfAddresses <= 0xFFFF {
            data += withUnsafeBytes(of: [UInt8(0xFD),UInt16(countOfAddresses.littleEndian)]) { Data($0) }
        } else if countOfAddresses <= 0xFFFFFFFF {
            data += withUnsafeBytes(of: [UInt8(0xFE),UInt32(countOfAddresses.littleEndian)]) { Data($0) }
        } else {
            data += withUnsafeBytes(of: [UInt8(0xFF),UInt64(countOfAddresses.littleEndian)]) { Data($0) }
        }
        
        for index in 0..<countOfAddresses {
            let (timestamp, networkAddress) = networkAddresses[index]
            data += withUnsafeBytes(of: UInt32(timestamp).littleEndian) { Data($0) }
            data += networkAddress.serialize()
        }
        return data
    }
    
    public static func deserialise(_ uint8Array: [UInt8]) -> AddrMessage? {
        var offset = 0
        var size = MemoryLayout<UInt8>.size
        
        var countOfAddresses: Int = 0
        let numOfAddresses = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt8(byte)
        }
        countOfAddresses = Int(numOfAddresses)
        
        // Is varint greater than 252
        if countOfAddresses == 0xFD {
            offset = 1
            size = MemoryLayout<UInt16>.size
            let numOfAddresses = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt16(byte)
            }
            countOfAddresses = Int(numOfAddresses)
        } else if countOfAddresses == 0xFE {
            offset = 1
            size = MemoryLayout<UInt32>.size
            let numOfAddresses = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt32(byte)
            }
            countOfAddresses = Int(numOfAddresses)
        } else if countOfAddresses == 0xFF {
            offset = 1
            size = MemoryLayout<UInt64>.size
            let numOfAddresses = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt64(byte)
            }
            countOfAddresses = Int(numOfAddresses)
        }
        print("Number of addresses is \(countOfAddresses)")
    
        let numberOfSuppliedAddresses = (uint8Array.count - 1) / 30
        guard countOfAddresses == numberOfSuppliedAddresses else {
            print("Number of addresses is supposed to be \(countOfAddresses)\nActual number of addresses is \(numberOfSuppliedAddresses)")
            return nil
        }

        offset += size
        var extractedNetworkAddresses = [(TimeInterval, NetworkAddress)]()
        for _ in 0..<countOfAddresses {
            size = MemoryLayout<UInt32>.size
            let timestamp = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt32(byte)
            }
            
            offset += size
            let (newAddress, updatedOffset) = NetworkAddress.deserialise(uint8Array, offset: offset)
            offset = updatedOffset
            
            extractedNetworkAddresses.append((TimeInterval(timestamp), newAddress))
        }
        return AddrMessage(networkAddresses: extractedNetworkAddresses)
    }
}
