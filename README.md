# Central Chat — iOS

SwiftPM (the package URL Central gives you) · CocoaPods `pod 'CentralChat'`.
Both are SOURCE; there is no binary to trust and no XCFramework to notarise.

```swift
CentralChat.init(entry)        // at launch — warms everything
CentralChat.show(from: self)   // from your support button
CentralChat.hide()             // optional; the screen closes itself
```

`entry` is a **channel key** (`businessId|chatAccountId`, anonymous) or a **mint
user key** your backend signed (that person). One argument, either door.

iOS 15 · no dependencies · `init` hops to the main queue itself.

### Optional

```swift
CentralChat.onReady = { }           // warm; enable your button here
CentralChat.onError = { error in }  // .entryInvalid | .tokenExpired | .network | .internalError
```

`Info.plist`, only for what your chat account offers:
`NSMicrophoneUsageDescription`, `NSCameraUsageDescription`,
`NSPhotoLibraryUsageDescription`, `NSLocationWhenInUseUsageDescription`.

Session and keys live in the Keychain (`ThisDeviceOnly`), so your "clear cache"
cannot sign the visitor out. Example: [`../../example/ios`](../../example/ios).
