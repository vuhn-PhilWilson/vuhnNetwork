
// https://github.com/IBM-Swift/BlueSocket
import Dispatch

struct vuhnNetwork {
    var text = "Hello, World!"
}

var connectionsManager: ConnectionsManager?

public func runEchoServer()
{
    let port = 1337
    let echoServer = EchoServer(port: port)
    print("Swift Echo Server Sample")
    print("Connect with a command line window by entering 'telnet ::1 \(port)' or macOS `nc ::1 \(port)`")

    echoServer.run()
}

public func makeOutBoundConnections(to addresses: [String], listenPort: Int = 8333, updateHandler: (([String: NetworkUpdate],Error?) -> Void)?)
{

    signal(SIGINT, SIG_IGN) // // Make sure the signal does not terminate the application.

    let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSrc.setEventHandler {
        print("\nGot SIGINT")
        connectionsManager?.close()
        print("connectionsManager closed")
        exit(0)
    }
    sigintSrc.resume()

    
    connectionsManager = ConnectionsManager(addresses: addresses, listenPort: listenPort) { (dictionary, error) in
        // Supply update information to commandline
        updateHandler?(dictionary, error)
    }
    
    connectionsManager?.run()
    
//    let connectionsManager = ConnectionsManager(addresses, updateHandler)
//    for address in addresses {
//        addOutBoundClient(with address)
//    }
//    let port = 1337
//    let echoServer = EchoServer(port: port)
//    print("Swift Echo Server Sample")
//    print("Connect with a command line window by entering 'telnet ::1 \(port)' or macOS `nc ::1 \(port)`")
//
//    echoServer.run()
}

//Trap.handle(.interrupt) {
//    connectionsManager.close()
////    task.terminate()
//    exit(EXIT_FAILURE)
//}
