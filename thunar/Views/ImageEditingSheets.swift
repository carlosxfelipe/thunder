//
//  ImageEditingSheets.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 16/05/26.
//

import AppKit
import SwiftUI

struct RotateImageSheet: View {
    @Binding var isPresented: Bool
    let item: FileItem
    var onApply: (() -> Void)? = nil

    @State private var rotationDegrees: Double = 90
    @State private var saveAsCopy: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text(LanguageManager.shared.local("rotate_image"))
                .font(.headline)

            Text(item.name)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker(LanguageManager.shared.local("rotation_angle"), selection: $rotationDegrees) {
                Text("90°").tag(90.0)
                Text("180°").tag(180.0)
                Text("270°").tag(270.0)
            }
            .pickerStyle(.segmented)

            Toggle(LanguageManager.shared.local("save_as_copy"), isOn: $saveAsCopy)

            HStack {
                Button(LanguageManager.shared.local("cancel")) {
                    isPresented = false
                }

                Button(LanguageManager.shared.local("apply")) {
                    rotateImage()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func rotateImage() {
        let url = item.url
        // applyOrientationProperty reads EXIF and bakes it into pixels, avoiding orientation conflicts
        guard let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return }

        var orientation: CGImagePropertyOrientation
        switch Int(rotationDegrees) {
        case 90:
            orientation = .right
        case 180:
            orientation = .down
        case 270:
            orientation = .left
        default:
            orientation = .up
        }

        let rotated = ciImage.oriented(orientation)

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(rotated, from: rotated.extent) else { return }

        let newBitmap = NSBitmapImageRep(cgImage: cgImage)
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType = (ext == "png") ? .png : .jpeg

        var targetURL = url
        if saveAsCopy {
            let dir = url.deletingLastPathComponent()
            let base = url.deletingPathExtension().lastPathComponent
            let extensionStr = url.pathExtension

            var newURL = dir.appendingPathComponent("\(base)_edited.\(extensionStr)")
            var counter = 2
            while FileManager.default.fileExists(atPath: newURL.path) {
                newURL = dir.appendingPathComponent("\(base)_edited_\(counter).\(extensionStr)")
                counter += 1
            }
            targetURL = newURL
        }

        if let data = newBitmap.representation(using: type, properties: [:]) {
            try? data.write(to: targetURL)
            DispatchQueue.main.async {
                onApply?()
            }
        }
    }
}

enum ResizeUnit {
    case pixels
    case percent
}

enum ResizeDimension {
    case width
    case height
}

struct ResizeImageSheet: View {
    @Binding var isPresented: Bool
    let item: FileItem
    var onApply: (() -> Void)? = nil

    @State private var newWidth: String = ""
    @State private var newHeight: String = ""
    @State private var maintainAspectRatio: Bool = true
    @State private var unit: ResizeUnit = .pixels
    @State private var primaryDimension: ResizeDimension = .width
    @State private var saveAsCopy: Bool = false

    @State private var originalSize: CGSize = .zero

    private func updateUnits(to newUnit: ResizeUnit) {
        guard originalSize.width > 0, originalSize.height > 0 else { return }

        let currentWidthVal = Double(newWidth) ?? 0
        let currentHeightVal = Double(newHeight) ?? 0

        if newUnit == .percent {
            newWidth = String(Int(round((currentWidthVal / originalSize.width) * 100)))
            newHeight = String(Int(round((currentHeightVal / originalSize.height) * 100)))
        } else {
            newWidth = String(Int(round((currentWidthVal / 100) * originalSize.width)))
            newHeight = String(Int(round((currentHeightVal / 100) * originalSize.height)))
        }
    }

    private func syncDimensions(changedWidth: Bool) {
        guard maintainAspectRatio else { return }

        if changedWidth {
            if let w = Double(newWidth) {
                if unit == .pixels, originalSize.width > 0 {
                    newHeight = String(Int(round(w * (originalSize.height / originalSize.width))))
                } else if unit == .percent {
                    newHeight = newWidth
                }
            }
        } else {
            if let h = Double(newHeight) {
                if unit == .pixels, originalSize.height > 0 {
                    newWidth = String(Int(round(h * (originalSize.width / originalSize.height))))
                } else if unit == .percent {
                    newWidth = newHeight
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(LanguageManager.shared.local("resize_image"))
                .font(.headline)

            Text(item.name)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("", selection: $unit) {
                Text("Pixels (px)").tag(ResizeUnit.pixels)
                Text(LanguageManager.shared.local("percent") + " (%)").tag(ResizeUnit.percent)
            }
            .pickerStyle(.segmented)
            .onChange(of: unit) { newUnit in
                updateUnits(to: newUnit)
            }

            VStack(spacing: 10) {
                HStack {
                    Text(LanguageManager.shared.local("width") + ":")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", text: $newWidth)
                        .textFieldStyle(.roundedBorder)
                        .disabled(maintainAspectRatio && primaryDimension != .width)
                        .onChange(of: newWidth) { _ in
                            if !maintainAspectRatio || primaryDimension == .width {
                                syncDimensions(changedWidth: true)
                            }
                        }
                    Text(unit == .pixels ? "px" : "%")
                        .frame(width: 25, alignment: .leading)
                }

                HStack {
                    Text(LanguageManager.shared.local("height") + ":")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", text: $newHeight)
                        .textFieldStyle(.roundedBorder)
                        .disabled(maintainAspectRatio && primaryDimension != .height)
                        .onChange(of: newHeight) { _ in
                            if !maintainAspectRatio || primaryDimension == .height {
                                syncDimensions(changedWidth: false)
                            }
                        }
                    Text(unit == .pixels ? "px" : "%")
                        .frame(width: 25, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(LanguageManager.shared.local("maintain_aspect_ratio"), isOn: $maintainAspectRatio)

                if maintainAspectRatio {
                    HStack {
                        Text(LanguageManager.shared.local("edit_dimension") + ":")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Picker("", selection: $primaryDimension) {
                            Text(LanguageManager.shared.local("width")).tag(ResizeDimension.width)
                            Text(LanguageManager.shared.local("height")).tag(ResizeDimension.height)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding(.leading, 24)
                }

                Toggle(LanguageManager.shared.local("save_as_copy"), isOn: $saveAsCopy)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            HStack {
                Button(LanguageManager.shared.local("cancel")) {
                    isPresented = false
                }

                Button(LanguageManager.shared.local("apply")) {
                    resizeImage()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            if let image = NSImage(contentsOf: item.url) {
                originalSize = image.size
                newWidth = String(Int(image.size.width))
                newHeight = String(Int(image.size.height))
            }
        }
    }

    private func resizeImage() {
        var finalWidth = 0.0
        var finalHeight = 0.0

        if unit == .percent {
            guard let wPct = Double(newWidth), let hPct = Double(newHeight) else { return }
            finalWidth = (wPct / 100.0) * originalSize.width
            finalHeight = (hPct / 100.0) * originalSize.height
        } else {
            guard let w = Double(newWidth), let h = Double(newHeight) else { return }
            finalWidth = w
            finalHeight = h
        }

        guard finalWidth > 0, finalHeight > 0 else { return }

        let width = finalWidth
        let height = finalHeight
        let url = item.url

        guard let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return }
        let contextCI = CIContext(options: nil)
        guard let cgImage = contextCI.createCGImage(ciImage, from: ciImage.extent) else { return }

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = cgImage.bitmapInfo.rawValue

        guard let context = CGContext(data: nil,
                                      width: Int(width),
                                      height: Int(height),
                                      bitsPerComponent: cgImage.bitsPerComponent,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let newCGImage = context.makeImage() else { return }

        let newBitmap = NSBitmapImageRep(cgImage: newCGImage)
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType = (ext == "png") ? .png : .jpeg

        var targetURL = url
        if saveAsCopy {
            let dir = url.deletingLastPathComponent()
            let base = url.deletingPathExtension().lastPathComponent
            let extensionStr = url.pathExtension

            var newURL = dir.appendingPathComponent("\(base)_edited.\(extensionStr)")
            var counter = 2
            while FileManager.default.fileExists(atPath: newURL.path) {
                newURL = dir.appendingPathComponent("\(base)_edited_\(counter).\(extensionStr)")
                counter += 1
            }
            targetURL = newURL
        }

        if let data = newBitmap.representation(using: type, properties: [:]) {
            try? data.write(to: targetURL)
            DispatchQueue.main.async {
                onApply?()
            }
        }
    }
}
