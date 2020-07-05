//
//  TypesAndConstants.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/25/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd

let PI: Float = 3.1415926535

struct camera {
    let origin: simd_float3
    let imagePlaneTopLeft: simd_float3
    let pixelRight: simd_float3
    let PixelDown: simd_float3
}

struct quadlight {
    let a: simd_float3
    let ab: simd_float3
    let ac: simd_float3
    let intensity: simd_float3
}

struct material {
    let diffuse: simd_float3
    let specular: simd_float3
    let emission: simd_float3
    let ambient: simd_float3
    
    let shininess: Float
    let roughness: Float
}


class Scene {
    var description: String {
        var buildingString = "";
        buildingString += "mapDepth: \t\(maxDepth)\n"
        buildingString += "imageSize: \t\(imageSize)\n"
        buildingString += "outputName: \t\(outputName)\n"

        return buildingString
    }
    
    // Part one: Rendering Specification
    public var maxDepth: Int = -1
    public var imageSize: simd_int2 = simd_int2(400, 400)
    public var outputName: String = "output.png"
    
    public var cameraOrigin: simd_float3!
    public var cameraLookAt: simd_float3!
    public var cameraUp: simd_float3!
    public var fieldOfView: Float!
            
}
