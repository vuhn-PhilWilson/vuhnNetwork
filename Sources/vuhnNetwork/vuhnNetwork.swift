
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
    print("makeOutBoundConnections  addresses  \(addresses)")
    consoleUpdateHandler = updateHandler
    
    let signalInteruptHandler = setUpInterruptHandling()
    signalInteruptHandler.resume()

    connectionsManager = ConnectionsManager(addresses: addresses, listenPort: listenPort) { (dictionary, error) in
        // Supply update information to commandline
        DispatchQueue.main.async {
            consoleUpdateHandler?(dictionary, error)
        }
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
