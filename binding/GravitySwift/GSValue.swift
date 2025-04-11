//
//  GSValue.swift
//  
//
//  Created by v.prusakov on 6/2/22.
//

import CGravity

/// Wrapper around Gravity Script Value.
/// You can create your GSValue and pass it to virtual machine, or cast given to valid format.
public class GSValue {
    
    public private(set) var value: gravity_value_t
    unowned let vm: GravityVirtualMachine
    
    public init(value: gravity_value_t, in vm: GravityVirtualMachine) {
        self.value = value
        self.vm = vm
    }
}

public extension GSValue {
    /// Create a new string in virtual machine memory.
    convenience init(string: String, in vm: GravityVirtualMachine) {
        let mutStr = UnsafeMutablePointer<CChar>.init(mutating: string.toPointer())
        
        let object = gravity_string_new(
            vm.vmPtr,
            mutStr,
            UInt32(string.count),
            UInt32(string.count)
        )
        let value = gravity_value_from_object(object)
        self.init(value: value, in: vm)
    }
    
    /// Create a new closed range in virtual machine memory.
    convenience init(range: ClosedRange<Int>, in vm: GravityVirtualMachine) {
        let object = gravity_range_new(vm.vmPtr, Int64(range.lowerBound), Int64(range.upperBound), true)
        let value = gravity_value_from_object(object)
        self.init(value: value, in: vm)
    }
    
    /// Create a new range in virtual machine memory.
    convenience init(range: Range<Int>, in vm: GravityVirtualMachine) {
        let object = gravity_range_new(vm.vmPtr, Int64(range.lowerBound), Int64(range.upperBound), false)
        let value = gravity_value_from_object(object)
        self.init(value: value, in: vm)
    }
    
    /// Create a new double in virtual machine memory.
    convenience init(double: Double, in vm: GravityVirtualMachine) {
        let value = gravity_value_from_float(double)
        self.init(value: value, in: vm)
    }
    
    /// Create a new integer in virtual machine memory.
    convenience init(integer: Int, in vm: GravityVirtualMachine) {
        let value = gravity_value_from_int(gravity_int_t(integer))
        self.init(value: value, in: vm)
    }
    
    /// Create a new boolean in virtual machine memory.
    convenience init(boolean: Bool, in vm: GravityVirtualMachine) {
        let value = gravity_value_from_bool(boolean)
        self.init(value: value, in: vm)
    }
    
    /// Create new instance of object, or store `gravity_value_t` or any refs to `gravity_object_y`.
    /// If object type not matched with supported type, then create undefined value.
    convenience init<T>(object: T, in vm: GravityVirtualMachine) {
        if let string = object as? String {
            self.init(string: string, in: vm)
        } else if let int = object as? Int {
            self.init(integer: int, in: vm)
        } else if let double = object as? Double {
            self.init(double: double, in: vm)
        } else if let bool = object as? Bool {
            self.init(boolean: bool, in: vm)
        } else if var exportType = object as? GSExportable & AnyObject {
            self.init(value: &exportType, in: vm)
        } else if let value = object as? gravity_value_t {
            self.init(value: value, in: vm)
        } else if let gravityObject = object as? UnsafeMutablePointer<gravity_object_t> {
            let value = gravity_value_from_object(gravityObject)
            self.init(value: value, in: vm)
        } else {
            self.init(undefinedIn: vm)
        }
    }
    
    /// Create a new array in virtual machine memory with given length.
    convenience init(newArrayIn vm: GravityVirtualMachine, length: Int = 1) {
        let list = gravity_list_new(vm.vmPtr, UInt32(length))
        let value = gravity_value_from_object(list)
        self.init(value: value, in: vm)
    }
    
    convenience init<T: GSExportable & AnyObject>(value: inout T, in vm: GravityVirtualMachine) {
        if let instance = value.instance, let value = instance.value?.value {
            self.init(value: value, in: vm)
        } else {
            let instance = GSIntstance(object: value, vm: vm)
            value.instance = instance
            self.init(value: instance.value!.value, in: vm)
        }
    }
    
    /// Create a new map in virtual machine memory with given length.
    convenience init(newMapIn vm: GravityVirtualMachine, length: Int = 1) {
        let list = gravity_map_new(vm.vmPtr, UInt32(length))
        let value = gravity_value_from_object(list)
        self.init(value: value, in: vm)
    }
    
    /// Create a new null value in virtual machine memory.
    convenience init(nullIn vm: GravityVirtualMachine) {
        let value = gravity_value_from_null()
        self.init(value: value, in: vm)
    }
    
    /// Create a new undefined value in virtual machine memory.
    convenience init(undefinedIn vm: GravityVirtualMachine) {
        let value = gravity_value_from_undefined()
        self.init(value: value, in: vm)
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
    
    var toInstance: GSIntstance? {
        guard isInstance else {
            return nil
        }
        
        return GSIntstance(value: self)
    }
    
    var toClass: GSValue {
        guard let isa = self.value.isa else {
            return GSValue(undefinedIn: vm)
        }
        
        let value = gravity_value_from_object(isa)
        return GSValue(value: value, in: vm)
    }
    
    // TODO: Currently not work with Range/List/Map
    func toObjectOf<T>(_ type: T.Type) -> T? {
        if type == String.self {
            return self.toString as? T
        }
        if type == Int.self {
            return Int(self.toInteger) as? T
        }
        if type == Int32.self {
            return Int32(self.toInteger) as? T
        }
        if type == Int16.self {
            return Int16(self.toInteger) as? T
        }
        if type == Int8.self {
            return Int8(self.toInteger) as? T
        }
        if type == Int8.self {
            return Int8(self.toInteger) as? T
        }
        if type == UInt8.self {
            return UInt8(self.toInteger) as? T
        }
        if type == UInt16.self {
            return UInt16(self.toInteger) as? T
        }
        if type == UInt32.self {
            return UInt32(self.toInteger) as? T
        }
        if type == Double.self {
            return self.toDouble as? T
        }
        
        // Extra data always contains reference to an object, and we should work with it as AnyObject, but cast to T.
        // With that hack we can support both value and reference types.
        guard let xdata = xData else { return nil }
        // We use unretained value, because we will release it later in bridge_free function.
        return Unmanaged<AnyObject>.fromOpaque(xdata).takeUnretainedValue() as? T
    }
}

extension GSValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        let value = gravity_value_hash(self.value)
        hasher.combine(value)
    }
}

public extension GSValue {
    
    var size: UInt32 {
        return gravity_value_size(self.vm.vmPtr, self.value)
    }
    
    var name: String {
        let cString = gravity_value_name(self.value)
        return cString.flatMap { String(cString: $0) } ?? ""
    }
    
    var xData: UnsafeMutableRawPointer? {
        return gravity_value_xdata(self.value)
    }
    
    func hasMethod(named name: String) -> Bool {
        if !isInstance {
            return false
        }
        
        let instance = gravity_cast_value_as_instance(self.value)
        
        let closure = name.withCString { ptr in
            gravity_instance_lookup_event(instance, name.toPointer())
        }
        
        guard let closure = closure else {
            return false
        }
        
        let val = gravity_value_from_object(closure)
        return gravity_value_isa_valid(val)
    }
    
    // TODO: Currently not work
    func hasClassMethod(named name: String) -> Bool {
        if !(isClass || isInstance) {
            return false
        }
        
        let key = GSValue(string: name, in: self.vm).value
        guard let closure = gravity_class_lookup_closure(self.value.isa, key) else {
            return false
        }
        let obj = gravity_value_from_object(closure)
        return gravity_value_isa_valid(obj)
        
    }
    
    /// Lookup only in instances properties.
    /// If you want check class properties use `hasClassProperty` method.
    func hasProperty(named name: String) -> Bool {
        if !isInstance {
            return false
        }
        
        let key = GSValue(string: name, in: self.vm).value
        let instance = gravity_cast_value_as_instance(self.value)
        let value = gravity_instance_lookup_property(self.vm.vmPtr, instance, key)
        
        return gravity_value_isa_valid(value)
    }
    
    // TODO: Currently not work
    func hasClassProperty(named name: String) -> Bool {
        if !isClass {
            return false
        }
        
        let key = GSValue(string: name, in: self.vm).value
        let clazz = gravity_cast_value_as_class(self.value)
        guard let prop = gravity_class_lookup(clazz, key) else {
            return false
            
        }
        let value = gravity_value_from_object(prop)
        
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
    func callMethod(named name: String, with args: [Any]) -> GSValue? {
        if self.hasMethod(named: name) {
            return nil
        }
        
        let closure = gravity_cast_value_as_closure(self.value)
        let arguments = args.map { GSValue(object: $0, in: self.vm) }
        
        return self.vm.execute(closure: closure, sender: self, params: arguments)
    }
    
    // Not sure that is works
    func callConstructor(with args: [Any]) -> GSValue? {
        let closure = gravity_cast_value_as_closure(self.value)
        let arguments = args.map { GSValue(object: $0, in: self.vm) }
        
        return self.vm.execute(closure: closure, sender: nil, params: arguments)
    }
    
    func callAsFunction(_ args: Any...) -> GSValue? {
        let closure = gravity_cast_value_as_closure(self.value)
        let arguments = args.map { GSValue(object: $0, in: self.vm) }
        
        return self.vm.execute(closure: closure, sender: nil, params: arguments)
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

public final class GSIntstance {
    
    weak var instance: AnyObject?
    public private(set) var value: GSValue?
    unowned let vm: GravityVirtualMachine
    
    public convenience init<T: GSExportable & AnyObject>(object: T, vm: GravityVirtualMachine) {
        let clazz = vm.getOrRegisterClass(T.self)
        let instance = gravity_instance_new(vm.vmPtr, clazz)
        let unmanaged = Unmanaged<T>.passUnretained(object).toOpaque()
        gravity_instance_setxdata(instance, unmanaged)
        let value = gravity_value_from_object(instance)
        self.init(value: value, in: vm)
    }
    
    public convenience init(value: gravity_value_t, in vm: GravityVirtualMachine) {
        self.init(value: GSValue(value: value, in: vm))
    }
    
    public init(value: GSValue) {
        self.value = value
        self.vm = value.vm
    }
    
    deinit {
        if let value = instance {
            Unmanaged.passUnretained(value).release()
        }
    }
}
