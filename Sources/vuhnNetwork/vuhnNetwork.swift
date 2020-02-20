
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
