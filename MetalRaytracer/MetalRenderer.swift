//
//  MetalRenderer.swift
//  MetalRenderer
//
//  Created by Xuezheng Wang on 10/5/21.
//  Copyright © 2021 Xuezheng Wang. All rights reserved.
//

class MetalRenderer {
    func run() {
        let inputFileName = CommandLine.arguments[1]
        let engine = Engine()
        engine.render(filename: inputFileName)
    }
}
