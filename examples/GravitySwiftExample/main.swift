//
//  main.swift
//  
//
//  Created by v.prusakov on 6/1/22.
//

import Gravity
import CGravity
import Foundation

class GVMDelegateImpl: GravityVirtualMachineDelegate {
    func virtualMachineDidReciveLog(_ virtualMachine: GravityVirtualMachine, message: String, data: UnsafeMutableRawPointer?) {
        print(message)
    }
    
    func virtualMachineDidClearLog(_ virtualMachine: GravityVirtualMachine, data: UnsafeMutableRawPointer?) {
        print("claer")
    }
    
    func virtualMachineBridgeEquals(_ virtualMachine: GravityVirtualMachine, lhsValue: GSValue, rhsValue: GSValue) -> Bool {
        return lhsValue == rhsValue
    }
    
    func virtalMachine(_ virtualMachine: GravityVirtualMachine, didRequestCloneFor object: GSValue) -> GSValue {
        return object
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didExecuteIn ctx: GSValue, arguments: [GSValue], argumentsCount: Int16, vIndex: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
        return false
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didSetValue value: GSValue, in target: GSValue, forKey key: String) -> Bool {
        return false
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didGetValueFrom target: GSValue, forKey: String, vIndex: UInt32) -> Bool {
        return false
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didSetUndefValue value: GSValue, in target: GSValue, forKey key: String) -> Bool {
        return false
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didGetUndefValueFrom target: GSValue, forKey: String, vIndex: UInt32) -> Bool {
        return false
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestStringWith length: UInt32, data: UnsafeMutableRawPointer?) -> String {
        return ""
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestFree object: GSValue) {
        return
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestSizeFor object: GSValue) -> UInt32 {
        return 1
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didInitObjectIn ctx: GSValue, instance: UnsafeMutablePointer<gravity_instance_t>?, arguments: [GSValue], argumentsCount: Int16, data: UnsafeMutableRawPointer?) -> Bool {
        return false
    }
    
  
}

let vmDelegate = GVMDelegateImpl()

let settings = GravityVirtualMachine.Settings(
    reportNullErrors: true,
    disableGarbageCollectorCheck: false,
    xdata: nil
)

let sourceCodePath = Bundle.module.path(forResource: "main", ofType: "gravity")!
let sourceCode = try String(contentsOfFile: sourceCodePath)

let vm = GravityVirtualMachine(settings: settings, delegate: vmDelegate)

class SwiftObject: GSExportable {
    init() {
        print("SwiftObject Init")
    }
    
    var text: String = "kek"
    
    var random: String {
        return "Random string"
    }
    
    func printKek() {
        print(#function, text)
    }
    
    func debug(_ value: Int) -> String {
        return "Debug value is \(value)"
    }
    
    // MARK: GSExportable
    
    static func export(in encoder: GravityExportEncoder) throws {
        let container = try encoder.makeContainer(for: SwiftObject.self, named: "SwiftObject")
        container.bind(.constructor(SwiftObject.init))
        container.bind(.method(SwiftObject.debug(_:), named: "debug"))
        container.bind(.method(SwiftObject.printKek, named: "printKek"))
        
        container.bind(.property(\SwiftObject.text, named: "text"))
        container.bind(.property(\SwiftObject.random, named: "random"))
    }
}


let compiler = GravityCompiler()
let binary = compiler.compile(source: sourceCode)

compiler.transferMem(to: vm)

vm.bindClass(with: SwiftObject.self)

let res = vm.executeMain(for: binary)

