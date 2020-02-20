// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation
import Socket

class NetworkService {
    var stillRunning = false

    // MARK: - Messages
    
    func sendMessage(_ socket: Socket?, _ message: Message) {
        guard let socket = socket else { return }
        print("Sending \(message.command)")
        let data = message.serialize()
        //        let dataArray = [UInt8](data)
        do {
            try socket.write(from: data)
        } catch let error {
            guard let socketError = error as? Socket.Error else {
                print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                return
            }
            if self.stillRunning {
                print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
            }
        }
    }

    // MARK: -
    
    // Attempt to consume network packet data
    func consumeNetworkPackets(_ node: Node) -> Message?{
        // Extract data
        if node.packageData.count < 24 { return nil }
        
        return consumeMessage(node)
//        while consumeMessage(node) { }
    }
    
    /// Attempt to consume message data.
    /// Returns whether message was consumed
    func consumeMessage(_ node: Node) -> Message? {
        if let message = Message.deserialise(Array([UInt8](node.packageData)), arrayLength: UInt32(node.packageData.count)) {
            
            if message.payload.count < message.length {
                // We received the Message data but not the payload
                return nil
            }
            let payload = message.payload
            node.packageData.removeFirst(Int(message.length + 24))
            
            // Confirm magic number is correct
            if message.fourCC.characterCode != [0xe3, 0xe1, 0xf3, 0xe8] {
                print("fourCC != 0xe3e1f3e8\nfourCC == \(message.fourCC)\nfor node with address \(node.address):\(node.port)")
                return nil
            }
            
            // Only verify checksum if this packet sent payload
            // with message header
            if message.payload.count >= message.length {
                // Confirm checksum for message is correct
                let checksumFromPayload =  Array(payload.doubleSHA256ToData[0..<4])
                var checksumConfirmed = true
                for (index, element) in checksumFromPayload.enumerated() {
                    if message.checksum[index] != element { checksumConfirmed = false; break }
                }
                if checksumConfirmed != true { return nil }
            } else {
                // Still more data to retrive for this message
                return nil
            }
            
            // MARK: - Message Check
            
            print("Received \(message.command)")

            return message
        }
        return nil
    }

}
