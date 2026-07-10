# iOS group-call media

Mithka follows Telegram iOS's native group-call architecture:

1. `GroupCallThreadLocalContext.emitJoinPayload` produces the JSON payload and
   audio SSRC sent through TDLib's `joinVideoChat`.
2. The returned TDLib payload is passed to `setJoinResponsePayload`, then the
   native engine enters RTC mode.
3. TDLib participant updates maintain the audio SSRC-to-peer descriptions that
   `TgVoipWebrtc` requests for incoming voice streams.
4. Camera enable/disable emits another join payload and repeats the same TDLib
   join handshake.
5. Remote video is subscribed as one complete
   `setRequestedVideoChannels` list and rendered with
   `makeIncomingVideoViewWithEndpointId`. The grid lowers maximum quality as
   more tiles become visible, matching Telegram's layout-driven subscriptions.
6. LiveCommunicationKit owns the system conversation and audio-session
   activation. `TgVoipWebrtc` owns microphone, camera, codecs, transport, and
   native video views.

The bridge is in `ios/Runner/TelegramGroupCallMediaBridge.swift`. It compiles to
an explicit unsupported implementation when `TgVoipWebrtc` is absent, so a
partial build never sends a fabricated Telegram media payload.

## Building the framework

The official iOS client builds `TgVoipWebrtc` with Bazel rather than SwiftPM or
CocoaPods. Clone Telegram-iOS recursively and prepare its normal build input,
then run:

```sh
scripts/build-tgvoip-xcframework.sh /path/to/Telegram-iOS
```

Xcode Cloud downloads the pinned artifact built from Telegram iOS
`6e370e06d147b091b07903071cb1b8a22152492d` from the sibling artifact
repository:

```text
https://github.com/iebb/mithka-tdjson/releases/download/tgvoip-telegram-ios-6e370e06d147/tgvoip-ios.xcframework.zip
```

The generated XCFramework contains arm64 slices for devices and simulators.
Telegram's current dav1d Bazel target rejects `ios_x86_64`, so the Podfile
excludes the Intel simulator architecture whenever this framework is installed.

Copy or unzip the generated framework to:

```text
ios/LocalPods/tgvoip/TgVoipWebrtc.xcframework
```

Then run `pod install` in `ios`. The Podfile only adds the local pod when the
framework exists, preserving simulator and contributor builds that do not need
group calling.

The implementation was checked against Telegram-iOS master revision
`6e370e06d147b091b07903071cb1b8a22152492d` on 2026-07-11. Pin the source used
for release artifacts and record any revision change with the artifact.
