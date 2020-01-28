//
//  NetworkAddress.swift
//  
//
//  Created by Phil Wilson on 27/1/20.
//

import Foundation

public class NetworkAddress {
    
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
