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
    
    // Metal Objects
    private var commandQueue: MTLCommandQueue!
    
    // Pipelines
    private var initRayPipeline: MTLComputePipelineState!
    private var neePipeline: MTLComputePipelineState! // Next-event estimation, execute after itersections were found
    private var shadingPipeline: MTLComputePipelineState! // Shade the image and proeduce bounces
    
    // Buffers
    // Read-only Buffers
    private var sceneDataBuffer: MTLBuffer!
    private var triVertexBuffer: MTLBuffer!
    private var triMaterialBuffer: MTLBuffer!

    // InitRays
    private var rayBuffer: MTLBuffer!
    private var intersectionBuffer: MTLBuffer!
    private var outputImageBuffer: MTLBuffer!
    
    
    /**
     Helper method that loads scene for later use. Metal device reference, accelerationStructure, and MPSRayintersector are all setup here.
     */
    private func setupScene(path: String) -> Bool {
        // Load the Scene from the input file
        let loader = SceneLoader()
        guard let newScene = loader.loadScene(path: path) else {
            print("Can not load the scene from path!")
            return false
        }
        
        if !newScene.isComplete() {
            print("Incomplete information in the scene!")
            return false
        }
        
        scene = newScene
        
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
        
        // Initialize Vertex Buffer
        if let buffer = scene.metalDevice!.makeBuffer(bytes: scene.triVerts, length: scene.triVerts.count * MemoryLayout<simd_float3>.size, options: .storageModeShared) {
            triVertexBuffer = buffer
        } else {
            print("Unable to generate vertex buffer")
            return false
        }
        
        // Initialize Triangle Material
        if let buffer = scene.metalDevice!.makeBuffer(bytes: scene.triMaterial, length: scene.triMaterial.count * MemoryLayout<Material>.size, options: .storageModeShared) {
            triMaterialBuffer = buffer
        } else {
            print("Unable to generate material buffer")
            return false
        }

        // Initialize Output Image data Buffer
        if let buffer = scene.metalDevice!.makeBuffer(length: length * MemoryLayout<RGBData>.size, options: .storageModeShared) {
            outputImageBuffer = buffer
        } else {
            print("Unable to generate output buffer")
            return false
        }
        
        return true
    }
    
    
    /**
     Setup the commandQueue and all the pipelines needed for rendering
     */
    private func setupPipelines() -> Bool {
        // Get default library
        guard let defaultLibrary = scene.metalDevice?.makeDefaultLibrary() else {
            print("Unable to get defaultLibrary!")
            return false
        }
        
        // Pipeline 1: Initialize all the rays
        guard let initRayFunction = defaultLibrary.makeFunction(name: "generateInitRay") else {
            print("Failed to fetch initRay shader method")
            return false
        }
        
        // Pipeline 2: compute nee
        guard let neeKernalFunc = defaultLibrary.makeFunction(name: "neeKernel") else {
            print("Failed to fetch nee kernel method")
            return false
        }
        
        do {
            initRayPipeline = try scene.metalDevice?.makeComputePipelineState(function: initRayFunction)
            neePipeline = try scene.metalDevice?.makeComputePipelineState(function: neeKernalFunc)
        } catch {
            print("Failed to create Pipelines")
            return false
        }

        
        guard let queue = scene.metalDevice?.makeCommandQueue() else {
            print("Unable to generate command queue")
            return false
        }
        commandQueue = queue
        
        return true
    }
    
    
    /**
     The core of the rendering engine. Everything goes here.
     */
    public func render(filename sourcePath: String) {
        
        // Perform setup
        if !setupScene(path: sourcePath) { return }
        if !setupBuffers() { return }
        if !setupPipelines() { return }

        // Start the rendering stopwatch
        let startTime = Date.init()
        
        // Create the command buffer needed
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Unable to generate command Buffer")
            return
        }
        
        // MARK: Step 1: Generate all initial rays
        let initRayEncoder = commandBuffer.makeComputeCommandEncoder()
        initRayEncoder?.setComputePipelineState(initRayPipeline)
        initRayEncoder?.setBuffer(sceneDataBuffer, offset: 0, index: 0)
        initRayEncoder?.setBuffer(rayBuffer, offset: 0, index: 1)
        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroups = MTLSize(width: (Int(scene.imageSize.x)  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
                                   height: (Int(scene.imageSize.y) + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                                   depth: 1);
        initRayEncoder?.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup) // Copied from example
        initRayEncoder?.endEncoding()
                        
        // MARK: Step 2: Loop until all the rays are terminated.
        var depthCount = 0
        while depthCount != scene.maxDepth {
            
            // Find intersections
            scene.intersector?.encodeIntersection(
                commandBuffer: commandBuffer,
                intersectionType: .nearest,
                rayBuffer: rayBuffer,
                rayBufferOffset: 0,
                intersectionBuffer: intersectionBuffer,
                intersectionBufferOffset: 0,
                rayCount: scene.pixelCount,
                accelerationStructure: scene.accelerationStructure!)
            
            // Compute the NEE intersection jobs
            let shadingEncoder = commandBuffer.makeComputeCommandEncoder()
            shadingEncoder?.setComputePipelineState(neePipeline)
            shadingEncoder?.setBuffer(sceneDataBuffer, offset: 0, index: 0)
            shadingEncoder?.setBuffer(triVertexBuffer, offset: 0, index: 1)
            shadingEncoder?.setBuffer(triMaterialBuffer, offset: 0, index: 2)
            shadingEncoder?.setBuffer(rayBuffer, offset: 0, index: 3)
            shadingEncoder?.setBuffer(intersectionBuffer, offset: 0, index: 4)
            shadingEncoder?.setBuffer(outputImageBuffer, offset: 0, index: 5)
            shadingEncoder?.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            shadingEncoder?.endEncoding()
            
            depthCount += 1
            depthCount = scene.maxDepth
        }
        
        commandBuffer.commit()
        print("Command Comitted")
        
        commandBuffer.waitUntilCompleted()
        print("Command completed")
        
        let film = Film(size: scene.imageSize, outputFileName: scene.outputName)
        let pointer = outputImageBuffer.contents().bindMemory(to: RGBData.self, capacity: scene.pixelCount)
        let imageData = Array(UnsafeBufferPointer(start: pointer, count: scene.pixelCount))
        film.setImageData(data: imageData)
        if !film.saveImage() {
            print("Image save failed")
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
