// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation
import NIO

class NetworkService {
    var stillRunning = false

    // MARK: - Messages
    
    func sendMessage(_ channel: Channel?, _ message: Message) {
        guard let channel = channel else { return }
        let data = message.serialize()
        
            let dataArray = [UInt8](data)
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(dataArray)
            _ =  channel.writeAndFlush(buffer)//.wait()
    }

    // MARK: -
    
    // Attempt to consume network packet data
    func consumeNetworkPackets(_ node: Node) -> Message? {
        if node.packetData.count < 24 { return nil }
        return consumeMessage(node)
    }
    
    /// Attempt to consume message data.
    /// Returns whether message was consumed
    func consumeMessage(_ node: Node) -> Message? {
        if let message = Message.deserialise(Array([UInt8](node.packetData)), arrayLength: UInt32(node.packetData.count)) {
            
            if message.payload.count < message.length {
                // We received the Message data but not the payload
                print("\(node.name) We received the Message data but not the payload. \(message.command)  message.payload.count \(message.payload.count) message.length \(message.length)")
                return nil
            }
            let payload = message.payload
            node.packetData.removeFirst(Int(message.length + 24))
            
            // Confirm magic number is correct
            if message.fourCC.characterCode != [0xe3, 0xe1, 0xf3, 0xe8] {
                print("\(node.name) fourCC != 0xe3e1f3e8\nfourCC == \(message.fourCC)\nfor node with address \(node.address):\(node.port)")
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
                print("\(node.name) received \(message.command)")
            } else {
                // Still more data to retrive for this message
                return nil
            }
            return message
        }
        return nil
    }
}
