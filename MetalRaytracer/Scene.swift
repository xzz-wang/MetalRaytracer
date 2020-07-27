//
//  Scene.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/8/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import MetalPerformanceShaders

let rayStride = 48 // 3 * 16 due to alignment of float3

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
    public var pixelCount: Int {
        return Int(imageSize.x * imageSize.y)
    }
    
    public var outputName: String = "output.png"
    public var spp: Int = 1
    
    public var camera: Camera?
    
    
    // Part two: MPS
    public var metalDevice: MTLDevice?
    public var triVertsBuffer: MTLBuffer?
    public var accelerationStructure: MPSTriangleAccelerationStructure?
    public var intersector: MPSRayIntersector?
    
    // Part three: Geometrics
    public var triVerts: [simd_float3] = []
    public var triMaterial: [Material] = []
    
    // Part four: Lights
    public var directionalLights: [DirectionalLight] = []
    public var pointLights: [PointLight] = []
    public var quadLights: [Quadlight] = []
    
    
    public func isComplete() -> Bool {
        if (camera != nil) &&
            accelerationStructure != nil &&
            intersector != nil &&
            metalDevice != nil{
            return true
        }
        
        return false
    }
    
    public func getSceneData() -> SceneData {
        var data = SceneData()
        data.camera = camera!
        data.imageSize = imageSize
        data.pointLightCount = Int32(pointLights.count)
        data.directLightCount = Int32(directionalLights.count)
        data.quadLightCount = Int32(quadLights.count)
        return data
    }
}
