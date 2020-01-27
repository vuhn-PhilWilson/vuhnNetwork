//
//  Node.swift
//  
//
//  Created by Phil Wilson on 26/1/20.
//

import Foundation

class Node {
    
    var address: String
    var port: String
    
    public init(address: String, port: String = "8333") {
        self.port = port
        self.address = address
        var splitAddress = address.split(separator: ":")
        if splitAddress.count == 1 {
            // Address is only the address portion
            self.address = address
        } else if splitAddress.count == 2 {
            // Address is IPV4 including port suffix
            self.address = String(splitAddress[0])
            self.port = String(splitAddress[1])
        }
        else if splitAddress.count == 6 {
            // Address is IPV6 without port suffix
            self.address = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        else if splitAddress.count == 7 {
            // Address is IPV6 with port suffix
            self.port = String(splitAddress.removeLast())
            self.address = String(splitAddress.joined(separator: ":")).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
    }
}
