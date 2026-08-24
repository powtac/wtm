#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(Data("Usage: render-dmg-background.swift OUTPUT VERSION\n".utf8))
  exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let version = CommandLine.arguments[2]
let canvasSize = NSSize(width: 660, height: 420)
let image = NSImage(size: canvasSize)

image.lockFocus()

let canvas = NSRect(origin: .zero, size: canvasSize)
let gradient = NSGradient(
  starting: NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1),
  ending: NSColor(red: 0.10, green: 0.16, blue: 0.25, alpha: 1)
)
gradient?.draw(in: canvas, angle: -22)

NSColor(red: 0.49, green: 0.88, blue: 0.76, alpha: 0.14).setFill()
NSBezierPath(ovalIn: NSRect(x: 390, y: 110, width: 390, height: 390)).fill()

let markColor = NSColor(red: 0.49, green: 0.88, blue: 0.76, alpha: 1)
for offset in [-20.0, 0, 20.0] {
  let rect = NSRect(x: 64, y: 292 + offset, width: 56, height: 22)
  let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
  path.lineWidth = 4
  markColor.setStroke()
  NSColor(red: 0.07, green: 0.12, blue: 0.14, alpha: 1).setFill()
  path.fill()
  path.stroke()
}

let titleStyle: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 34, weight: .bold),
  .foregroundColor: NSColor.white,
]
let detailStyle: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 16, weight: .regular),
  .foregroundColor: NSColor(white: 0.78, alpha: 1),
]
let hintStyle: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 14, weight: .medium),
  .foregroundColor: markColor,
]

NSAttributedString(string: "What The Model", attributes: titleStyle)
  .draw(at: NSPoint(x: 140, y: 296))
NSAttributedString(string: "Local LLM inventory for macOS · v\(version)", attributes: detailStyle)
  .draw(at: NSPoint(x: 66, y: 252))
NSAttributedString(string: "Drag WTM to Applications", attributes: hintStyle)
  .draw(at: NSPoint(x: 229, y: 58))
image.unlockFocus()

guard
  let tiff = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  FileHandle.standardError.write(Data("Could not render DMG background.\n".utf8))
  exit(1)
}

try png.write(to: outputURL, options: .atomic)
