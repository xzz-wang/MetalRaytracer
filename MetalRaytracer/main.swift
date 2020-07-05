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


// TODO: Parse the input filename from command line.

let inputFileName = "./hw1/scene1.test"
let engine = Engine()
engine.render(filename: "./inputTest.test")



//let film = Film(imageWidth: 400, imageHeight: 600)
//
//film.commitColor(atX: 0, atY: 0, color: simd_float3(0.8, 0.6, 0.6))
//
//let success = film.saveImage()
//
//if success {
//    print("Image successfully saved!")
//} else {
//    print("Image failed saving!")
//}
