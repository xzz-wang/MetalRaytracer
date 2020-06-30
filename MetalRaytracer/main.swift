//
//  main.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/20/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import CoreGraphics

print("Hello, World!")

let film = Film(imageWidth: 10, imageHeight: 10)

film.commitColor(atX: 0, atY: 0, color: simd_float3(0.8, 0.6, 0.6))

var image = film.produceCGImage()

// plain write to image
func writeCGImage(_ image: CGImage, to destinationURL: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypePNG, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}


let url = URL(fileURLWithPath: "./output.png")

writeCGImage(image, to: url)
