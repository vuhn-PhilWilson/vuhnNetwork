// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// https://en.bitcoin.it/wiki/Protocol_documentation#getaddr
/// The getaddr message sends a request to a node asking for information about known active peers to help with finding potential nodes in the network.
/// The response to receiving this message is to transmit one or more addr messages with one or more peers from a database of known active peers.
/// The typical presumption is that a node is likely to be active if it has been sending a message within the last three hours.
/// No additional data is transmitted with this message.
public struct GetAddrMessage {
    
    public func serialize() -> Data {
        return Data()
    }
}
