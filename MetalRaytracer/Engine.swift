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
    private var convertColorPipeline: MTLComputePipelineState!
    
    private var intersectionFunctionTable: MTLIntersectionFunctionTable!

    // Buffers
    // Acceleration Structure
    private var triVertexBuffer: MTLBuffer!
    private var sphereBBoxBuffer: MTLBuffer!
    private var instBUffer: MTLBuffer!
    
    // Read-only Buffers
    private var uniformBuffer: MTLBuffer!
    private var triMaterialBuffer: MTLBuffer!
    private var sphereBuffer: MTLBuffer!
    
    private var directionalLightBuffer: MTLBuffer!
    private var pointLightBuffer: MTLBuffer!
    private var quadLightBuffer: MTLBuffer!

    // Other buffers
    private var outputImageBuffer: MTLBuffer!
    private var renderResultBuffer: MTLBuffer!
    
    // For multiple sample at once
    private let concurrentFrameCount = 3
    private var semaphore: DispatchSemaphore
    private var currentUniformIndex = -1
    private var currentSampleIndex: Int32 = -1
    private let uniformStride = MemoryLayout<FrameData>.stride
    private var finishedSampleCount = 0

    
    init() {
        semaphore = DispatchSemaphore(value: concurrentFrameCount)
    }
    
    
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
    
    
    private func buildAccelerationStructure(descriptor: MTLAccelerationStructureDescriptor, commandQueue: MTLCommandQueue) -> MTLAccelerationStructure {
        // Allocate space
        let sizes = metalDevice.accelerationStructureSizes(descriptor: descriptor)
        let thisAccelerationStructure = metalDevice.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
        let scratchBuffer = metalDevice.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate)!
        
        // Build the acceleration structure
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
        commandEncoder.build(accelerationStructure: thisAccelerationStructure,
                                                descriptor: descriptor,
                                                scratchBuffer: scratchBuffer,
                                                scratchBufferOffset: 0)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        return thisAccelerationStructure

    }
    
    
    /**
     Setup required metal objects
     */
    private func setupAccelerationStructure() -> Bool {
                
        /* SETUP acceleration Structure */
        // acceleration structure itself
        let instanceAccelStructureDescriptor = MTLInstanceAccelerationStructureDescriptor()
        
        // create the triangle acceleration structure
        let triGeometryDescriptor = MTLAccelerationStructureTriangleGeometryDescriptor()
        triGeometryDescriptor.vertexBuffer = triVertexBuffer
        triGeometryDescriptor.triangleCount = scene.triVerts.count / 3
        triGeometryDescriptor.vertexStride = MemoryLayout<simd_float3>.size
        triGeometryDescriptor.intersectionFunctionTableOffset = 0
        
        let triAccelStructureDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
        triAccelStructureDescriptor.geometryDescriptors = [triGeometryDescriptor]
        let triAccelerationStructure = buildAccelerationStructure(descriptor: triAccelStructureDescriptor, commandQueue: commandQueue)
        
        
        // Create the sphere acceleration structure
        let sphereGeometryDescriptor = MTLAccelerationStructureBoundingBoxGeometryDescriptor()
        sphereGeometryDescriptor.boundingBoxBuffer = sphereBBoxBuffer
        sphereGeometryDescriptor.boundingBoxBufferOffset = 0
        sphereGeometryDescriptor.boundingBoxCount = scene.sphereBoundingBoxes.count
        sphereGeometryDescriptor.boundingBoxStride = MemoryLayout<BoundingBox>.stride
        sphereGeometryDescriptor.intersectionFunctionTableOffset = 1

        let sphereAccelStructureDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
        sphereAccelStructureDescriptor.geometryDescriptors = [sphereGeometryDescriptor]
        let sphereAccelerationStructure = buildAccelerationStructure(descriptor: sphereAccelStructureDescriptor, commandQueue: commandQueue)
        
        
        // Create the instance acceleration Structure
        var identityMatrix = MTLPackedFloat4x3()
        identityMatrix.columns.0.x = 1.0
        identityMatrix.columns.1.y = 1.0
        identityMatrix.columns.2.z = 1.0
        
        var triInstanceDescriptor = MTLAccelerationStructureInstanceDescriptor()
        triInstanceDescriptor.accelerationStructureIndex = 0
        triInstanceDescriptor.intersectionFunctionTableOffset = 0
        triInstanceDescriptor.transformationMatrix = identityMatrix
        triInstanceDescriptor.mask = UInt32.max

        var sphereInstanceDescriptor = MTLAccelerationStructureInstanceDescriptor()
        sphereInstanceDescriptor.accelerationStructureIndex = 1
        sphereInstanceDescriptor.intersectionFunctionTableOffset = 0
        sphereInstanceDescriptor.transformationMatrix = identityMatrix
        sphereInstanceDescriptor.mask = UInt32.max
        
        instanceAccelStructureDescriptor.instanceCount = 2
        let instances = [triInstanceDescriptor, sphereInstanceDescriptor]
        let instanceDescriptorBuffer = metalDevice.makeBuffer(bytes: instances, length: MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.size * instances.count, options: .storageModeManaged)
        instanceAccelStructureDescriptor.instanceDescriptorBuffer = instanceDescriptorBuffer
        instanceAccelStructureDescriptor.instancedAccelerationStructures = [triAccelerationStructure, sphereAccelerationStructure]
        accelerationStructure = buildAccelerationStructure(descriptor: instanceAccelStructureDescriptor, commandQueue: commandQueue)
        
        return true
    }
    
    
    /**
     Helper method that sets up all required buffers. Only called once after setupScene
     */
    private func setupBuffers() -> Bool {
        let length = Int(scene.imageSize.x * scene.imageSize.y)
        
        var failed = false
        
        // Initialize SceneData buffer
        let initFrameData = scene.getInitFrameData()
        let data = Array(repeating: initFrameData, count: concurrentFrameCount)
        if let buffer = metalDevice!.makeBuffer(bytes: data ,length: MemoryLayout<FrameData>.size * concurrentFrameCount, options: .storageModeShared) {
            uniformBuffer = buffer
        } else { failed = true }
        
        // Initialize Vertex Buffer
        if let buffer = metalDevice!.makeBuffer(bytes: scene.triVerts, length: scene.triVerts.count * MemoryLayout<simd_float3>.size, options: .storageModeShared) {
            triVertexBuffer = buffer
        } else { failed = true }
        
        // Initialize Triangle Material
        if let buffer = metalDevice!.makeBuffer(bytes: scene.triMaterials, length: scene.triMaterials.count * MemoryLayout<Material>.size, options: .storageModeShared) {
            triMaterialBuffer = buffer
        } else { failed = true }
        
        // Initialize Sphere Buffer
        if let buffer = metalDevice!.makeBuffer(bytes: scene.spheres, length: scene.spheres.count * MemoryLayout<Sphere>.size, options: .storageModeShared) {
            sphereBuffer = buffer
        } else { failed = true }
        
        // Initialize Instance Buffer & data
        
        // Initialize Sphere BBox buffer
        if let buffer = metalDevice!.makeBuffer(bytes: scene.sphereBoundingBoxes, length: scene.sphereBoundingBoxes.count * MemoryLayout<BoundingBox>.size, options: .storageModeShared) {
            sphereBBoxBuffer = buffer
        } else { failed = true }
        

        // Initialize Output Image data Buffer
        if let buffer = metalDevice!.makeBuffer(length: length * MemoryLayout<RGBData>.size, options: .storageModeShared) {
            outputImageBuffer = buffer
        } else { failed = true }
        
        // Initialize Rendering reuslt buffer
        if let buffer = metalDevice!.makeBuffer(length: length * MemoryLayout<simd_float3>.size, options: .storageModeShared) {
            renderResultBuffer = buffer
        } else { failed = true }

        // Initialize lightBuffers
        if let dirBuffer = metalDevice!.makeBuffer(bytes: scene.directionalLights, length: scene.directionalLights.count * MemoryLayout<DirectionalLight>.size, options: .storageModeShared),
            let pointBuffer = metalDevice!.makeBuffer(bytes: scene.pointLights, length: scene.pointLights.count * MemoryLayout<PointLight>.size, options: .storageModeShared),
            let quadBuffer = metalDevice!.makeBuffer(bytes: scene.quadLights, length: scene.quadLights.count * MemoryLayout<Quadlight>.size, options: .storageModeShared){
            directionalLightBuffer = dirBuffer
            pointLightBuffer = pointBuffer
            quadLightBuffer = quadBuffer
        } else { failed = true }
        
        if (failed) {
            print("ERROR: Buffer initialization failed!")
        }
        
        return !failed
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
        
        guard let convertFunction = defaultLibrary.makeFunction(name: "convertToColorSpace") else {
            print("Failed to fetch convert color space kernel")
            return false;
        }
        
        
        // Get the intersection functions
        let sphereIntersectionFunction = defaultLibrary.makeFunction(name: "sphereIntersectionFunction")!
        let linkedFunctions = MTLLinkedFunctions()
        linkedFunctions.functions = [sphereIntersectionFunction]
        
        // Line the intersection to the descriptor
        let raytracingPipelineDescriptor = MTLComputePipelineDescriptor()
        raytracingPipelineDescriptor.linkedFunctions = linkedFunctions
        raytracingPipelineDescriptor.computeFunction = pathtracingFunction
        
        
        do {
            pathtracingPipeline = try metalDevice!.makeComputePipelineState(descriptor: raytracingPipelineDescriptor, options: [], reflection: nil)
            convertColorPipeline = try metalDevice.makeComputePipelineState(function: convertFunction)
        } catch {
            print("Failed to create Pipelines")
            return false
        }
        
        /* Setup intersection function table */
        let intersectionFunctionTableDescriptor = MTLIntersectionFunctionTableDescriptor()
        intersectionFunctionTableDescriptor.functionCount = 2
        
        // The only sphere intersection function
        intersectionFunctionTable = pathtracingPipeline.makeIntersectionFunctionTable(descriptor: intersectionFunctionTableDescriptor)!
        let functionHandle = pathtracingPipeline.functionHandle(function: sphereIntersectionFunction)
        intersectionFunctionTable.setOpaqueTriangleIntersectionFunction(signature: .instancing, index: 0)
        intersectionFunctionTable.setFunction(functionHandle, index: 1)
        intersectionFunctionTable.setBuffer(sphereBuffer, offset: 0, index: 0)

        
        guard let queue = metalDevice?.makeCommandQueue() else {
            print("Unable to generate command queue")
            return false
        }
        commandQueue = queue
        
        return true
    }
    
    
    
    private func updateUniform() {
        
        semaphore.wait()
        
        currentSampleIndex += 1
        currentUniformIndex = (currentUniformIndex + 1) % concurrentFrameCount
        
        let memoryOffset = currentUniformIndex * uniformStride
        
        var newUniform = uniformBuffer.contents().load(fromByteOffset: memoryOffset, as: FrameData.self)
        newUniform.sampleIndex = currentSampleIndex
        uniformBuffer.contents().storeBytes(of: newUniform, toByteOffset: memoryOffset, as: FrameData.self)
        
    }
    
    
    
    // MARK: - Here's the main function. Everything starts here.
    /**
     The core of the rendering engine. Everything goes here.
     */
    public func render(filename sourcePath: String) {
        
        // Perform setup
        let possibleDevices = MTLCopyAllDevices()
        var assignedFlag = false
        for device in possibleDevices {
            if device.supportsRaytracing {
                metalDevice = device
                assignedFlag = true
            }
        }
        
        if assignedFlag == false {
            print("Error! Raytracing Not supported")
            return
        }
        
        print("Graphics card:\t\t \(metalDevice.name)")        

        if !setupScene(path: sourcePath) { return }
        if !setupBuffers() { return }
        if !setupPipelines() { return }

        // Start the rendering stopwatch
        let startTime = Date.init()
        
        // Construct the acceleration structure
        if !setupAccelerationStructure() { return }
        
        
        // Commit commands for each sample
        var threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        var threadsPerGrid = MTLSize(width: Int(scene.imageSize.x), height: Int(scene.imageSize.y), depth: 1)

        for _ in 0..<scene.spp {
            // Create the command buffer needed
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Unable to generate command Buffer")
                return
            }
            
            updateUniform()
            
            // MARK: The main path-tracing kernel
            let mainKernelEncoder = commandBuffer.makeComputeCommandEncoder()!
            mainKernelEncoder.setComputePipelineState(pathtracingPipeline)
            mainKernelEncoder.setBuffer(uniformBuffer, offset: currentUniformIndex * uniformStride, index: 0)
            mainKernelEncoder.setAccelerationStructure(accelerationStructure, bufferIndex: 1)
            mainKernelEncoder.setBuffers([triVertexBuffer, triMaterialBuffer, sphereBuffer, directionalLightBuffer, pointLightBuffer, quadLightBuffer, renderResultBuffer], offsets: Array(repeating: 0, count: 7), range: 2..<9)
            mainKernelEncoder.setIntersectionFunctionTable(intersectionFunctionTable, bufferIndex: 9)
            
            
            mainKernelEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            mainKernelEncoder.endEncoding()
            
            
            commandBuffer.addCompletedHandler({cb in
                self.semaphore.signal()
                self.finishedSampleCount += 1
                if (self.finishedSampleCount % 10 == 0) {
                    print(self.finishedSampleCount)
                }
            })
            
            commandBuffer.commit()

        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Unable to generate command Buffer")
            return
        }

        // MARK: Convert the output of the rendering
        let convertKernelEncoder = commandBuffer.makeComputeCommandEncoder()!
        convertKernelEncoder.setComputePipelineState(convertColorPipeline)
        convertKernelEncoder.setBuffers([uniformBuffer, renderResultBuffer, outputImageBuffer], offsets: [0, 0, 0], range: 0..<3)
        
        threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        threadsPerGrid = MTLSize(width: Int(scene.imageSize.x), height: Int(scene.imageSize.y), depth: 1)
        convertKernelEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        convertKernelEncoder.endEncoding()
        
        commandBuffer.commit()
        print("All Command Comitted")
        
        commandBuffer.waitUntilCompleted()
        print("Command completed")
        
        // Render finished
        let formatted = String(format: "Rendering time:\t\t %.5fs", Date.init().timeIntervalSince(startTime))
        print(formatted)
        
        let film = Film(size: scene.imageSize, outputFileName: scene.outputName)
        let pointer = outputImageBuffer.contents().bindMemory(to: RGBData.self, capacity: scene.pixelCount)
        let imageData = Array(UnsafeBufferPointer(start: pointer, count: scene.pixelCount))
        film.setImageData(data: imageData)
        if !film.saveImage() {
            print("Image save failed")
        } else {
            print("Image saved as:\t\t \(scene.outputName)")
        }
        
        
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
