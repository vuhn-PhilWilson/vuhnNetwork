import XCTest
import Cryptor
@testable import vuhnNetwork

final class vuhnNetworkTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(vuhnNetwork().text, "Hello, World!")
    }

    func testCrypto() {
        
        // echo -n hello |openssl dgst -sha256 -binary |openssl dgst -sha256
        // echo -n "The quick brown fox jumps over the lazy dog." |openssl dgst -sha256 -binary |openssl dgst -sha256
        
        let myKeyData = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
        let myData = "4869205468657265"
        let key = CryptoUtils.byteArray(fromHex: myKeyData)
        let data : [UInt8] = CryptoUtils.byteArray(fromHex: myData)

        if let hmac = HMAC(using: HMAC.Algorithm.sha256, key: key).update(byteArray: data)?.final() {
            print("hmac\t\t\t\t\(hmac)")
        }
        
        let hashResult: [UInt8] = [228, 217, 9, 194, 144, 208, 251, 28, 160, 104, 255, 173, 223, 34, 203, 208]
        
        let qbfBytes: [UInt8] = [0x54,0x68,0x65,0x20,0x71,0x75,0x69,0x63,0x6b,0x20,0x62,0x72,0x6f,0x77,0x6e,0x20,0x66,0x6f,0x78,0x20,0x6a,0x75,0x6d,0x70,0x73,0x20,0x6f,0x76,0x65,0x72,0x20,0x74,0x68,0x65,0x20,0x6c,0x61,0x7a,0x79,0x20,0x64,0x6f,0x67,0x2e]
        let qbfString = "The quick brown fox jumps over the lazy dog."
        
        // String...
        let md5 = Digest(using: .md5)
        guard let md5Result = md5.update(string: qbfString)
            else {
                print("md5.update error")
                return
        }
        
        let digestFromString = md5.final()
        
        print("digestFromString\t\(digestFromString)")
        
        XCTAssertEqual(digestFromString, hashResult)
        
        // NSData using optional chaining...
        let qbfData: NSData = CryptoUtils.data(from: qbfBytes)
        //        let qbfData = CryptoUtils.data(from: qbfBytes)
        //let digestFromData: NSData = Digest(using: .md5).update(data: qbfData)?.final()
        if let digestFromData = Digest(using: .md5).update(data: qbfData)?.final() {
            print("digestFromData\t\t\(digestFromData)")
        }
        
        print("\n\n")
        
        
        if let sha256 = Digest(using: .sha256).update(string: qbfString)?.final() {
            print("sha256\t\t\(sha256)")
            let hexString = CryptoUtils.hexString(from: sha256)

            
            let sha256Result = "ef537f25c895bfa782526529a9b63d97aa631564d5d789c2b765448c8635fb6c"
            let sha256DoubleResult = "a51a910ecba8a599555b32133bf1829455d55fe576677b49cb561d874077385c"
            
            print("sha256 hexString \t\t\(hexString)")
            
            XCTAssertEqual(hexString, sha256Result)
            
            
            // Doubled
            if let sha256D = Digest(using: .sha256).update(byteArray: sha256)?.final() {
                print("sha256D\t\t\(sha256D)")
                let hexString = CryptoUtils.hexString(from: sha256D)
                print("sha256D hexString \t\t\(hexString)")
                XCTAssertEqual(hexString, sha256DoubleResult)
            }
                
        }
        
        print("\n\n")
        
    }
    
    func testBlockHash() {
        
        var header = Header()
        
//        version = 1
        let prevBlock: [UInt8] = [0, 0, 0, 0, 0, 25, 214, 104, 156, 8, 90, 225, 101, 131, 30, 147, 79, 247, 99, 174, 70, 162, 166, 193, 114, 179, 241, 182, 10, 140, 226, 111]
//        prevBlock = 000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f
        let merkleRoot: [UInt8] = [14, 62, 35, 87, 232, 6, 182, 205, 177, 247, 11, 84, 195, 163, 161, 123, 103, 20, 238, 31, 14, 104, 190, 187, 68, 167, 75, 30, 253, 81, 32, 152]
//        merkleRoot = 0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098
//        timestamp = 1231469665
//        bits = 486604799
//        nonce = 2573394689
//        txnCount = 0

        header.version = 1
        header.prevBlock = Data(Array(prevBlock[0..<prevBlock.count].reversed()))
        header.merkleRoot = Data(Array(merkleRoot[0..<merkleRoot.count].reversed()))
        header.timestamp = 1231469665
        header.bits = 486604799
        header.nonce = 2573394689
        header.txnCount = 0
        
        
        print("header.serialize\t\t\(header.serialize())")
        print("header.serialize [UInt8]\t\t\([UInt8](header.serialize()))")
        
        
        let testHeaderData: [UInt8] = [1, 0, 0, 0, 111, 226, 140, 10, 182, 241, 179, 114, 193, 166, 162, 70, 174, 99, 247, 79, 147, 30, 131, 101, 225, 90, 8, 156, 104, 214, 25, 0, 0, 0, 0, 0, 152, 32, 81, 253, 30, 75, 167, 68, 187, 190, 104, 14, 31, 238, 20, 103, 123, 161, 163, 195, 84, 11, 247, 177, 205, 182, 6, 232, 87, 35, 62, 14, 97, 188, 102, 73, 255, 255, 0, 29, 1, 227, 98, 153]
        print("\n\n🍎testHeaderData\t\t\(testHeaderData)\n\n")
//        if let deserialisedHeader = Header.deserialise(testHeaderData) {
//            print("\ndeserialisedHeader.serialize [UInt8]\t\t\([UInt8](deserialisedHeader.serialize()))")
//
//        }
        let deserialisedHeader = Header.deserialise(testHeaderData)!
        print("\ndeserialisedHeader.serialize [UInt8]\t\t\([UInt8](deserialisedHeader.serialize()))")
           
        
//        let data = header.serialize()
//        let dataArray = [UInt8](data)

//        print("dataArray\t\t\(dataArray)")
        
//        var hexString = CryptoUtils.hexString(from: [UInt8](header.prevBlock))
//        print("prevBlock\t\t\(hexString)")
//        hexString = CryptoUtils.hexString(from: [UInt8](header.merkleRoot))
//        print("merkleRoot\t\t\(hexString)")
        
//        print("header.timestamp.littleEndian\t\t\(header.timestamp.littleEndian)")
        
//        var timestamp = withUnsafeBytes(of: header.timestamp.littleEndian) { Data($0) }
//        print("timestamp\t\t\([UInt8](timestamp))")
//        timestamp = withUnsafeBytes(of: header.timestamp) { Data($0) }
//        print("timestamp\t\t\([UInt8](timestamp))")
        
//        let textBlockHashHex = "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"
        let textBlockHashHex = "4860eb18bf1b1620e37e9490fc8a427514416fd75159ab86688e9a8300000000"
        print("textBlockHashHex\t\t\(textBlockHashHex)")
        
        let blockHash = [UInt8](deserialisedHeader.blockHash)
        let blockHashHex = CryptoUtils.hexString(from: blockHash)
        print("blockHashHex\t\t\(blockHashHex)")
        XCTAssertEqual(blockHashHex, textBlockHashHex)
        
        let sha256D = [UInt8](header.hashSha256D())
//        let sha256D = header.hashSha256D()
        let sha256DHex = CryptoUtils.hexString(from: sha256D)
        print("sha256DHex\t\t\(sha256DHex)")
        
//        if let sha256 = Digest(using: .sha256).update(data: data)?.final() {
//            if let sha256D = Digest(using: .sha256).update(byteArray: sha256)?.final() {
//                print("sha256D\t\t\(sha256D)")
//                let hexString = CryptoUtils.hexString(from: sha256D)
//                print("hexString\t\t\(hexString)")
//            }
//        }
        

        XCTAssertEqual(sha256DHex, textBlockHashHex)
        
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
