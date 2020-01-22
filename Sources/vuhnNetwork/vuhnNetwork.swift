
// https://github.com/IBM-Swift/BlueSocket

struct vuhnNetwork {
    var text = "Hello, World!"
}

public func runEchoServer()
{
    let port = 1337
    let echoServer = EchoServer(port: port)
    print("Swift Echo Server Sample")
    print("Connect with a command line window by entering 'telnet ::1 \(port)' or macOS `nc ::1 \(port)`")

    echoServer.run()
}
