#!/bin/bash
mkdir -p Payload/SwiftStore.app

swiftc -parse-as-library \
       -sdk $(xcrun --sdk iphoneos --show-sdk-path) \
       -target arm64-apple-ios15.0 \
       -emit-executable *.swift \
       -o Payload/SwiftStore.app/SwiftStore

cp Info.plist Payload/SwiftStore.app/Info.plist
zip -r SwiftStore.ipa Payload
