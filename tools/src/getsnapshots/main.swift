//
//  main.swift
//  getsnapshots
//
//  Created by Wojciech Kulik on 18/11/2023.
//

import AppKit
import CoreGraphics
import Foundation
import XCTestHTMLReportCore

if CommandLine.arguments.count < 3 {
    print("Missing arguments.\n\nUsage: getsnapshots /path/to/tests.xcresult /path/to/save/snapshots")
}

let xcresultPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/sh"
    task.standardInput = nil
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!

    return output
}

let summary = Summary(
    resultPaths: [xcresultPath],
    renderingMode: .inline,
    downsizeImagesEnabled: false,
    downsizeScaleFactor: 1.0
)
let failedTests = summary.getFailingSnapshotTests()

var allTasks: [Task<(), Never>] = []

for test in failedTests {
    let sanitizedName = test.id
        .replacingOccurrences(of: "(", with: "")
        .replacingOccurrences(of: ")", with: "")
        .replacingOccurrences(of: "/", with: "_")
    allTasks.append(Task {
        mergeImages(
            image1: test.referenceImage,
            image2: test.failureImage,
            image3: test.diffImage,
            outputPath: "\(outputDir)/\(sanitizedName).png"
        )
    })
}

for task in allTasks {
    _ = await task.result
}

func mergeImages(image1: Data?, image2: Data?, image3: Data?, outputPath: String) {
    guard let image1, let image2, let image3 else { return }

    let firstImage = NSImage(data: image1)!
    let secondImage = NSImage(data: image2)!
    let thirdImage = NSImage(data: image3)!

    let padding = 6.0
    let size: CGSize
    let horizontally: Bool
    let areaSize: CGRect

    if firstImage.size.width > firstImage.size.height {
        horizontally = false
        size = CGSize(width: firstImage.size.width, height: firstImage.size.height * 3.0 + padding * 2.0)
        areaSize = CGRect(
            x: 0,
            y: firstImage.size.height * 2.0 + padding * 2.0,
            width: firstImage.size.width,
            height: firstImage.size.height
        )
    } else {
        horizontally = true
        size = CGSize(width: firstImage.size.width * 3.0 + padding * 2.0, height: firstImage.size.height)
        areaSize = CGRect(x: 0, y: 0, width: firstImage.size.width, height: firstImage.size.height)
    }

    guard let offscreenRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else { fatalError() }

    guard let context = NSGraphicsContext(bitmapImageRep: offscreenRep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.current = nil
        NSGraphicsContext.restoreGraphicsState()
    }

    context.cgContext.setFillColor(NSColor.red.cgColor)
    NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()

    firstImage.draw(in: areaSize)
    if horizontally {
        secondImage.draw(in: areaSize.offsetBy(dx: firstImage.size.width + padding, dy: 0.0))
        thirdImage.draw(in: areaSize.offsetBy(dx: firstImage.size.width * 2.0 + padding * 2.0, dy: 0.0))
    } else {
        secondImage.draw(in: areaSize.offsetBy(dx: 0.0, dy: -firstImage.size.height - padding))
        thirdImage.draw(in: areaSize.offsetBy(dx: 0.0, dy: -2.0 * firstImage.size.height - padding * 2.0))
    }

    guard let newImage = context.cgContext.makeImage() else { return }

    let toSaveImage = NSImage(cgImage: newImage, size: size)
    toSaveImage.writePNG(toURL: URL(fileURLWithPath: outputPath))
}

extension NSImage {
    func writePNG(toURL url: URL) {
        guard let data = tiffRepresentation,
              let rep = NSBitmapImageRep(data: data),
              let imgData = rep.representation(using: .png, properties: [.compressionFactor: NSNumber(floatLiteral: 1.0)]) else {
            print("\(self) Error Function '\(#function)' Line: \(#line) No tiff rep found for image writing to \(url)")
            return
        }

        do {
            try imgData.write(to: url)
        } catch {
            print("\(self) Error Function '\(#function)' Line: \(#line) \(error.localizedDescription)")
        }
    }
}
