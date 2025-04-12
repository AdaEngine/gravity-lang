//
//  main.swift
//  
//
//  Created by v.prusakov on 6/1/22.
//

import Gravity
import Foundation

class GVMDelegateImpl: GravityVirtualMachineDelegate {
    func virtualMachine(_ virtualMachine: Gravity.GravityVirtualMachine, didGetValueFrom target: Gravity.GSValue, forKey: String) throws -> Gravity.GSValue? {
        return nil
    }
    
    func virtualMachine(_ virtualMachine: Gravity.GravityVirtualMachine, xdata: UnsafeMutableRawPointer?, didSetUndefValue value: Gravity.GSValue, in target: Gravity.GSValue, forKey key: String) -> Bool {
        return false
    }
    
    func virtualMachine(
        _ virtualMachine: Gravity.GravityVirtualMachine,
        xdata: UnsafeMutableRawPointer?,
        didGetUndefValueFrom target: Gravity.GSValue,
        forKey key: String
    ) throws -> Gravity.GSValue? {
        return nil
    }
    
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

@GSExportable
class SwiftObject: @unchecked Sendable {
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
}

let compiler = GravityCompiler()
let binary = compiler.compile(source: sourceCode)

compiler.transferMem(to: vm)

try! vm.bindClass(with: SwiftObject.self)
vm.setValue(SwiftObject(), forKey: "sw")

let res = vm.executeMain(for: binary)

