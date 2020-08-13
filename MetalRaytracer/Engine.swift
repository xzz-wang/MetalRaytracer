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
    private var metalDevice: MTLDevice!
    private var accelerationStructure: MTLAccelerationStructure!
    private var commandQueue: MTLCommandQueue!
    
    // Pipelines
    private var pathtracingPipeline: MTLComputePipelineState!
    
    // Buffers
    // Acceleration Structure
    private var triVertexBuffer: MTLBuffer!
    
    // Read-only Buffers
    private var sceneDataBuffer: MTLBuffer!
    private var triMaterialBuffer: MTLBuffer!
    
    private var directionalLightBuffer: MTLBuffer!
    private var pointLightBuffer: MTLBuffer!
    private var quadLightBuffer: MTLBuffer!

    // Other buffers
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
     Setup required metal objects
     */
    private func setupAccelerationStructure() -> Bool {
        
        /* SETUP acceleration Structure */
        // make triangle vertex buffer
        // Make the vertex position buffer
        guard let buffer = metalDevice.makeBuffer(bytes: scene.triVerts, length: MemoryLayout<simd_float3>.size * scene.triVerts.count, options: .storageModeShared) else {
            print("Failed to make vertexPositionBuffer!")
            return false
        }
        triVertexBuffer = buffer        

        // Now acceleration structure itself
        let accelerationStructureDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
        
        // greate geometry descriptor
        let triGeometryDescriptor = MTLAccelerationStructureTriangleGeometryDescriptor()
        triGeometryDescriptor.vertexBuffer = triVertexBuffer
        triGeometryDescriptor.triangleCount = scene.triVerts.count / 3
        
//        let sphereGeometryDescriptor = MTLAccelerationStructureBoundingBoxGeometryDescriptor()
//        sphereGeometryDescriptor.boundingBoxBuffer
        
        accelerationStructureDescriptor.geometryDescriptors = [ triGeometryDescriptor ]
        
        // Allocate space
        let sizes = metalDevice.accelerationStructureSizes(descriptor: accelerationStructureDescriptor)
        accelerationStructure = metalDevice.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
        let scratchBuffer = metalDevice.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate)!
        
        // Build the acceleration structure
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
        commandEncoder.build(accelerationStructure: accelerationStructure,
                                                descriptor: accelerationStructureDescriptor,
                                                scratchBuffer: scratchBuffer,
                                                scratchBufferOffset: 0)
        commandEncoder.endEncoding()
        commandBuffer.commit()

        return true
    }
    
    
    /**
     Helper method that sets up all required buffers. Only called once after setupScene
     */
    private func setupBuffers() -> Bool {
        let length = Int(scene.imageSize.x * scene.imageSize.y)
        
        // Initialize SceneData buffer
        let data = [scene.getSceneData()]
        if let buffer = metalDevice!.makeBuffer(bytes: data ,length: MemoryLayout<SceneData>.size, options: .storageModeShared) {
            sceneDataBuffer = buffer
        } else {
            print("Unable to initialize sceneDataBuffer!")
            return false
        }
        
        // Initialize Vertex Buffer
        if let buffer = metalDevice!.makeBuffer(bytes: scene.triVerts, length: scene.triVerts.count * MemoryLayout<simd_float3>.size, options: .storageModeShared) {
            triVertexBuffer = buffer
        } else {
            print("Unable to generate vertex buffer")
            return false
        }
        
        // Initialize Triangle Material
        if let buffer = metalDevice!.makeBuffer(bytes: scene.triMaterials, length: scene.triMaterials.count * MemoryLayout<Material>.size, options: .storageModeShared) {
            triMaterialBuffer = buffer
        } else {
            print("Unable to generate material buffer")
            return false
        }

        // Initialize Output Image data Buffer
        if let buffer = metalDevice!.makeBuffer(length: length * MemoryLayout<RGBData>.size, options: .storageModeShared) {
            outputImageBuffer = buffer
        } else {
            print("Unable to generate output buffer")
            return false
        }
        
        // Initialize lightBuffers
        if let dirBuffer = metalDevice!.makeBuffer(bytes: scene.directionalLights, length: scene.directionalLights.count * MemoryLayout<DirectionalLight>.size, options: .storageModeShared),
            let pointBuffer = metalDevice!.makeBuffer(bytes: scene.pointLights, length: scene.pointLights.count * MemoryLayout<PointLight>.size, options: .storageModeShared),
            let quadBuffer = metalDevice!.makeBuffer(bytes: scene.quadLights, length: scene.quadLights.count * MemoryLayout<Quadlight>.size, options: .storageModeShared){
            directionalLightBuffer = dirBuffer
            pointLightBuffer = pointBuffer
            quadLightBuffer = quadBuffer
        } else {
            print("Unable to generate light buffer")
            return false
        }

        
        return true
    }
    
    
    /**
     Setup the commandQueue and all the pipelines needed for rendering
     */
    private func setupPipelines() -> Bool {
        // Get default library
        guard let defaultLibrary = metalDevice?.makeDefaultLibrary() else {
            print("Unable to get defaultLibrary!")
            return false
        }
        
        // Pipeline 1: the path tracing pipeline
        guard let pathtracingFunction = defaultLibrary.makeFunction(name: "pathtracingKernel") else {
            print("Failed to fetch pathtracing kernel")
            return false
        }
        
        do {
            pathtracingPipeline = try metalDevice?.makeComputePipelineState(function: pathtracingFunction)
        } catch {
            print("Failed to create Pipelines")
            return false
        }

        
        guard let queue = metalDevice?.makeCommandQueue() else {
            print("Unable to generate command queue")
            return false
        }
        commandQueue = queue
        
        return true
    }
    
    // MARK: - Here's the main function. Everything starts here.
    
    
    /**
     The core of the rendering engine. Everything goes here.
     */
    public func render(filename sourcePath: String) {
        
        // Perform setup
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("The environment does not support Metal")
            return
        }
        metalDevice = device
        

        if !setupScene(path: sourcePath) { return }
        if !setupBuffers() { return }
        if !setupPipelines() { return }
        
//        let sceneData = scene.getSceneData()

        // Start the rendering stopwatch
        let startTime = Date.init()
        
        // Construct the acceleration structure
        if !setupAccelerationStructure() { return }
        
        // Create the command buffer needed
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Unable to generate command Buffer")
            return
        }
        
        // MARK: The main path-tracing kernel
        let mainKernelEncoder = commandBuffer.makeComputeCommandEncoder()!
        mainKernelEncoder.setComputePipelineState(pathtracingPipeline)
        mainKernelEncoder.setBuffer(sceneDataBuffer, offset: 0, index: 0)
        mainKernelEncoder.setAccelerationStructure(accelerationStructure, bufferIndex: 1)
        mainKernelEncoder.setBuffers([triVertexBuffer, triMaterialBuffer, directionalLightBuffer, pointLightBuffer, quadLightBuffer, outputImageBuffer], offsets: Array(repeating: 0, count: 6), range: 2..<8)
        
        
        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadsPerGrid = MTLSize(width: Int(scene.imageSize.x), height: Int(scene.imageSize.y), depth: 1)
        mainKernelEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        mainKernelEncoder.endEncoding()
                        
        
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
