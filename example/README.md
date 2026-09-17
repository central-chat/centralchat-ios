# Central Chat example — iOS

```bash
brew install xcodegen   # once
xcodegen generate
open CentralChatExample.xcodeproj
```

The `.xcodeproj` is generated, not committed — no binary merge conflicts and no
stale build settings.

Paste a **channel key** (`businessId|chatAccountId`) or a **mint user key**, tap
**Test**, then **Open central.chat**.

## What to read

[`Sources/AppDelegate.swift`](Sources/AppDelegate.swift), and in it two lines —
`CentralChat.init(entry)` and `CentralChat.show(from:)`. Everything else is a
text field and two buttons.

Your app has no key field: it asks its backend for a mint user key on every
launch and calls `init` with it.

It takes the library from [`../../lib/ios`](../../lib/ios) by path, so it always
compiles against the source beside it.

> **Unbuilt.** Written without a Mac in reach; expect the first `xcodegen` +
> build to find real errors.
