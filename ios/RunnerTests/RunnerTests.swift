import Flutter
import Intents
import UIKit
import UserNotifications
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testHandoffPayloadContainsOnlyNavigationIdentity() throws {
    let payload = try XCTUnwrap(
      HandoffPayload(
        arguments: [
          "version": 1,
          "activityId": "handoff-test",
          "accountUserId": 42,
          "chatId": -100_123,
          "messageId": 88,
        ]
      )
    )

    XCTAssertEqual(payload.accountUserID, 42)
    XCTAssertEqual(payload.chatID, -100_123)
    XCTAssertEqual(payload.messageID, 88)
    XCTAssertNil(payload.dictionary["sessionString"])
  }

  func testHandoffPayloadRejectsZeroAndFutureValues() {
    XCTAssertNil(
      HandoffPayload(
        arguments: [
          "version": 2,
          "activityId": "future",
          "accountUserId": 42,
          "chatId": 7,
        ]
      )
    )
    XCTAssertNil(
      HandoffPayload(
        arguments: [
          "version": 1,
          "activityId": "invalid",
          "accountUserId": 42,
          "chatId": 0,
        ]
      )
    )
    XCTAssertNil(
      HandoffPayload(
        arguments: [
          "version": 1,
          "activityId": "temporary-message",
          "accountUserId": 42,
          "chatId": 7,
          "messageId": -1,
        ]
      )
    )
  }

  @available(iOS 15.0, *)
  func testCommunicationNotificationUsesChatAvatarAndTapPayload() throws {
    let iconURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-notification-chat-icon.png")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    try png.write(to: iconURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: iconURL) }

    let request = try XCTUnwrap(
      CommunicationNotificationRequest(
        arguments: [
          "id": 42,
          "title": "Family",
          "body": "Dinner is ready",
          "conversation_identifier": "2:-100123",
          "sender_name": "Alice",
          "payload": "{\"chat_id\":-100123,\"message_id\":8}",
          "group_conversation": true,
          "play_sound": false,
          "chat_id": -100123,
          "chat_icon_path": iconURL.path,
        ]
      )
    )

    XCTAssertEqual(request.identifier, "mithka.communication.42")
    let content = request.baseContent()
    XCTAssertEqual(content.threadIdentifier, "2:-100123")
    XCTAssertNil(content.sound)
    XCTAssertEqual(
      content.userInfo["payload"] as? String,
      "{\"chat_id\":-100123,\"message_id\":8}"
    )

    let intent = request.messageIntent()
    XCTAssertEqual(intent.sender?.displayName, "Alice")
    XCTAssertNil(intent.sender?.image)
    XCTAssertEqual(intent.conversationIdentifier, "2:-100123")
    XCTAssertEqual(intent.speakableGroupName?.spokenPhrase, "Family")
    XCTAssertNotNil(intent.image(forParameterNamed: \.speakableGroupName))

    let updated = try content.updating(from: intent)
    XCTAssertEqual(updated.body, "Dinner is ready")
  }

  @available(iOS 15.0, *)
  func testPrivateCommunicationNotificationPinsAvatarToSenderParameter() throws {
    let iconURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-private-notification-icon.png")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    try png.write(to: iconURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: iconURL) }
    let request = try XCTUnwrap(
      CommunicationNotificationRequest(
        arguments: [
          "id": 43,
          "title": "Alice",
          "body": "Hello",
          "conversation_identifier": "0:99",
          "sender_name": "Alice",
          "payload": "{\"chat_id\":99}",
          "group_conversation": false,
          "play_sound": true,
          "chat_id": 99,
          "chat_icon_path": iconURL.path,
        ]
      )
    )

    let intent = request.messageIntent()

    XCTAssertNotNil(intent.sender?.image)
    XCTAssertNotNil(intent.image(forParameterNamed: \.sender))
  }

  @available(iOS 15.0, *)
  func testRemoteTelegramPushMapsToGroupCommunicationIntent() throws {
    let content = UNMutableNotificationContent()
    content.title = "Family"
    content.body = "Dinner is ready"
    let remote = try XCTUnwrap(
      RemoteCommunicationNotification(
        content: content,
        userInfo: [
          "data": [
            "user_id": "7001",
            "loc_key": "CHAT_MESSAGE_TEXT",
            "loc_args": ["Alice", "Family", "Dinner is ready"],
            "custom": [
              "channel_id": "123",
              "chat_from_id": "42",
              "msg_id": "8",
            ],
          ],
        ]
      )
    )

    XCTAssertEqual(remote.chatId, -1_000_000_000_123)
    XCTAssertEqual(remote.information.title, "Family")
    XCTAssertEqual(remote.information.senderName, "Alice")
    XCTAssertEqual(remote.information.body, "Dinner is ready")
    XCTAssertEqual(
      remote.information.conversationIdentifier,
      "telegram:7001:-1000000000123"
    )
    XCTAssertTrue(remote.information.groupConversation)
    XCTAssertEqual(
      remote.information.messageIntent().speakableGroupName?.spokenPhrase,
      "Family"
    )
  }

  @MainActor
  func testNativeGlassSelectionHierarchyCapsulesRTLAndResize() throws {
    let host = GlassSurfaceHost(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
    var config: [String: Any] = [
      "radius": 999, "selection": 0, "itemCount": 4, "selectionInset": 5,
      "durationMs": 0, "dark": false, "tint": UInt32(0x5CFFFFFF),
      "selectionTint": UInt32(0x1A007AFF), "rtl": false,
    ]
    host.apply(config)
    let outer = try XCTUnwrap(host.subviews.first as? UIVisualEffectView)
    let selected = try XCTUnwrap(outer.contentView.subviews.first as? UIVisualEffectView)
    XCTAssertEqual(host.subviews.count, 1)
    XCTAssertFalse(host.isUserInteractionEnabled)
    XCTAssertTrue(host.accessibilityElementsHidden)
    XCTAssertEqual(outer.frame, host.bounds)
    XCTAssertEqual(outer.layer.cornerRadius, 36)
    XCTAssertEqual(selected.frame, CGRect(x: 5, y: 5, width: 72.5, height: 62))
    XCTAssertEqual(selected.layer.cornerRadius, 31)

    for count in 1...4 {
      for rtl in [false, true] {
        for selection in 0..<count {
          config["itemCount"] = count
          config["selection"] = selection
          config["rtl"] = rtl
          host.apply(config)
          let width = CGFloat(290) / CGFloat(count)
          let slot = rtl ? count - 1 - selection : selection
          // UIView stores center + bounds, so fractional third-slot origins can
          // round by ~1e-14 when frame is reconstructed. Keep subpixel accuracy
          // without requiring bit-identical floating-point arithmetic.
          XCTAssertEqual(selected.frame.minX, 5 + CGFloat(slot) * width, accuracy: 0.000001)
          XCTAssertEqual(selected.frame.minY, 5, accuracy: 0.000001)
          XCTAssertEqual(selected.frame.width, width, accuracy: 0.000001)
          XCTAssertEqual(selected.frame.height, 62, accuracy: 0.000001)
          XCTAssertEqual(selected.layer.cornerRadius, min(width, 62) / 2)
        }
      }
    }
    config["itemCount"] = 4
    config["selection"] = 1
    config["rtl"] = true
    host.apply(config)
    host.frame.size = CGSize(width: 180, height: 100)
    host.setNeedsLayout()
    host.layoutIfNeeded()
    XCTAssertEqual(outer.frame, host.bounds)
    XCTAssertEqual(outer.layer.cornerRadius, 50)
    XCTAssertEqual(selected.frame, CGRect(x: 90, y: 5, width: 42.5, height: 90))
    XCTAssertEqual(selected.layer.cornerRadius, 21.25)
    config["selection"] = -1
    host.apply(config)
    XCTAssertTrue(selected.isHidden)
  }

  @MainActor
  func testNativeGlassOpaqueFallbackAndFreshTintAssignment() throws {
    let host = GlassSurfaceHost(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
    var config: [String: Any] = [
      "radius": 999, "selection": 1, "itemCount": 3, "selectionInset": 5,
      "durationMs": 0, "dark": false, "highContrast": true,
      "opaqueBackground": UInt32(0xFFEEEEEE), "opaqueSelection": UInt32(0xFFCCDDFF),
      "contrastBorder": UInt32(0xFF007AFF),
    ]
    host.apply(config)
    let outer = try XCTUnwrap(host.subviews.first as? UIVisualEffectView)
    let selected = try XCTUnwrap(outer.contentView.subviews.first as? UIVisualEffectView)
    XCTAssertNil(outer.effect)
    XCTAssertNil(selected.effect)
    XCTAssertEqual(outer.backgroundColor?.cgColor.alpha, 1)
    XCTAssertEqual(selected.backgroundColor?.cgColor.alpha, 1)
    XCTAssertEqual(selected.layer.borderWidth, 1)
    XCTAssertEqual(selected.layer.cornerRadius, 31)

    config["highContrast"] = false
    config["tint"] = UInt32(0x5CFFFFFF)
    config["selectionTint"] = UInt32(0x30007AFF)
    host.apply(config)
    if !UIAccessibility.isReduceTransparencyEnabled && !UIAccessibility.isDarkerSystemColorsEnabled {
      if #available(iOS 26.0, *) {
        let firstOuter = try XCTUnwrap(outer.effect as? UIGlassEffect)
        let firstSelected = try XCTUnwrap(selected.effect as? UIGlassEffect)
        config["dark"] = true
        config["tint"] = UInt32(0x20101010)
        config["selectionTint"] = UInt32(0x4000FF00)
        host.apply(config)
        let nextOuter = try XCTUnwrap(outer.effect as? UIGlassEffect)
        let nextSelected = try XCTUnwrap(selected.effect as? UIGlassEffect)
        XCTAssertFalse(firstOuter === nextOuter)
        XCTAssertFalse(firstSelected === nextSelected)
        XCTAssertNotEqual(firstSelected.tintColor, nextSelected.tintColor)
        XCTAssertEqual(outer.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(selected.overrideUserInterfaceStyle, .dark)
      } else {
        XCTAssertTrue(outer.effect is UIBlurEffect)
        XCTAssertTrue(selected.effect is UIBlurEffect)
        XCTAssertNotNil(selected.contentView.backgroundColor)
      }
    }
  }

  @MainActor
  func testNativeGlassRapidRetargetThenResizeAndReducedDurationSettleLatestSlot() throws {
    let host = GlassSurfaceHost(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
    var config: [String: Any] = [
      "radius": 999, "selection": 0, "itemCount": 4, "selectionInset": 5,
      "durationMs": 280, "dark": false,
    ]
    host.apply(config)
    for selection in [3, 1, 2] {
      config["selection"] = selection
      host.apply(config)
    }
    let outer = try XCTUnwrap(host.subviews.first as? UIVisualEffectView)
    let selected = try XCTUnwrap(outer.contentView.subviews.first as? UIVisualEffectView)
    host.frame.size.width = 220
    host.setNeedsLayout()
    host.layoutIfNeeded()
    XCTAssertEqual(selected.frame, CGRect(x: 110, y: 5, width: 52.5, height: 62))
    config["selection"] = 0
    host.apply(config)
    config["selection"] = 3
    config["durationMs"] = 0
    host.apply(config)
    XCTAssertEqual(selected.frame, CGRect(x: 162.5, y: 5, width: 52.5, height: 62))
    XCTAssertEqual(selected.layer.cornerRadius, 26.25)
    // Endpoint/layout coverage only; live interruption continuity and material
    // contrast still require on-device/simulator optical verification.
  }

}
