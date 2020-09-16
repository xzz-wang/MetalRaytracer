//
//  Scene.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/8/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import Metal

struct BoundingBox {
    var min: MTLPackedFloat3
    var max: MTLPackedFloat3
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
    public var pixelCount: Int {
        return Int(imageSize.x * imageSize.y)
    }
    
    public var outputName: String = "output.png"
    public var spp: Int = 1
    public var lightsamples: Int = 1
    public var neeOn: Bool = false;
    public var rrOn: Bool = false; // Russian Rullette
    
    public var camera: Camera?
    
    // Part two: Geometrics
    public var triVerts: [simd_float3] = []
    public var triMaterials: [Material] = []
    
    public var spheres: [Sphere] = []
    public var sphereBoundingBoxes: [BoundingBox] = []
    
    // Part three: Lights
    public var directionalLights: [DirectionalLight] = []
    private var directionalLightPadded = false
    public var directionalLightsCount: Int {
        let count = directionalLights.count
        if directionalLightPadded {
            return count - 1
        } else {
            return count
        }
    }
    
    public var pointLights: [PointLight] = []
    private var pointLightPadded = false
    public var pointLightsCount: Int {
        let count = pointLights.count
        if pointLightPadded {
            return count - 1
        } else {
            return count
        }
    }
    
    public var quadLights: [Quadlight] = []
    private var quadLightPadded = false
    public var quadLightsCount: Int {
        let count = quadLights.count
        if quadLightPadded {
            return count - 1
        } else {
            return count
        }
    }
    
    public var shadowRayPerPixel: Int {
        return directionalLightsCount + pointLightsCount + quadLightsCount * lightsamples
    }

    
    public func isComplete() -> Bool {
        if (camera != nil){
            return true
        }
        
        return false
    }
    
    public func makeLightPlaceholders () {
        // Add an invisible light if there's no light of such type
        if directionalLights.count == 0 {
            let newLight = DirectionalLight(toDirection: simd_float3(1.0, 0.0, 0.0), brightness: simd_float3(0.0, 0.0, 0.0))
            directionalLights.append(newLight)
            directionalLightPadded = true
        }
        
        if pointLights.count == 0 {
            let newLight = PointLight(position: simd_float3(0.0, 0.0, 0.0), brightness: simd_float3(0.0, 0.0, 0.0))
            pointLights.append(newLight)
            pointLightPadded = true
        }
        
        if quadLights.count == 0 {
            let newLight = Quadlight(a: simd_float3(0.0, 0.0, 0.0), ab: simd_float3(0.0, 0.0, 0.0), ac: simd_float3(0.0, 0.0, 0.0), intensity: simd_float3(0.0, 0.0, 0.0))
            quadLights.append(newLight)
            quadLightPadded = true
        }

    }
    
    public func getSceneData() -> SceneData {
        var data = SceneData()
        data.camera = camera!
        data.imageSize = imageSize
        data.pointLightCount = Int32(pointLightsCount)
        data.directLightCount = Int32(directionalLightsCount)
        data.quadLightCount = Int32(quadLightsCount)
        data.lightsamples = Int32(lightsamples)
        data.maxDepth = Int32(maxDepth)
        data.neeOn = neeOn ? 1 : 0
        data.rrOn = rrOn ? 1 : 0
        data.spp = Int32(spp)
        return data
    }
}
