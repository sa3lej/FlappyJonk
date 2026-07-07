import Vision
import CoreImage
import Foundation

// usage: swift cutout.swift in.jpg out.png [x yTop w h]  (crop in top-left coords)
let a = CommandLine.arguments
let input = URL(fileURLWithPath: a[1])
let output = URL(fileURLWithPath: a[2])
var ci = CIImage(contentsOf: input)!
if a.count >= 7 {
    let x = Double(a[3])!, yTop = Double(a[4])!, w = Double(a[5])!, h = Double(a[6])!
    let H = ci.extent.height
    let rect = CGRect(x: x, y: H - yTop - h, width: w, height: h)
    ci = ci.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
}
let ctx = CIContext()
let cg = ctx.createCGImage(ci, from: ci.extent)!
let handler = VNImageRequestHandler(cgImage: cg)
let req = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([req])
guard let res = req.results?.first else { print("NO_SUBJECT"); exit(1) }
let buf = try res.generateMaskedImage(ofInstances: res.allInstances, from: handler, croppedToInstancesExtent: true)
let out = CIImage(cvPixelBuffer: buf)
try ctx.writePNGRepresentation(of: out, to: output, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
print("OK")
