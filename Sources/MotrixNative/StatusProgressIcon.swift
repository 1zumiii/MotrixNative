import AppKit

struct ProgressSummary {
  let progress: Double
  let taskCount: Int
  let hasIncompleteTasks: Bool

  var percent: Int {
    Int((min(1, max(0, progress)) * 100).rounded())
  }

  var statusTitle: String {
    guard hasIncompleteTasks else {
      return ""
    }

    if taskCount > 1 {
      return "\(taskCount) \(percent)%"
    }

    return "\(percent)%"
  }
}

enum StatusProgressIcon {
  private static let progressColor = NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.54, alpha: 1)
  private static let completeColor = NSColor(calibratedRed: 0.18, green: 0.64, blue: 0.35, alpha: 1)
  private static let trackColor = NSColor(calibratedWhite: 0.68, alpha: 0.42)

  static func renderError() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    rect.fill()
    drawSymbol("exclamationmark.circle.fill", in: rect, color: .systemOrange)
    image.isTemplate = false
    return image
  }

  static func renderCompletion() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    rect.fill()
    drawSymbol("checkmark.circle.fill", in: rect, color: completeColor)
    image.isTemplate = false
    return image
  }

  static func render(_ summary: ProgressSummary?) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    rect.fill()

    guard let summary else {
      drawSymbol("arrow.down.circle", in: rect, color: .labelColor)
      image.isTemplate = true
      return image
    }

    if !summary.hasIncompleteTasks && summary.percent >= 100 {
      drawSymbol("checkmark.circle.fill", in: rect, color: completeColor)
      image.isTemplate = false
      return image
    }

    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radius: CGFloat = 7
    let lineWidth: CGFloat = 2.2

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    trackColor.setStroke()
    track.stroke()

    let progress = min(1, max(0, summary.progress))
    if progress > 0 {
      let arc = NSBezierPath()
      arc.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 90,
        endAngle: 90 - (360 * progress),
        clockwise: true
      )
      arc.lineCapStyle = .round
      arc.lineWidth = lineWidth
      progressColor.setStroke()
      arc.stroke()
    }

    let innerRect = rect.insetBy(dx: 5.25, dy: 5.25)
    drawSymbol("arrow.down", in: innerRect, color: NSColor(calibratedWhite: 0.58, alpha: 0.95))
    image.isTemplate = false
    return image
  }

  private static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
      return
    }

    symbol.lockFocus()
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    symbol.unlockFocus()

    symbol.draw(in: rect)
  }
}
