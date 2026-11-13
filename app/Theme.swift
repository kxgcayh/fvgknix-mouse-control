// The app's look: a dark, translucent window with content on Liquid Glass panels.
// Liquid Glass needs macOS 26; earlier systems get the closest material.

import AppKit
import SwiftUI

enum Theme {
  static let pad: CGFloat = 24
  static let gap: CGFloat = 16
  static let radius: CGFloat = 20
  static let cellRadius: CGFloat = 12
  /// Fill for controls drawn on a panel, e.g. a DPI level or the Try it pad.
  static let cellFill = Color.white.opacity(0.07)
  static let hairline = Color.white.opacity(0.14)
}

/// Blurs the desktop behind the window, darkened so text keeps its contrast on any wallpaper.
struct WindowBackdrop: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    if reduceTransparency {
      Color(white: 0.11)
    } else {
      ZStack {
        BehindWindowBlur()
        Color.black.opacity(0.45)
      }
    }
  }
}

private struct BehindWindowBlur: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }
  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
  /// A panel that groups related controls.
  @ViewBuilder
  func glassPanel(cornerRadius: CGFloat = Theme.radius) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(macOS 26.0, *) {
      glassEffect(.regular, in: shape)
    } else {
      background(.regularMaterial, in: shape).overlay(shape.strokeBorder(Theme.hairline))
    }
  }

  /// Glass buttons on macOS 26; `prominent` marks the main action.
  @ViewBuilder
  func glassButton(prominent: Bool = false) -> some View {
    if #available(macOS 26.0, *) {
      if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
    } else {
      if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
    }
  }
}

/// A panel's heading.
struct PanelTitle: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View { Text(text).font(.headline) }
}
