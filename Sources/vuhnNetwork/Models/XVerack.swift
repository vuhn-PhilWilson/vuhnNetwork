// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// The xverack message is sent in reply to xversion.
/// This message consists of only a message header with the command string "xverack".
public struct XVerackMessage {
    public func serialize() -> Data {
        return Data()
    }
}
