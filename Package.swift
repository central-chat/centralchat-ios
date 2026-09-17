// swift-tools-version: 5.9
import PackageDescription

/// CentralChat — the iOS chat library.
///
/// Source, rather than the notarised XCFramework the docs hand out. Both exist
/// and they are the same code: the release job builds this package into
/// `CentralChat.xcframework.zip`, publishes it next to the web bundle on the CDN
/// with a `.sha256` beside it, and apps that would rather not take a binary
/// dependency (a very reasonable position) point SwiftPM straight here.
///
/// No dependencies, on purpose. Everything this library needs is WebKit and
/// UIKit, and a chat SDK that drags in a networking stack is a chat SDK somebody
/// has to reconcile with theirs.
let package = Package(
    name: "CentralChat",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CentralChat", targets: ["CentralChat"]),
    ],
    targets: [
        // Not built under StrictConcurrency: the API is a main-thread-hopping
        // facade over shared state rather than an actor-isolated one, which is
        // what lets `init` be called from the background request that fetched
        // the token — the thing every integration does first.
        .target(name: "CentralChat"),
    ]
)
