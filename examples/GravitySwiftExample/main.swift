//
//  main.swift
//  
//
//  Created by v.prusakov on 6/1/22.
//

import Gravity
import CGravity

let sourceCode = """
//extern var SwiftObject
//extern var swiftObj

class SomeClass {

    static var staticText = "Some Text"
    var text: String = "some text"
    
    func init() {
        System.print("init")
    }

    func printHello() {
        System.print("Hello")
    }

}

var someClass = SomeClass()
var someClassStatic = SomeClass

func main() {
    someClass.printHello()
//    var swiftObj = SwiftObject()
//    swiftObj.printKek()
}

"""

class GVMDelegateImpl: GravityVirtualMachineDelegate {
    func virtualMachineDidReciveLog(_ virtualMachine: GravityVirtualMachine, message: String, data: UnsafeMutableRawPointer?) {
        print(message)
    }
    
    func virtualMachineDidClearLog(_ virtualMachine: GravityVirtualMachine, data: UnsafeMutableRawPointer?) {
        print("clear")
    }
    
    func virtualMachineBridgeEquals(_ virtualMachine: GravityVirtualMachine, lhsObject: GSObject, rhsObject: GSObject) -> Bool {
        return true
    }
    
    func virtalMachine(_ virtualMachine: GravityVirtualMachine, didRequestCloneFor object: GSObject) -> GSObject {
        return object
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine) {
        
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didExecuteIn ctx: gravity_value_t, arguments: [gravity_value_t], argumentsCount: Int16, vIndex: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
        return true
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didSetValue value: gravity_value_t, in target: gravity_value_t, forKey key: String) -> Bool {
        return true
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didGetValueFrom target: gravity_value_t, forKey: String, vIndex: UInt32) -> Bool {
        return true
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didSetUndefValue value: gravity_value_t, in target: gravity_value_t, forKey key: String) -> Bool {
        return true
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didGetUndefValueFrom target: gravity_value_t, forKey: String, vIndex: UInt32) -> Bool {
        return true
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestStringWith length: UInt32, data: UnsafeMutableRawPointer?) -> String {
        return "true"
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestFree object: gravity_object_t) {
        
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestSizeFor object: gravity_object_t) -> UInt32 {
        return 1
    }
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didInitObjectIn ctx: gravity_value_t, instance: UnsafeMutablePointer<gravity_instance_t>?, arguments: [gravity_value_t], argumentsCount: Int16, data: UnsafeMutableRawPointer?) -> Bool {
        return true
    }
    
    
}

let vmDelegate = GVMDelegateImpl()

let settings = GravityVirtualMachine.Settings(
    reportNullErrors: true,
    disableGarbageCollectorCheck: false,
    xdata: nil
)

let vm = GravityVirtualMachine(settings: settings, delegate: vmDelegate)

let compiler = GravityCompiler()
let binary = compiler.compile(source: sourceCode)

compiler.transferMem(to: vm)

let swiftObject = SwiftObject()

//vm.setValue(swiftObject, forKey: "swiftObj")

//let obj = vm["swiftObj"]
//print(obj.toString)



let result = vm.executeMain(for: binary)

let s = vm["someClass"]

let stat = vm["someClassStatic"]

//print(s.hasMethod(named: "printHello"))
print(stat.hasProperty(named: "staticText"))

print("result", result)


class SwiftObject: GravityExportable {
    static func export(in encoder: GravityExportEncoder) throws {
        let container = try encoder.registerClassWithConstructor(named: "SwiftObject", constructor: { _ in
            SwiftObject()
        })
        var printKek = SwiftObject.printKek
        container.bindMethod(named: "printKek", callback: &printKek)
    }
    
    var text: String = "kek"
    
    func printKek() {
        print(text)
    }
}
