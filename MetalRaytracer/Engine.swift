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
    private var scene: Scene!
    
    // Buffers
    private var rayBuffer: MTLBuffer!
    private var intersectionBuffer: MTLBuffer!
    private var sceneDataBuffer: MTLBuffer!
    
    
    /**
     Helper method that loads scene for later use. Metal device reference, accelerationStructure, and MPSRayintersector are all setup here.
     */
    private func setupScene(path: String) -> Bool {
        // Load the Scene from the input file
        let loader = SceneLoader()
        guard let newaScene = loader.loadScene(path: path) else {
            print("Can not load the scene from path!")
            return false
        }
        
        if !newaScene.isComplete() {
            print("Incomplete information in the scene!")
            return false
        }
        
        scene = newaScene
        
        return true
    }
    
    
    /**
     Helper method that sets up all required buffers. Only called once after setupScene
     */
    private func setupBuffers() -> Bool {
        let length = Int(scene.imageSize.x * scene.imageSize.y)
        
        // Initialize SceneData buffer
        let data = [scene.getSceneData()]
        if let buffer = scene.metalDevice!.makeBuffer(bytes: data ,length: MemoryLayout<SceneData>.size, options: .storageModeShared) {
            sceneDataBuffer = buffer
        } else {
            print("Unable to initialize sceneDataBuffer!")
            return false
        }
        
        
        // Initialize RayBuffer
        if let buffer = scene.metalDevice!.makeBuffer(length: length * MemoryLayout<Ray>.size, options: .storageModeShared) {
            rayBuffer = buffer
        } else {
            print("Unable to initialize rayBuffer!")
            return false
        }
        
        // Initialize Intersection Buffer
        if let buffer = scene.metalDevice!.makeBuffer(length: MemoryLayout<Intersection>.size * length, options: .storageModeShared) {
            intersectionBuffer = buffer
        } else {
            print("Unable to generate intersectionBuffer!")
            return false
        }
        
        return true
    }
    
    
    /**
     The core of the rendering engine. Everything goes here.
     */
    public func render(filename sourcePath: String) {
        
        // Perform setup
        if !setupScene(path: sourcePath) {
            return
        }
        
        if !setupBuffers() {
            return
        }
        
        // Start the rendering stopwatch
        let startTime = Date.init()
        
        // Get default library
        guard let defaultLibrary = scene.metalDevice?.makeDefaultLibrary() else {
            print("Unable to get defaultLibrary!")
            return
        }
        
        guard let initRayFunction = defaultLibrary.makeFunction(name: "generateInitRay") else {
            print("Failed to fetch initRay shader method")
            return
        }
        
        guard let commandQueue = scene.metalDevice?.makeCommandQueue() else {
            print("Unable to generate command queue")
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Unable to generate command Buffer")
            return
        }
        
        // MARK: Step 1: Generate all initial rays
        var initRayPipeline: MTLComputePipelineState!
        do {
            initRayPipeline = try scene.metalDevice?.makeComputePipelineState(function: initRayFunction)
        } catch {
            print("Failed to create initRayPipeline")
            return
        }
        
        let initRayEncoder = commandBuffer.makeComputeCommandEncoder()
        initRayEncoder?.setComputePipelineState(initRayPipeline)
        initRayEncoder?.setBuffer(sceneDataBuffer, offset: 0, index: 0)
        initRayEncoder?.setBuffer(rayBuffer, offset: 0, index: 1)
        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroups = MTLSize(width: (Int(scene.imageSize.x)  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
                                   height: (Int(scene.imageSize.y) + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                                   depth: 1);
        print(initRayPipeline.maxTotalThreadsPerThreadgroup)
        initRayEncoder?.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup) // Copied from example
        initRayEncoder?.endEncoding()
                        
        // MARK: Step 2: Loop until all the rays are terminated.
        var depthCount = 0
        while depthCount != scene.maxDepth {
                        
            scene.intersector?.encodeIntersection(
                commandBuffer: commandBuffer,
                intersectionType: .nearest,
                rayBuffer: rayBuffer,
                rayBufferOffset: 0,
                intersectionBuffer: intersectionBuffer,
                intersectionBufferOffset: 0,
                rayCount: scene.pixelCount,
                accelerationStructure: scene.accelerationStructure!)
                        
            commandBuffer.commit()
            print("Command Comitted")
            
            commandBuffer.waitUntilCompleted()
            print("Command completed")
            
            // Loop through each pixel and calculate the contribution
            let pointer = intersectionBuffer.contents().bindMemory(to: Intersection.self, capacity: scene.pixelCount)
            let intersections: [Intersection] = Array(UnsafeBufferPointer(start: pointer, count: scene.pixelCount))
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
