import AppKit
let directory = CommandLine.arguments[1]
func draw(_ pixels: Int) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
    let scale = CGFloat(pixels)/1024
    let transform = NSAffineTransform(); transform.scale(by:scale); transform.concat()
    let tile = NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:206,yRadius:206)
    NSGradient(starting:NSColor(srgbRed:0.035,green:0.37,blue:0.37,alpha:1),ending:NSColor(srgbRed:0.07,green:0.69,blue:0.62,alpha:1))!.draw(in:tile,angle:75)
    NSColor(srgbRed:1,green:0.83,blue:0.38,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:284,y:690,width:112,height:112)).fill()
    NSColor.white.setStroke()
    let tick = NSBezierPath(); tick.lineWidth=86; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
    tick.move(to:NSPoint(x:292,y:493)); tick.line(to:NSPoint(x:447,y:341)); tick.line(to:NSPoint(x:737,y:645)); tick.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory+"/icon_\(pixels).png"))
}
for size in [16,32,64,128,256,512,1024] { try draw(size) }
