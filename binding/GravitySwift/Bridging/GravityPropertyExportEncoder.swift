//
//  GravityPropertyExportEncoder.swift
//  
//
//  Created by v.prusakov on 6/4/22.
//

import Foundation
import CGravity

public protocol GravityExportClassEncoderContainer {
    func bind(_ method: MethodDescriptor)
}

public final class _GravityExportClassEncoderContainer<T: GSExportable>: GravityExportClassEncoderContainer {
    
    private unowned let descriptor: GravityBridgeClassDescriptor
    
    init(descriptor: GravityBridgeClassDescriptor, type: T.Type) {
        self.descriptor = descriptor
    }
    
    public func bind(_ method: MethodDescriptor) {
        let methodPtr = Unmanaged.passRetained(method).toOpaque()
        let clazz = self.descriptor.gClass
        let closure = gravity_closure_new(nil, gravity_function_new_bridged(nil, nil, methodPtr))!
        let closureValue = gravity_value_from_object(closure)
        
        if method.isConstrucor {
            let narg = method.argsCount > 0 ? "\(method.argsCount)" : ""
            let name = CLASS_INTERNAL_INIT_NAME + narg
            
//            CLASS_INTERNAL_INIT_NAME = "$init"
//            GRAVITY_INTERNAL_EXEC_NAME = "exec"
            name.withCString { ptr in
                gravity_class_bind(clazz, ptr, closureValue)
            }
            
        } else {
            method.name.withCString { ptr in
                gravity_class_bind(clazz, ptr, closureValue)
            }
        }
        
        self.descriptor.addMethod(method)
    }
    
}

//private func bridgeExecConstructor(vm: OpaquePointer!, args: UnsafeMutablePointer<gravity_value_t>!, nargs: UInt16, rIndex: UInt32) -> Bool {
//    
//    guard let virtualMachine = GravityVirtualMachine.getVM(vm), let clazz = args[0].p else {
//        return false
//    }
//    
//    let classIdentifier = String(cString: clazz.pointee.identifier)
//    
//    guard let desc = virtualMachine.getClassDescriptor(for: classIdentifier) else {
//        print("Can't find class descriptor for identifier - \(classIdentifier).")
//        return false
//    }
//    
//    guard let method = desc.methodDescriptions.first(where: { $0.isConstrucor && $0.argsCount == nargs - 1 }) else {
//        print("Can't find method constructor")
//        
//        return false
//    }
//    
//    let instance = gravity_instance_new(vm, clazz)
//    
//    // first index always contains class information
//    let args: [GSValue] = (1..<nargs).map { index in
//        let value = args[Int(index)]
//        return GSValue(value: value, vm: virtualMachine)
//    }
//    
//    var value = method.callStatic(with: args)
//    gravity_instance_setxdata(instance, &value)
//    
//    return gravity_return_value(vm, gravity_value_from_object(instance), Int32(rIndex))
//}
//
//private func bridgeExec(vm: OpaquePointer!, args: UnsafeMutablePointer<gravity_value_t>!, nargs: UInt16, rIndex: UInt32) -> Bool {
//    
//    guard let virtualMachine = GravityVirtualMachine.getVM(vm) else {
//        return gravity_return_error(vm, Int32(rIndex), "Cannot find virtual machine.")
//    }
//    
//    let arguments: [GSValue] = (0..<nargs).map { index in
//        let value = args[Int(index)]
//        return GSValue(object: value, in: virtualMachine)
//    }
//    
//    guard let instance = args[0].p, instance.pointee.xdata != nil else {
//        return gravity_return_error(vm, Int32(rIndex), "Cannot find instance")
//    }
//    
//    guard let methodNamePtr = args[1].p else {
//        return gravity_return_error(vm, Int32(rIndex), "Cannot find method name")
//    }
//    
//    let methodNameValue = GSValue(object: methodNamePtr, in: virtualMachine)
//    
//    let classIdentifier = String(cString: instance.pointee.identifier)
//    let object = GSValue(object: instance, in: virtualMachine)
//    let methodName = methodNameValue.toString
//    
//    guard let desc = virtualMachine.getClassDescriptor(for: classIdentifier) else {
//        return gravity_return_error(vm, Int32(rIndex), "Can't find class descriptor for identifier - \(classIdentifier).")
//    }
//    
//    // first two indecies always contains instance information and method name
//    let args: [GSValue] = (2..<nargs).map { index in
//        let value = args[Int(index)]
//        return GSValue(value: value, vm: virtualMachine)
//    }
//    
//    guard let method = desc.methodDescriptions.first(where: { $0.name == methodName }) else {
//        return gravity_return_error(vm, Int32(rIndex), "Can't find method constructor")
//    }
//    
//    virtualMachine.setGCEnabled(false)
//    defer { virtualMachine.setGCEnabled(true) }
//    
//    let result = method.call(in: object, with: args)
//    
//    if result is Void {
//        return gravity_return_no_value()
//    } else {
//        let returnValue = GSValue(object: result, in: virtualMachine)
//        return gravity_return_value(vm, returnValue.value, Int32(rIndex))
//    }
//}
