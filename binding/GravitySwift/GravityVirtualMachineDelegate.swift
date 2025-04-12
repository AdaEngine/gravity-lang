//
//  GravityVirtualMachineDelegate.swift
//  
//
//  Created by v.prusakov on 6/4/22.
//

import Foundation

public protocol GravityVirtualMachineDelegate: AnyObject {
    
    func virtualMachineDidReciveLog(_ virtualMachine: GravityVirtualMachine, message: String, data: UnsafeMutableRawPointer?)
    func virtualMachineDidClearLog(_ virtualMachine: GravityVirtualMachine, data: UnsafeMutableRawPointer?)
    
    func virtualMachineBridgeEquals(_ virtualMachine: GravityVirtualMachine, lhsValue: GSValue, rhsValue: GSValue) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didExecuteIn ctx: GSValue,
        arguments: [GSValue],
        argumentsCount: Int16,
        vIndex: UInt32,
        data: UnsafeMutableRawPointer?
    ) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didSetValue value: GSValue,
        in target: GSValue,
        forKey key: String
    ) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didGetValueFrom target: GSValue,
        forKey key: String
    ) throws -> GSValue?
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        xdata: UnsafeMutableRawPointer?,
        didSetUndefValue value: GSValue,
        in target: GSValue,
        forKey key: String
    ) -> Bool
    
    /// - Parameter virtualMachine: Current virtual machine
    /// - Parameter xdata: Instance object if exists
    /// - Parameter didGetUndefValueFrom: target
    /// - Parameter forKey: identifier key
    /// - Parameter vIndex: index in register
    /// - Returns: true if you find a value, or false if not.
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        xdata: UnsafeMutableRawPointer?,
        didGetUndefValueFrom target: GSValue,
        forKey key: String
    ) throws -> GSValue?
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestStringWith length: UInt32, data: UnsafeMutableRawPointer?) -> String
}

// MARK: Memory managment

public protocol GravityMemoryControlVMDelegate: GravityVirtualMachineDelegate {
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestFree object: GSValue)
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestSizeFor object: GSValue) -> UInt32
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didInitObjectIn ctx: GSValue,
        instance:  UnsafeMutablePointer<gravity_instance_t>?,
        arguments: [GSValue],
        argumentsCount: Int16,
        data: UnsafeMutableRawPointer?
    ) -> Bool
    
    func virtalMachine(_ virtualMachine: GravityVirtualMachine, didRequestCloneFor object: GSValue) -> GSValue
}
