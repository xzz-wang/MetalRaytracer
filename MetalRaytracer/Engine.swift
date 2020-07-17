//
//  Engine.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import MetalPerformanceShaders

class Engine {
    public func render(filename sourcePath: String) {
        // Load the Scene from the input file
        let loader = SceneLoader()
        guard let scene = loader.loadScene(path: sourcePath) else {
            print("Can not load the scene from path!")
            return
        }
        
        if !scene.isComplete() {
            print("Incomplete information in the scene!")
            return
        }
        
        // Start the rendering
        let startTime = Date.init()
        
        // MARK: Step 1: Generate all initial rays
        // TODO: Take into account of spp, and maybe move this into different thread
        var initialRays: [Ray] = []
        for y in 0..<scene.imageSize.y {
            for x in 0..<scene.imageSize.x {
                let target = scene.camera!.imagePlaneTopLeft
                    + (Float(x) + 0.5) * scene.camera!.pixelRight
                    + (Float(y) + 0.5) * scene.camera!.pixelDown
                let direction = normalize(target - scene.camera!.origin)
                
                let thisRay = Ray(origin: scene.camera!.origin, direction: direction)
                initialRays.append(thisRay)
            }
        }
        
        // Setup the buffers
        guard let rayBuffer = scene.metalDevice!.makeBuffer(
            bytes: initialRays,
            length: initialRays.count * MemoryLayout<Ray>.size,
            options: .storageModeShared) else {
                print("Unable to generate rayBuffer!")
                return
        }
        guard let intersectionBuffer = scene.metalDevice!.makeBuffer(length: MemoryLayout<Intersection>.size * initialRays.count, options: .storageModeShared) else {
            print("Unable to generate intersectionBuffer!")
            return
        }
        guard let commandQueue = scene.metalDevice?.makeCommandQueue() else {
            print("Unable to generate command buffer")
            return
        }
        
        
        // MARK: Step 2: Loop until all the rays are terminated.
        var depthCount = 0
        while depthCount != scene.maxDepth {
            
            // TODO: Get the result of intersection, then shade
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Unable to generate command queue")
                return
            }
            
            scene.intersector?.encodeIntersection(
                commandBuffer: commandBuffer,
                intersectionType: .nearest,
                rayBuffer: rayBuffer,
                rayBufferOffset: 0,
                intersectionBuffer: intersectionBuffer,
                intersectionBufferOffset: 0,
                rayCount: initialRays.count,
                accelerationStructure: scene.accelerationStructure!)
            
            commandBuffer.commit()
            print("Command Comitted")
            
            commandBuffer.waitUntilCompleted()
            print("Command completed")
            
            // Loop through each pixel and calculate the contribution
            let pointer = intersectionBuffer.contents().bindMemory(to: Intersection.self, capacity: initialRays.count)
            let intersections: [Intersection] = Array(UnsafeBufferPointer(start: pointer, count: initialRays.count))
            let film = Film(size: scene.imageSize, outputFileName: scene.outputName)
            for y in 0..<scene.imageSize.y {
                for x in 0..<scene.imageSize.x {
 
                    let thisIdx = Int(y * scene.imageSize.x + x)
                    let thisHit = intersections[thisIdx]
                    if thisHit.distance < 0 {
                        continue
                    }
                    
                    let triID = Int(thisHit.primitiveIndex)
                    let hitMaterial = scene.triMaterial[triID]
                    let thisRay = initialRays[thisIdx]
                    
                    // Now interpolate the hitPosition
                    let v1 = scene.triVerts[3 * triID + 0]
                    let v2 = scene.triVerts[3 * triID + 1]
                    let v3 = scene.triVerts[3 * triID + 2]
                    let hitPosition = interpolateVec3(v1: v1, v2: v2, v3: v3, coord: thisHit.coordinates)
                    
                    film.commitColor(atX: Int(x), atY: Int(y), color: hitMaterial.emission)
                }
            }
            
            depthCount += 1
            depthCount = scene.maxDepth
            print("Should End!")
            
            film.saveImage()
        }
        
        // Render finished
        print("Rendering time: \(Date.init().timeIntervalSince(startTime))")
        
    }
    
    
    private func interpolateVec3(v1: simd_float3, v2: simd_float3, v3:simd_float3, coord: simd_float2) -> simd_float3 {
        // Barycentric coordinates sum to one
        let x = coord.x
        let y = coord.y
        let z = 1.0 - x - y
        var returnVal = x * v1 + y * v2
        returnVal += z * v3
        
        // Compute sum of vertex attributes weighted by barycentric coordinates
        return returnVal
    }
}
