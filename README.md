<p align="center">
    <a href="https://travis-ci.com/vuhn-PhilWilson/vuhnNetwork">
    <img src="https://travis-ci.com/vuhn-PhilWilson/vuhnNetwork.svg?branch=master" alt="Build Status - Master">
    </a>
    <img src="https://img.shields.io/badge/os-macOS-green.svg?style=flat" alt="macOS">
    <img src="https://img.shields.io/badge/os-linux-green.svg?style=flat" alt="Linux">
    <img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat" alt="MIT">
</p>

# vuhnNetwork

**vuhnNetwork** framework for Swift using the Swift Package Manager.
Works on macOS and Linux.
It uses IBM's `BlueSocket` framework for socket connectivity.

## Prerequisites

### Swift

* Swift Open Source `swift-5.1-RELEASE` toolchain (**Minimum REQUIRED for latest release**)
* Swift Open Source `swift-5.1-RELEASE` toolchain (**Recommended**)
* Swift toolchain included in *Xcode Version 11.0 (11A420a) or higher*.
* Example toolchains:
  * `swift-5.1-RELEASE-ubuntu16.04`
  * `swift-5.1-RELEASE-ubuntu18.04`
  * `swift-5.1-RELEASE-ubuntu19.04`
  * `Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)`

### macOS

* macOS 10.14.6 (*Mojave*) or higher.
* Xcode Version 11.0  (11A420a) or higher using one of the above toolchains.
* Xcode Version 11.0 (11A420a) or higher using the included toolchain (*Recommended*).

### Linux

* Ubuntu 19.04 (or 16.04 or 18.04 but only tested on 19.04).
* One of the Swift Open Source toolchain listed above.

## Build

To build **vuhnNetwork** from the command line:

```
% cd <path-to-vuhnNetwork-clone>
% swift build
```

## Testing

To run the supplied unit tests for **vuhnNetwork** from the command line:

```
% cd <path-to-vuhnNetwork-clone>
% swift build
% swift test
```

## Using vuhnNetwork

### Including in your project

#### Swift Package Manager

To include **vuhnNetwork** into a Swift Package Manager package, add it to the `dependencies` attribute defined in your `Package.swift` file.
You can select the version using the `from` parameter and choose an available `tag` value.
For example:
```
    dependencies: [
        .package(url: "https://github.com/vuhn-PhilWilson/vuhnNetwork", from: "0.0.3")
    ]
```

If you'd prefer to make local changes to **vuhnNetwork** and have it included into a Swift Package Manager package you can use a referenced path.
For example:
```
    dependencies: [
    .package(path: "../vuhnNetwork")
    ]
```

### Before starting

The first thing you need to do is import the **vuhnNetwork** framework.
This is done by the following:
```
import vuhnNetwork
```

See the **vuhnKredit** program for an example of using and running **vuhnNetwork**.

## Using vuhnKredit

After downloading **vuhnKredit**, run from the command line:

```
% cd <path-to-vuhnKredit-clone>
% swift run vuhnKredit
```

It defaults to listening on port 8333

Change the default listening port by using the -listeningPort parameter
```
% swift run vuhnKredit -listeningPort 8555
```

Connect to specific nodes by using the -connectTo parameter
```
% swift run vuhnKredit -connectTo 18.195.144.149:8333
```

You can run multiple nodes on the same computer by setting different ports
Just make sure the selected port is the same one the other node is listening to
```
% swift run vuhnKredit -listeningPort 8555
% swift run vuhnKredit -listeningPort 9333 -connectTo 18.195.144.149:8555
% swift run vuhnKredit -listeningPort 8888 -connectTo 63.143.34.98:9333
% swift run vuhnKredit -listeningPort 8333 -connectTo 63.143.34.98:9333
```

## License

Copyright (c) 2020 Satoshi Nakamoto

Distributed under the MIT/X11 software license ( see the accompanying
file `license.txt` or  [LICENSE](http://www.opensource.org/licenses/mit-license.php) for template ).

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
