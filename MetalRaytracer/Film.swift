//
//  Film.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/25/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import CoreGraphics
import simd


class Film {
    
    var width: Int!
    var height: Int!
    
    var outputFileName: String!
    
    // Three floats are a pixel, each representing RGB, row first
    var colorBuffer: [RGBData]
    
    
    // Initialization
    init(imageWidth width: Int, imageHeight height: Int, outputFileName name: String = "output.png") {
        self.width = width
        self.height = height
        outputFileName = name
        
        colorBuffer = [RGBData](repeating: RGBData(), count: width * height)
    }
    
    
    // Update the color in the color buffer array
    func commitColor(atX x: Int, atY y:Int, color: simd_float3) {
        let index = x * width + y;
        colorBuffer[index] = RGBData(color: color);
    }
    
    // Convert the data to CGImage
    func produceCGImage() -> CGImage {
        
        // 8 Bit RGBA Color Space
        let bitsPerComponent:Int = 8
        let bitsPerPixel:Int = 32
        
        let providerRef: CGDataProvider = CGDataProvider(
            data: NSData(bytes: colorBuffer, length: colorBuffer.count * MemoryLayout.size(ofValue: colorBuffer[0]))
        )!
        
        let bmi = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue);


        let cgim = CGImage.init(
            width: width,
            height: height,
            bitsPerComponent:
            bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: width * MemoryLayout.size(ofValue: colorBuffer[0]),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bmi,
            provider: providerRef,
            decode: nil,
            shouldInterpolate: false,
            intent: CGColorRenderingIntent.defaultIntent
        )
        
        return cgim!

    }
    
    // Save the image to file
    func saveImage() {
        let image = produceCGImage()
    }
    
}


struct RGBData {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8 = 255
    
    init() {
        r = 0
        g = 0
        b = 0
    }
    
    init(color: simd_float3) {
        r = UInt8(color.x * 255)
        g = UInt8(color.y * 255)
        b = UInt8(color.z * 255)
    }
    
}
