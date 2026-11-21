import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let scale = CGFloat(size)/512
    let transform = NSAffineTransform(); transform.scale(by:scale); transform.concat()
    NSGradient(starting:NSColor(srgbRed:0.17,green:0.20,blue:0.29,alpha:1),ending:NSColor(srgbRed:0.07,green:0.08,blue:0.13,alpha:1))!.draw(in:NSBezierPath(roundedRect:NSRect(x:20,y:20,width:472,height:472),xRadius:108,yRadius:108),angle:70)
    let stroke = NSBezierPath(); stroke.move(to:NSPoint(x:118,y:167)); stroke.curve(to:NSPoint(x:375,y:204),controlPoint1:NSPoint(x:179,y:91),controlPoint2:NSPoint(x:237,y:276)); stroke.lineWidth = 22; stroke.lineCapStyle = .round
    NSColor(srgbRed:1,green:0.31,blue:0.36,alpha:1).setStroke(); stroke.stroke()
    NSGraphicsContext.saveGraphicsState()
    let pen = NSAffineTransform(); pen.translateX(by:270,yBy:285); pen.rotate(byDegrees:-38); pen.concat()
    NSColor.white.setFill(); NSBezierPath(roundedRect:NSRect(x:-22,y:-49,width:44,height:165),xRadius:12,yRadius:12).fill()
    let tip = NSBezierPath(); tip.move(to:NSPoint(x:-22,y:-45)); tip.line(to:NSPoint(x:0,y:-93)); tip.line(to:NSPoint(x:22,y:-45)); tip.close(); NSColor(srgbRed:1,green:0.73,blue:0.46,alpha:1).setFill(); tip.fill()
    NSColor(srgbRed:1,green:0.31,blue:0.36,alpha:1).setFill(); NSBezierPath(rect:NSRect(x:-22,y:70,width:44,height:23)).fill()
    NSGraphicsContext.restoreGraphicsState(); image.unlockFocus()
    let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!; let data = rep.representation(using:.png,properties:[:])!
    let names:[String]
    switch size {
    case 16:names=["icon_16x16.png"]
    case 32:names=["icon_16x16@2x.png","icon_32x32.png"]
    case 64:names=["icon_32x32@2x.png"]
    case 128:names=["icon_128x128.png"]
    case 256:names=["icon_128x128@2x.png","icon_256x256.png"]
    case 512:names=["icon_256x256@2x.png","icon_512x512.png"]
    default:names=["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to:URL(fileURLWithPath:output).appendingPathComponent(name)) }
}
