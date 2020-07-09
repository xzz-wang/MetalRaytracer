//
//  TypesAndConstants.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/25/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import MetalPerformanceShaders

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
    var diffuse: simd_float3
    var specular: simd_float3
    var emission: simd_float3
    
    var shininess: Float
    var roughness: Float
    
    init() {
        diffuse = simd_float3(repeating: 0.0)
        specular = simd_float3(repeating: 0.0)
        emission = simd_float3(repeating: 0.0)
        
        shininess = 1.0
        roughness = 0.0
    }
    
}


class Scene {
    var debugDescription: String {
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
    public var spp: Int = 1
    
    public var cameraOrigin: simd_float3?
    public var cameraLookAt: simd_float3?
    public var cameraUp: simd_float3?
    public var fieldOfView: Float?
    
    // Part two: MPS
    public var accelerationStructure: MPSTriangleAccelerationStructure?
    public var intersector: MPSRayIntersector?
    
    
    public func checkComplete() -> Bool {
        if (cameraOrigin != nil) &&
            cameraLookAt != nil &&
            cameraUp != nil &&
            fieldOfView != nil &&
            accelerationStructure != nil &&
            intersector != nil {
            return true
        }
        
        return false
    }
}
