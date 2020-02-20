// Copyright (c) 2020 Satoshi Nakamoto
//
// Distributed under the MIT/X11 software license ( see the accompanying
// file license.txt or http://www.opensource.org/licenses/mit-license.php for template ).

import Foundation

/// The verack message is sent in reply to version.
/// This message consists of only a message header with the command string "verack".
public struct VerackMessage {
//    Hexdump of the verack message:
//
//    0000   F9 BE B4 D9 76 65 72 61  63 6B 00 00 00 00 00 00   ....verack......
//    0010   00 00 00 00 5D F6 E0 E2                            ........
//
//    Message header:
//     F9 BE B4 D9                          - Main network magic bytes
//     76 65 72 61  63 6B 00 00 00 00 00 00 - "verack" command
//     00 00 00 00                          - Payload is 0 bytes long
//     5D F6 E0 E2                          - Checksum (little endian)
    
    public func serialize() -> Data {
        return Data()
    }
    
}
