//
//  NetworkAddress.swift
//  
//
//  Created by Phil Wilson on 27/1/20.
//

import Foundation
import Socket

func pton(_ address: String) -> Data {
    var addr = in6_addr()
    _ = withUnsafeMutablePointer(to: &addr) {
        inet_pton(AF_INET6, address, UnsafeMutablePointer($0))
    }
    var buffer = Data(count: 16)
    _ = buffer.withUnsafeMutableBytes { memcpy($0.baseAddress.unsafelyUnwrapped, &addr, 16) }
    return buffer
}

public struct NetworkAddress {
    public let services: UInt64
    public let address: String
    public let port: UInt16

    public func serialize() -> Data {
        var data = Data()
        data += withUnsafeBytes(of: services.littleEndian) { Data($0) }
        data += pton(address)
        data += withUnsafeBytes(of: port.bigEndian) { Data($0) }
        return data
    }

    public static func deserialize( data: Data, offset: Int) -> (newAddress: NetworkAddress, updatedOffset: Int) {
        var offset = offset
        var size = MemoryLayout<UInt64>.size
        let services = data[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }
//        print("services = \(services)")

        offset += size
        size = MemoryLayout<UInt8>.size * 16
        let addressArray = Array(data[offset..<(offset + size)])
//        print("addressArray = <\(addressArray)>")
        
        let addressData = Data(addressArray)
        let address = parseIP(data: addressData)
        
        offset += size
        size = MemoryLayout<UInt16>.size
        let port = data[offset..<(offset + size)].reduce(0) { soFar, byte in
            return soFar << 8 | UInt16(byte)
        }
//        print("port = \(port)")
        
        let newNetworkAddress = NetworkAddress(services: services, address: address, port: port)
        offset += size
        return (newNetworkAddress, offset)
    }
    
    private static func parseIP(data: Data) -> String {
//        print("parseIP")
        let address = ipv6(from: data)
//        print("parseIP address = \(address)")
        if address.hasPrefix("0000:0000:0000:0000:0000:ffff") {
            return "0000:0000:0000:0000:0000:ffff:" + ipv4(from: data)
        } else {
            return address
        }
    }
    private static func ipv4(from data: Data) -> String {
        return Data(data.dropFirst(12)).map { String($0) }.joined(separator: ".")
    }

    private static func ipv6(from data: Data) -> String {
        return stride(from: 0, to: data.count - 1, by: 2).map { Data([data[$0], data[$0 + 1]]).hex }.joined(separator: ":")
    }
    
    static public func extractAddress(_ address: String, andPort port: Int32 = 8333) -> (address: String, port: Int32) {
        var portString = "\(port)"
        var returnPort = port
        var returnAddress = address
        var splitAddress = address.split(separator: ":")
        if splitAddress.count == 1 {
            // Address is only the address portion
            returnAddress = address
        } else if splitAddress.count == 2 {
            // Address is IPV4 including port suffix
            returnAddress = String(splitAddress[0])
            portString = String(splitAddress[1])
        }
        else if splitAddress.count == 6 {
            // Address is IPV6 without port suffix
            returnAddress = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        else if splitAddress.count == 7 {
            // Address is IPV6 with port suffix
            portString = String(splitAddress.removeLast())
            returnAddress = String(splitAddress.joined(separator: ":")).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        if let portInt = Int32(portString) {
            returnPort = portInt
        }
        return (returnAddress, returnPort)
    }
}


extension Data {
    public init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i * 2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }

    public var hex: String {
        return reduce("") { $0 + String(format: "%02x", $1) }
    }
}