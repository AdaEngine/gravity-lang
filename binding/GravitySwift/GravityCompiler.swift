//
//  GravityCompiler.swift
//  
//
//  Created by v.prusakov on 6/2/22.
//

//
//  File.swift
//
//
//  Created by v.prusakov on 6/4/22.
//

import CGravity

public class GravityCompiler {
    
    internal private(set) var compiler: OpaquePointer
    
    public init() {
        self.compiler = gravity_compiler_create(nil)
    }
    
    deinit {
        gravity_compiler_free(self.compiler)
    }
    
    public func compile(source: String, debug: Bool = true) -> UnsafeMutablePointer<gravity_closure_t>! {
        source.withCString { sourcePtr in
            return gravity_compiler_run(
                self.compiler,
                sourcePtr,
                source.count,
                0, // fileId
                true, // is_static
                debug // add_debug
            )
        }
    }
    
    public func transferMem(to vm: GravityVirtualMachine) {
        gravity_compiler_transfer(self.compiler, vm.vmPtr)
    }
}
