//
//  GSObject.swift
//  
//
//  Created by v.prusakov on 6/1/22.
//

import CGravity

public class GSObject {
    let ref: UnsafeMutableRawPointer
    
    unowned let vm: GravityVirtualMachine
    
    public init(ref: UnsafeMutableRawPointer, vm: GravityVirtualMachine) {
        self.ref = ref
        self.vm = vm
    }
    
    public init(_ object: UnsafeMutablePointer<gravity_object_t>, vm: GravityVirtualMachine) {
        self.vm = vm
        fatalError("")
//        self.ref = object
    }
}
