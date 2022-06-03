//
//  GSValue.swift
//  
//
//  Created by v.prusakov on 6/2/22.
//

import CGravity

/// Gravity Script Value

@dynamicCallable
public class GSValue {
    
    internal private(set) var value: gravity_value_t
    unowned let vm: GravityVirtualMachine
    
    public init(value: gravity_value_t, vm: GravityVirtualMachine) {
        self.value = value
        self.vm = vm
    }
}

public extension GSValue {
    convenience init(string: String, in vm: GravityVirtualMachine) {
        let mutStr = UnsafeMutablePointer<CChar>.init(mutating: string.toPointer())
        
        let object = gravity_string_new(
            vm.vmPtr,
            mutStr,
            UInt32(string.count),
            UInt32(string.count)
        )
        let value = gravity_value_from_object(object)
        self.init(value: value, vm: vm)
    }
    
    convenience init(range: ClosedRange<Int>, in vm: GravityVirtualMachine) {
        let object = gravity_range_new(vm.vmPtr, Int64(range.lowerBound), Int64(range.upperBound), true)
        let value = gravity_value_from_object(object)
        self.init(value: value, vm: vm)
    }
    
    convenience init(range: Range<Int>, in vm: GravityVirtualMachine) {
        let object = gravity_range_new(vm.vmPtr, Int64(range.lowerBound), Int64(range.upperBound), false)
        let value = gravity_value_from_object(object)
        self.init(value: value, vm: vm)
    }
    
    convenience init(double: Double, in vm: GravityVirtualMachine) {
        let value = gravity_value_from_float(double)
        self.init(value: value, vm: vm)
    }
    
    convenience init(integer: Int, in vm: GravityVirtualMachine) {
        let value = gravity_value_from_int(gravity_int_t(integer))
        self.init(value: value, vm: vm)
    }
    
    convenience init(boolean: Bool, in vm: GravityVirtualMachine) {
        let value = gravity_value_from_bool(boolean)
        self.init(value: value, vm: vm)
    }
    
    // Not create instance with exportable
    convenience init<T>(object: T, in vm: GravityVirtualMachine) {
        if let string = object as? String {
            self.init(string: string, in: vm)
        } else if let int = object as? Int {
            self.init(integer: int, in: vm)
        } else if let double = object as? Double {
            self.init(double: double, in: vm)
        } else if let bool = object as? Bool {
            self.init(boolean: bool, in: vm)
        } else if let exportType = object as? AnyClass {
            fatalError()
        } else {
            
            var instance = object
            if let obj = GSInstance(for: &instance, in: vm) {
                vm.setInstance(obj)
                let value = gravity_value_from_object(obj.instance)
                self.init(value: value, vm: vm)
                return
            }
            
            self.init(undefinedIn: vm)
        }
    }
    
    convenience init(newArrayIn vm: GravityVirtualMachine, length: Int = 1) {
        let list = gravity_list_new(vm.vmPtr, UInt32(length))
        let value = gravity_value_from_object(list)
        self.init(value: value, vm: vm)
    }
    
    convenience init(newMapIn vm: GravityVirtualMachine, length: Int = 1) {
        let list = gravity_map_new(vm.vmPtr, UInt32(length))
        let value = gravity_value_from_object(list)
        self.init(value: value, vm: vm)
    }
    
    convenience init(nullIn vm: GravityVirtualMachine) {
        let value = gravity_value_from_null()
        self.init(value: value, vm: vm)
    }
    
    convenience init(undefinedIn vm: GravityVirtualMachine) {
        let value = gravity_value_from_undefined()
        self.init(value: value, vm: vm)
    }
}

// MARK: Public Cast to

public extension GSValue {
    var toString: String {
        guard !self.isString else {
            return String(cString: gravity_cast_value_as_cString(self.value)!)
        }
        
        let string = convert_value2string(self.vm.vmPtr, self.value)
        return String(cString: gravity_cast_value_as_cString(string)!)
    }
    
    var toDouble: Double {
        return self.value.f
    }
    
    var toInteger: Int64 {
        return self.value.n
    }
    
    var toList: [GSValue] {
        guard self.isList else {
            return []
        }
        
        let list = gravity_cast_value_as_list(self.value)
        return []
    }
    
    var toBoolean: Bool {
        guard !self.isBool else {
            return gravity_cast_value_as_bool(self.value)
        }
        let bool = convert_value2bool(self.vm.vmPtr, self.value)
        return gravity_cast_value_as_bool(bool)
    }
    
    var toRange: ClosedRange<Int64> {
        let range = gravity_cast_value_as_range(self.value).pointee
        return range.from...range.to
    }
    
    // TODO: Currently not work with String/Double/Int/Range/List/Map
    func toObjectOf<T>(_ type: T.Type) -> T? {
        if !self.isInstance {
            return nil
        }
        
        let instance = gravity_cast_value_as_instance(self.value)
        // xdata contains pointer to object in memory
        return instance?.pointee.xdata.load(as: T.self)
    }
}

public extension GSValue {
    // TODO: Currently not work
    func hasMethod(named name: String) -> Bool {
        guard isInstance || isClass else {
            return false
        }
        
        let key = GSValue(string: name, in: self.vm).value
        let closure = gravity_class_lookup_closure(self.value.isa, key)
        let obj = gravity_value_from_object(closure)
        return gravity_value_isa_valid(obj)
    }
    
    func hasProperty(named name: String) -> Bool {
        let key = GSValue(string: name, in: self.vm).value
        
        let value: gravity_value_t
        
        if isInstance {
            let instance = gravity_cast_value_as_instance(self.value)
            value = gravity_instance_lookup_property(self.vm.vmPtr, instance, key)
        } else if isClass {
            // TODO: Currently not work
            let clazz = gravity_cast_value_as_class(self.value)
            guard let prop = gravity_class_lookup(clazz, key) else { return false }
            value = gravity_value_from_object(prop)
        } else {
            return false
        }
        
        return gravity_value_isa_valid(value)
    }
}

extension GSValue: Equatable {
    /// Equals to values in same virtual machine.
    public static func == (lhs: GSValue, rhs: GSValue) -> Bool {
        guard lhs.vm.vmPtr == rhs.vm.vmPtr else { return false }
        return gravity_value_vm_equals(lhs.vm.vmPtr, lhs.value, rhs.value)
    }
}

public extension GSValue {
    func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Int>) -> GSValue {
        
        if !self.isCallable {
            fatalError()
//            GSValue(value: <#T##gravity_value_t#>, vm: <#T##GravityVirtualMachine#>)
        }
        
        fatalError()
    }
}

// MARK: - Is A Check

public extension GSValue {
    var isString: Bool {
        return gravity_value_isa_string(self.value)
    }
    
    var isInteger: Bool {
        return gravity_value_isa_float(self.value)
    }
    
    var isDouble: Bool {
        return gravity_value_isa_int(self.value)
    }
    
    var isFunction: Bool {
        return gravity_value_isa_func(self.value)
    }
    
    var isFiber: Bool {
        return gravity_value_isa_fiber(self.value)
    }
    
    var isBool: Bool {
        return gravity_value_isa_bool(self.value)
    }
    
    var isClass: Bool {
        return gravity_value_isa_class(self.value)
    }
    
    var isNull: Bool {
        return gravity_value_isa_null(self.value)
    }
    
    var isNullClass: Bool {
        return gravity_value_isa_nullclass(self.value)
    }
    
    var isUndefined: Bool {
        return gravity_value_isa_undefined(self.value)
    }
    
    var isMap: Bool {
        return gravity_value_isa_map(self.value)
    }
    
    var isList: Bool {
        return gravity_value_isa_list(self.value)
    }
    
    var isRange: Bool {
        return gravity_value_isa_range(self.value)
    }
    
    var isInstance: Bool {
        return gravity_value_isa_instance(self.value)
    }
    
    var isClosure: Bool {
        return gravity_value_isa_closure(self.value)
    }
    
    var isError: Bool {
        return gravity_value_isa_error(self.value)
    }
    
    var isCallable: Bool {
        return gravity_value_isa_callable(self.value)
    }
    
    var isValid: Bool {
        return gravity_value_isa_valid(self.value)
    }
    
    var isNotValid: Bool {
        return gravity_value_isa_notvalid(self.value)
    }
    
    var isObject: Bool {
        return gravity_value_isobject(self.value)
    }
}
