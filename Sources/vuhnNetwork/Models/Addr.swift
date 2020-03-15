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
//        print("Number of addresses is \(countOfAddresses)")
    
        let numberOfSuppliedAddresses = (uint8Array.count - 1) / 30
        guard countOfAddresses == numberOfSuppliedAddresses else {
            print("Number of addresses is supposed to be \(countOfAddresses)\nActual number of addresses is \(numberOfSuppliedAddresses)")
            return nil
        }

        offset += size
        var extractedNetworkAddresses = [(TimeInterval, NetworkAddress)]()
        let currentTimeStamp = UInt64(NSDate().timeIntervalSince1970)
//        print("current TimeStamp: \(currentTimeStamp)")
        for _ in 0..<countOfAddresses {
            size = MemoryLayout<UInt32>.size
            let addressTimestamp = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
                return soFar << 8 | UInt32(byte)
            }
            // The returned timestamp could be a few seconds ahead of our own timestamp
            let timedifference = currentTimeStamp > addressTimestamp ? currentTimeStamp - UInt64(addressTimestamp) : 0
//            print("address timestamp \(addressTimestamp)  timedifference \(timedifference) = \(timedifference / 3600) hours")
            // 86400
            
            offset += size
            let (newAddress, updatedOffset) = NetworkAddress.deserialise(uint8Array, offset: offset)
            offset = updatedOffset
            
            // Only add this address if it's fresher than 3 hours
            // Ignore if address is older than 3 hours since last check if online
            // Also ignore is this is actually our own IP address being returned by another node
            if let myExternalIPAddress = NodeManager.myExternalIPAddress,
                (timedifference / 3600) < 3
                    && newAddress.address != "0000:0000:0000:0000:0000:ffff:\(myExternalIPAddress)" {
                extractedNetworkAddresses.append((TimeInterval(addressTimestamp), newAddress))
            }
        }
        return AddrMessage(networkAddresses: extractedNetworkAddresses)
    }
}
