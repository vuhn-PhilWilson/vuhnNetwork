// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

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

    public static func deserialise(_ uint8Array: [UInt8], offset: Int) -> (newAddress: NetworkAddress, updatedOffset: Int) {
        var offset = offset
        var size = MemoryLayout<UInt64>.size
        let services = uint8Array[offset..<(offset + size)].reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt64(byte)
        }

        offset += size
        size = MemoryLayout<UInt8>.size * 16
        let addressArray = Array(uint8Array[offset..<(offset + size)])
        let address = parseIP(addressArray)
        
        offset += size
        size = MemoryLayout<UInt16>.size
        let port = uint8Array[offset..<(offset + size)].reduce(0) { soFar, byte in
            return soFar << 8 | UInt16(byte)
        }
        
        let newNetworkAddress = NetworkAddress(services: services, address: address, port: port)
        offset += size
        return (newNetworkAddress, offset)
    }
        
    private static func parseIP(_ uint8Array: [UInt8]) -> String {
//        print("parseIP")
        let address = ipv6(uint8Array)
        if address.hasPrefix("0000:0000:0000:0000:0000:ffff") {
            return "0000:0000:0000:0000:0000:ffff:" + ipv4(uint8Array)
        } else {
            return address
        }
    }

    private static func ipv4(_ uint8Array: [UInt8]) -> String {
        return Data(uint8Array.dropFirst(12)).map { String($0) }.joined(separator: ".")
    }

    private static func ipv6(_ uint8Array: [UInt8]) -> String {
        return stride(from: 0, to: 16 - 1, by: 2).map { String(format: "%02x%02x", uint8Array[$0], uint8Array[$0 + 1]) }.joined(separator: ":")
    }
    
    static public func isIPv4(_ address: String) -> Bool {
        if address.split(separator: ".").count == 4
            && (address.split(separator: ":").count == 1 || address.split(separator: ":").count == 2) { return true }
        return false
    }
    
    static public func extractAddress(_ address: String, andPort port: UInt16 = 8333) -> (address: String, port: UInt16) {
        var portString = "\(port)"
        var returnPort = port
        var returnAddress = address
//        var splitAddress = address.split(separator: ":")
        let splitAddressForIPV4 = address.split(separator: ".")
        
        if splitAddressForIPV4.count == 4 {
            // Is IPV4
            // example:
            // "0000:0000:0000:0000:0000:ffff:51.15.125.5:8333"
            // "51.15.125.5:8333"
            // "0000:0000:0000:0000:0000:ffff:51.15.125.5"
            // "51.15.125.5"
            
            let splitAddressByColon = address.split(separator: ":")
            if splitAddressByColon.count == 1 {
                // IPV4 with no port suffix
                returnAddress = "0000:0000:0000:0000:0000:ffff:\(String(splitAddressByColon[0]))"
            } else if splitAddressByColon.count == 2 {
                // IPV4 with port suffix
                returnAddress = "0000:0000:0000:0000:0000:ffff:\(String(splitAddressByColon[0]))"
                portString = String(splitAddressByColon[1])
            } else if splitAddressByColon.count == 7 {
                // IPV4 expanded into IPV6 with no port suffix
                returnAddress = String(splitAddressByColon[6])
            } else if splitAddressByColon.count == 8 {
                // IPV4 expanded into IPV6 with port suffix
                returnAddress = String(splitAddressByColon[6])
                portString = String(splitAddressByColon[7])
            }
        } else {
            // Is IPV6
            var splitAddressByColon = address.split(separator: ":")
            
            if splitAddressByColon.count == 1 {
                // Address is only the address portion
                returnAddress = "0000:0000:0000:0000:0000:ffff:\(address)"
            } else if splitAddressByColon.count == 2 {
                // Address is IPV4 including port suffix
                returnAddress = "0000:0000:0000:0000:0000:ffff:\(String(splitAddressByColon[0]))"
                portString = String(splitAddressByColon[1])
            }
            else if splitAddressByColon.count == 8 {
                // Address is IPV6 without port suffix
                returnAddress = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            }
            else if splitAddressByColon.count == 9 {
                // Address is IPV6 with port suffix
                portString = String(splitAddressByColon.removeLast())
                returnAddress = String(splitAddressByColon.joined(separator: ":")).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            }

            if let portInt = UInt16(portString) {
                returnPort = portInt
            }
            
        }
        return (returnAddress, returnPort)
    }
    
    static public func isValidAddress(address: String) -> Bool {
        
        // Address must be
        //     IPV4 ( UInt8 + '.' + UInt8 + '.' + UInt8 + '.' + UInt8 )
        //     Or
        //     IPV6 ( UInt32hex + ':'UInt32hex + ':'UInt32hex + ':'UInt32hex + ':'UInt32hex + ':'UInt32hex )
        
        // port must be:
        //     an Unsigned Integer
        //     between 1-65535
        //     actually should be between 1024-65535
        
        return true
    }
}

extension NetworkAddress: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(address.hashValue ^ port.hashValue)
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
