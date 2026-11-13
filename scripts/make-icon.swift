import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Body: macOS icon grid (824pt squircle inside 1024 canvas)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.white.setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.9, alpha: 1)])!.draw(in: body, angle: -90)
ctx.restoreGState()

NSColor(white: 0, alpha: 0.08).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: 184, yRadius: 184)
rim.lineWidth = 2
rim.stroke()

// Page
let page = CGRect(x: 302, y: 236, width: 420, height: 552)
let fold: CGFloat = 116
let pagePath = NSBezierPath()
pagePath.move(to: NSPoint(x: page.minX + 44, y: page.minY))
pagePath.line(to: NSPoint(x: page.maxX - 44, y: page.minY))
pagePath.curve(to: NSPoint(x: page.maxX, y: page.minY + 44), controlPoint1: NSPoint(x: page.maxX - 20, y: page.minY), controlPoint2: NSPoint(x: page.maxX, y: page.minY + 20))
pagePath.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
pagePath.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
pagePath.line(to: NSPoint(x: page.minX + 44, y: page.maxY))
pagePath.curve(to: NSPoint(x: page.minX, y: page.maxY - 44), controlPoint1: NSPoint(x: page.minX + 20, y: page.maxY), controlPoint2: NSPoint(x: page.minX, y: page.maxY - 20))
pagePath.line(to: NSPoint(x: page.minX, y: page.minY + 44))
pagePath.curve(to: NSPoint(x: page.minX + 44, y: page.minY), controlPoint1: NSPoint(x: page.minX, y: page.minY + 20), controlPoint2: NSPoint(x: page.minX + 20, y: page.minY))
pagePath.close()

ctx.saveGState()
let pageShadow = NSShadow()
pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
pageShadow.shadowBlurRadius = 30
pageShadow.shadowOffset = NSSize(width: 0, height: -12)
pageShadow.set()
NSColor(white: 0.1, alpha: 1).setFill()
pagePath.fill()
ctx.restoreGState()

ctx.saveGState()
pagePath.addClip()
NSGradient(colors: [NSColor(white: 0.22, alpha: 1), NSColor(white: 0.06, alpha: 1)])!.draw(in: page, angle: -90)
ctx.restoreGState()

// Folded corner
let corner = NSBezierPath()
corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold + 26))
corner.curve(to: NSPoint(x: page.maxX - fold + 26, y: page.maxY - fold), controlPoint1: NSPoint(x: page.maxX - fold, y: page.maxY - fold + 10), controlPoint2: NSPoint(x: page.maxX - fold + 10, y: page.maxY - fold))
corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
corner.close()
NSColor(white: 0.42, alpha: 1).setFill()
corner.fill()

// Text lines
NSColor(white: 1, alpha: 0.95).setFill()
NSBezierPath(roundedRect: CGRect(x: page.minX + 64, y: page.maxY - 196, width: 190, height: 40), xRadius: 20, yRadius: 20).fill()
NSColor(white: 1, alpha: 0.42).setFill()
for (i, w) in [292.0, 250.0, 292.0, 180.0].enumerated() {
    let y = page.maxY - 290 - CGFloat(i) * 64
    NSBezierPath(roundedRect: CGRect(x: page.minX + 64, y: y, width: CGFloat(w), height: 24), xRadius: 12, yRadius: 12).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
