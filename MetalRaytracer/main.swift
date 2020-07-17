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
engine.render(filename: "./hw1/scene4-emission.test")




func testFilm() {
    let film = Film(imageWidth: 400, imageHeight: 400)
    
    for x in 0..<400 {
        for y in 0..<400 {
            film.commitColor(atX: x, atY: y, color: simd_float3(Float(x) / 400, Float(y) / 400, Float(y) / 400))
        }
    }

    let success = film.saveImage()

    if success {
        print("Image successfully saved!")
    } else {
        print("Image failed saving!")
    }
}
