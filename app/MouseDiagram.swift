// A top view of the mouse. Each button is a clickable zone, and callouts show what it does now.
// The drawing is original, made from a description of the IGNIX F5: adjust `MouseArt` to move anything.

import SwiftUI

/// Geometry in a fixed 460 × 380 space; the view scales it to fit.
enum MouseArt {
  static let size = CGSize(width: 460, height: 380)

  static let body: Path = {
    var p = Path()
    p.move(to: CGPoint(x: 230, y: 40))
    p.addCurve(to: CGPoint(x: 304, y: 112), control1: CGPoint(x: 276, y: 40), control2: CGPoint(x: 304, y: 66))
    p.addCurve(to: CGPoint(x: 294, y: 214), control1: CGPoint(x: 304, y: 152), control2: CGPoint(x: 290, y: 178))
    p.addCurve(to: CGPoint(x: 230, y: 320), control1: CGPoint(x: 300, y: 276), control2: CGPoint(x: 276, y: 320))
    p.addCurve(to: CGPoint(x: 166, y: 214), control1: CGPoint(x: 184, y: 320), control2: CGPoint(x: 160, y: 276))
    p.addCurve(to: CGPoint(x: 156, y: 112), control1: CGPoint(x: 170, y: 178), control2: CGPoint(x: 156, y: 152))
    p.addCurve(to: CGPoint(x: 230, y: 40), control1: CGPoint(x: 156, y: 66), control2: CGPoint(x: 184, y: 40))
    p.closeSubpath()
    return p
  }()

  private static let wheelRect = CGRect(x: 221, y: 78, width: 18, height: 50)
  private static let mainButtonsBottom: CGFloat = 168

  /// The top of the body on one side of the centre line, with room cut out for the wheel.
  private static func mainButton(_ rect: CGRect) -> Path {
    let wheelGap = CGPath(roundedRect: wheelRect.insetBy(dx: -4, dy: -4), cornerWidth: 13, cornerHeight: 13, transform: nil)
    return Path(body.cgPath.intersection(CGPath(rect: rect, transform: nil)).subtracting(wheelGap))
  }

  /// Zone shape for buttons 1–5.
  static let zones: [Int: Path] = [
    1: mainButton(CGRect(x: 0, y: 0, width: 227, height: mainButtonsBottom)),
    2: mainButton(CGRect(x: 233, y: 0, width: 227, height: mainButtonsBottom)),
    3: Path(roundedRect: wheelRect, cornerRadius: 9),
    4: Path(roundedRect: CGRect(x: 150, y: 190, width: 20, height: 38), cornerRadius: 7),   // back: rear side button
    5: Path(roundedRect: CGRect(x: 147, y: 146, width: 20, height: 38), cornerRadius: 7),   // forward: front side button
  ]
  static let dpiButton = Path(roundedRect: CGRect(x: 223, y: 182, width: 14, height: 24), cornerRadius: 5)

  enum Side { case left, right, top }
  struct Callout {
    let anchor: CGPoint   // where the leader line starts, on the zone
    let side: Side
    let y: CGFloat        // the label's centre line (ignored for .top)
  }
  static let callouts: [Int: Callout] = [
    1: Callout(anchor: CGPoint(x: 176, y: 84), side: .left, y: 84),
    5: Callout(anchor: CGPoint(x: 147, y: 165), side: .left, y: 165),
    4: Callout(anchor: CGPoint(x: 150, y: 209), side: .left, y: 236),
    2: Callout(anchor: CGPoint(x: 284, y: 84), side: .right, y: 84),
    3: Callout(anchor: CGPoint(x: 230, y: 78), side: .top, y: 0),
  ]
  static let dpiCallout = Callout(anchor: CGPoint(x: 237, y: 194), side: .right, y: 236)

  static let labelWidth: CGFloat = 118
  static let leftEdge: CGFloat = 122    // left labels end here
  static let rightEdge: CGFloat = 338   // right labels start here
  static let topLabelY: CGFloat = 18
}

/// What a button does now, in a few characters.
func actionSummary(_ action: ButtonAction, button: Int) -> String {
  switch action.kind {
  case .standard: "Normal"
  case .disabled: "Off"
  case .shortcut: action.keyCode == nil ? "No shortcut yet" : action.shortcutText
  case .button: Ignix.buttonNames[action.button ?? button] ?? "Normal"
  }
}

struct MouseDiagram: View {
  @Binding var selection: Int
  let config: IgnixConfig
  /// e.g. "Level 2 · 2400", shown beside the DPI button.
  let dpiText: String?
  @State private var hovered: Int?

  var body: some View {
    GeometryReader { geo in
      let fit = min(geo.size.width / MouseArt.size.width, geo.size.height / MouseArt.size.height)
      drawing
        .frame(width: MouseArt.size.width, height: MouseArt.size.height)
        .scaleEffect(min(max(fit, 0.8), 1.35))
        .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  private var drawing: some View {
    ZStack {
      MouseBody()
      leaders
      ForEach(1...Ignix.buttonCount, id: \.self) { button in
        Zone(button: button, selection: $selection, hovered: hovered == button,
             label: "Button \(button), \(Ignix.buttonNames[button]!), \(actionSummary(config.action(for: button), button: button))")
      }
      MouseArt.dpiButton.fill(.white.opacity(0.18))
      MouseArt.dpiButton.stroke(.white.opacity(0.35), lineWidth: 1)
      ForEach(1...Ignix.buttonCount, id: \.self) { button in
        label(for: button)
      }
      CalloutLabel(title: "DPI button", value: dpiText ?? "Cycles the levels", side: .right, selected: false)
        .position(labelCentre(MouseArt.dpiCallout))
        .accessibilityElement(children: .combine)
    }
    .onContinuousHover { phase in
      switch phase {
      case .active(let point): hovered = MouseArt.zones.first { $0.value.contains(point) }?.key
      case .ended: hovered = nil
      }
    }
  }

  private func label(for button: Int) -> some View {
    let callout = MouseArt.callouts[button]!
    return CalloutLabel(title: Ignix.buttonNames[button]!,
                        value: actionSummary(config.action(for: button), button: button),
                        side: callout.side, selected: selection == button)
      .contentShape(Rectangle())
      .onTapGesture { selection = button }
      .position(labelCentre(callout))
      .accessibilityHidden(true)   // the zone carries the same information as a button
  }

  private func labelCentre(_ callout: MouseArt.Callout) -> CGPoint {
    switch callout.side {
    case .left: CGPoint(x: MouseArt.leftEdge - MouseArt.labelWidth / 2, y: callout.y)
    case .right: CGPoint(x: MouseArt.rightEdge + MouseArt.labelWidth / 2, y: callout.y)
    case .top: CGPoint(x: callout.anchor.x, y: MouseArt.topLabelY)
    }
  }

  /// Thin lines from each zone to its label, with a dot on the zone.
  private var leaders: some View {
    Canvas { context, _ in
      for (button, callout) in MouseArt.callouts.map({ ($0.key as Int?, $0.value) }) + [(nil, MouseArt.dpiCallout)] {
        var line = Path()
        line.move(to: callout.anchor)
        switch callout.side {
        case .left:
          line.addLine(to: CGPoint(x: MouseArt.leftEdge + 16, y: callout.y))
          line.addLine(to: CGPoint(x: MouseArt.leftEdge + 4, y: callout.y))
        case .right:
          line.addLine(to: CGPoint(x: MouseArt.rightEdge - 16, y: callout.y))
          line.addLine(to: CGPoint(x: MouseArt.rightEdge - 4, y: callout.y))
        case .top:
          line.addLine(to: CGPoint(x: callout.anchor.x, y: MouseArt.topLabelY + 20))
        }
        let active = button != nil && button == selection
        context.stroke(line, with: .color(.white.opacity(active ? 0.9 : 0.4)), lineWidth: 1)
        let dot = CGRect(x: callout.anchor.x - 2.5, y: callout.anchor.y - 2.5, width: 5, height: 5)
        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(active ? 1 : 0.7)))
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// The mouse's shell: Liquid Glass where the system has it.
private struct MouseBody: View {
  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        Color.clear.glassEffect(.regular, in: MouseArt.body)
      } else {
        MouseArt.body.fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
      }
    }
    .overlay(MouseArt.body.stroke(.white.opacity(0.3), lineWidth: 1))
    .shadow(color: .black.opacity(0.45), radius: 22, y: 14)
    .accessibilityHidden(true)
  }
}

private struct Zone: View {
  let button: Int
  @Binding var selection: Int
  let hovered: Bool
  let label: String
  @FocusState private var focused: Bool

  private var selected: Bool { selection == button }
  private var path: Path { MouseArt.zones[button]! }

  var body: some View {
    Button { selection = button } label: {
      ZStack {
        path.fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(hovered ? 0.24 : 0.1)))
        path.stroke(.white.opacity(selected ? 0.95 : 0.35), lineWidth: 1)
        if focused {
          path.stroke(.white, lineWidth: 2.5)
        }
        Text(String(button))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
          .position(x: path.boundingRect.midX, y: path.boundingRect.midY)
      }
      .frame(width: MouseArt.size.width, height: MouseArt.size.height)
      .contentShape(path)
    }
    .buttonStyle(.plain)
    .focused($focused)
    .focusEffectDisabled()
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .animation(.easeOut(duration: 0.15), value: selected)
    .animation(.easeOut(duration: 0.12), value: hovered)
  }
}

private struct CalloutLabel: View {
  let title: String
  let value: String
  let side: MouseArt.Side
  let selected: Bool

  private var alignment: HorizontalAlignment {
    switch side {
    case .left: .trailing
    case .right: .leading
    case .top: .center
    }
  }

  var body: some View {
    VStack(alignment: alignment, spacing: 1) {
      Text(title).font(.caption).foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      Text(value).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
    }
    .frame(width: MouseArt.labelWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
  }
}
