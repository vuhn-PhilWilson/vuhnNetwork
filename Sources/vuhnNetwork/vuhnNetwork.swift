
import Dispatch
import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

struct vuhnNetwork {
    var text = "Hello, World!"
}

var connectionsManager: ConnectionsManager?
var consoleUpdateHandler: (([String: NetworkUpdate],Error?) -> Void)?

public func makeOutBoundConnections(to addresses: [String], listenPort: Int = 8333, updateHandler: (([String: NetworkUpdate],Error?) -> Void)?)
{
    consoleUpdateHandler = updateHandler
    
//    testSha256Hashing()
//    testSha256HashingData()
    
    let port: UInt16 = 8333
    let version = VersionMessage(version: protocolVersion,
                                 services: 0x00,
                                 timestamp: Int64(Date().timeIntervalSince1970),
                                 receivingAddress: NetworkAddress(services: 0x00,
                                                          address: "::ffff:127.0.0.1",
                                                          port: UInt16(port)),
                                 emittingAddress: NetworkAddress(services: 0x00,
                                                          address: "::ffff:127.0.0.1",
                                                          port: UInt16(8888)),
                                 nonce: 42,
                                 userAgent: yourUserAgent,
                                 startHeight: -1,
                                 relay: false)
                                 
    print("version = \(version)\n")
    
    var sentMessage = Message(command: .Version, payload: version.serialize())
    print("sentMessage = \(sentMessage)\n")
    var data = sentMessage.serialize()
//    print("sentMessage data = \(data)")
    

    // Extract Message data

    var byteArray = Array([UInt8](data))
    
    var receivedMessage = Message.deserialise(byteArray, length: UInt32(data.count))
//    let receivedMessage = Message.deserialise(data)
    print("receivedMessage = \(receivedMessage)\n")
    

    // Extract Version Message data
    guard let payload = receivedMessage?.payload else { exit(0) }
        
    let payloadCopy = Data(payload)
        
    let receivedVersionMessage = VersionMessage.deserialise(payloadCopy)
    print("receivedVersionMessage = \(receivedVersionMessage)\n")
    
    //============================================================================
    
    let verAckMessage = VerAckMessage()
    print("verAckMessage = \(verAckMessage)\n")
    
    sentMessage = Message(command: .VerAck, payload: verAckMessage.serialize())
    print("sentMessage = \(sentMessage)\n")
    data = sentMessage.serialize()
    
    byteArray = Array([UInt8](data))
    
    receivedMessage = Message.deserialise(byteArray, length: UInt32(data.count))
    print("receivedMessage = \(receivedMessage)\n")
    
    
    exit(0)
    
    let signalInteruptHandler = setUpInterruptHandling()
    signalInteruptHandler.resume()

    connectionsManager = ConnectionsManager(addresses: addresses, listenPort: listenPort) { (dictionary, error) in
        // Supply update information to commandline
        consoleUpdateHandler?(dictionary, error)
    }
    
    connectionsManager?.run()
}

private func setUpInterruptHandling() -> DispatchSourceSignal {
    // Make sure the ctrl+c signal does not terminate the application.
    signal(SIGINT, SIG_IGN)

    let signalInteruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalInteruptSource.setEventHandler {
        print("")
        var networkUpdate = NetworkUpdate(type: .receivedInterruptSignal, level: .information, error: .allFine)
        consoleUpdateHandler?(["information":networkUpdate], nil)
        connectionsManager?.close()
        networkUpdate = NetworkUpdate(type: .shutDown, level: .information, error: .allFine)
        consoleUpdateHandler?(["information":networkUpdate], nil)
        exit(0)
    }
    return signalInteruptSource
}
