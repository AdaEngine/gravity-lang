//
//  GravityCompiler.swift
//  
//
//  Created by v.prusakov on 6/2/22.
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
    
    public func compile(source: String) -> UnsafeMutablePointer<gravity_closure_t>! {
        return gravity_compiler_run(
            self.compiler,
            source.toPointer(),
            source.count,
            0, // fileId
            true, // is_static
            true // add_debug
        )
    }
    
    public func transferMem(to vm: GravityVirtualMachine) {
        gravity_compiler_transfer(self.compiler, vm.vmPtr)
    }
}

public final class GravityPropertyExportEncoder<T: GravityExportable> {
    
    var context: GravityExportContext<T>
    
    init(context: GravityExportContext<T>) {
        self.context = context
    }
    
    func bindMutableProperty(named: String, get: () -> GSValue, set: (GSValue) -> Void) {
        
//        var getClosure = { (vm: OpaquePointer, value: UnsafeMutablePointer<gravity_value_t>? , nargs: UInt16, rindex: UInt32) -> Bool in
//            let value = get()
//            return false
//        }
//        
//        var setClosure = { (vm: OpaquePointer, value: UnsafeMutablePointer<gravity_value_t>? , nargs: UInt16, rindex: UInt32) -> Bool in
//            let newValue = GSValue(value: value!.pointee, vm: GravityVirtualMachine.getVM(vm)!)
//            set(newValue)
//            
//            return true
//        }
//        
//        let getGClosure = new_function(&getClosure)
//        let setGClosure = new_function(&setClosure)
//        
//        let computedProp = computed_property_create(context.vm.virtualMachine, getGClosure!, setGClosure!)
//        
//        gravity_class_bind(
//            context.gClass,
//            named.toPointer(),
//            gravity_value_from_object(computedProp)
//        )
    }
    
    public func bindMethod(named: String, callback: UnsafeMutableRawPointer) {
        
        var closure = { (vm: OpaquePointer, value: UnsafeMutablePointer<gravity_value_t>? , nargs: UInt16, rindex: UInt32) -> Bool in
            
//            callback.load(as: MethodCallback<T>.self)(<#T##self: GravityExportable##GravityExportable#>)
            
            return true
        }

        let value = new_function(&closure)

        gravity_class_bind(
            context.gClass,
            named.toPointer(),
            gravity_value_from_object(value)
        )
    }
}

public final class GravityExportEncoder {

    unowned let vm: GravityVirtualMachine
    
    init(vm: GravityVirtualMachine) {
        self.vm = vm
    }
    
    public func registerClassWithConstructor<T: GravityExportable>(named: String, constructor: @escaping (GSValue) -> T) throws -> GravityPropertyExportEncoder<T> {
        let clazz = gravity_class_new_pair(self.vm.vmPtr, named.toPointer(), nil, 0, 0)!
        let context = GravityExportContext(
            vm: self.vm,
            gClass: clazz,
            initClosure: constructor
        )
        
//        gravity_value_from_object(UnsafeMutableRawPointer!)
        
        self.vm.setValue(clazz, forKey: named)
        
        return GravityPropertyExportEncoder(context: context)
    }
}

//public protocol GravityExportEncoder {
//    func registerClassWithConstructor<T: GravityExportable>(named: String, constructor: (GSValue) -> T) throws -> GravityPropertyExportEncoder<T>
//}

class GravityExportContext<T> {
    unowned let vm: GravityVirtualMachine
    let gClass: UnsafeMutablePointer<gravity_class_t>!
    var initClosure: (GSValue) -> T
    
    internal init(vm: GravityVirtualMachine, gClass: UnsafeMutablePointer<gravity_class_t>?, instance: T? = nil, initClosure: @escaping (GSValue) -> T) {
        self.vm = vm
        self.gClass = gClass
        self.initClosure = initClosure
    }
}

public protocol GravityExportable {
    static func export(in encoder: GravityExportEncoder) throws
}
