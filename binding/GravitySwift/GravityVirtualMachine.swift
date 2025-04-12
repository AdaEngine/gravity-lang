//
//  GravityVirtualMachine.swift
//
//
//  Created by v.prusakov on 6/4/22.
//

@_exported import CGravity
import Foundation

public final class GravityVirtualMachine {
    
    private var bridgeClassDescriptors: [String : GravityBridgeClassDescriptor] = [:]
    
    public struct Settings {
        public var reportNullErrors: Bool
        public var disableGarbageCollectorCheck: Bool
        public var xdata: UnsafeMutableRawPointer?
        
        public init(
            reportNullErrors: Bool = false,
            disableGarbageCollectorCheck: Bool = false,
            xdata: UnsafeMutableRawPointer? = nil
        ) {
            self.reportNullErrors = reportNullErrors
            self.disableGarbageCollectorCheck = disableGarbageCollectorCheck
            self.xdata = xdata
        }
    }
    
    unowned let delegate: GravityVirtualMachineDelegate
    
    internal let vmPtr: OpaquePointer
    
    private var vmDelegate: gravity_delegate_t
    
    public init(settings: Settings, delegate: GravityVirtualMachineDelegate) {
        var vmDelegate = gravity_delegate_t()
        vmDelegate.disable_gccheck_1 = settings.disableGarbageCollectorCheck
        vmDelegate.report_null_errors = settings.reportNullErrors
        vmDelegate.bridge_clone = bridgeClone
        vmDelegate.bridge_free = bridgeFree
        vmDelegate.bridge_equals = bridgeEquals
        vmDelegate.bridge_string = bridgeString
        vmDelegate.bridge_initinstance = bridgeInitInstance
        vmDelegate.bridge_execute = bridgeExecute
        vmDelegate.bridge_setvalue = bridgeSetValue
        vmDelegate.bridge_getvalue = bridgeGetValue
        vmDelegate.bridge_setundef = bridgeSetUndefValue
        vmDelegate.bridge_getundef = bridgeGetUndefValue
        
        self.vmDelegate = vmDelegate
        self.vmPtr = gravity_vm_new(&self.vmDelegate)
        self.delegate = delegate
        self.vmDelegate = vmDelegate
        
        Self.register(self)
    }
    
    deinit {
        Self.unregister(self)
        gravity_vm_free(self.vmPtr)
    }
    
    // MARK: - Public
    
    @discardableResult
    public func executeMain(for binary: UnsafeMutablePointer<gravity_closure_t>!) -> GSValue? {
        let runResult = gravity_vm_runmain(self.vmPtr, binary)
        
        if runResult {
            let result = gravity_vm_result(self.vmPtr)
            return GSValue(value: result, in: self)
        }
        
        return nil
    }
    
    @discardableResult
    public func execute(
        closure: UnsafeMutablePointer<gravity_closure_t>!,
        sender: GSValue? = nil,
        params: [GSValue] = []
    ) -> GSValue? {
        var args = params.map { $0.value }
        let sender = (sender ?? GSValue(nullIn: self)).value
        let runResult = gravity_vm_runclosure(self.vmPtr, closure, sender, &args, UInt16(args.count))
        
        if runResult {
            let result = gravity_vm_result(self.vmPtr)
            return GSValue(value: result, in: self)
        }
        
        return nil
    }
    
    public func loadClosure(
        closure: UnsafeMutablePointer<gravity_closure_t>!
    ) {
        gravity_vm_loadclosure(self.vmPtr, closure)
    }
    
    /// Off/On Garbage Collector
    public func setGCEnabled(_ isEnabled: Bool) {
        gravity_gc_setenabled(self.vmPtr, isEnabled)
    }
    
    public func getTime() -> Double {
        gravity_vm_time(self.vmPtr)
    }
    
    public func reset() {
        gravity_vm_reset(self.vmPtr)
    }
    
    public func getResult() -> GSValue {
        let value = gravity_vm_result(self.vmPtr)
        return GSValue(value: value, in: self)
    }
}

// MARK: - Bridging

public extension GravityVirtualMachine {
    func bindClass<T: GSExportable>(with type: T.Type) throws {
        self.setGCEnabled(false)
        
        let encoder = GravityExportEncoder(vm: self)
        try type.export(in: encoder)
        
        // Collect all descriptors
        let descriptors = encoder.classDescriptors
        
        for descriptor in descriptors {
            assert(bridgeClassDescriptors[descriptor.registredName] == nil, "We have registred class with name - \(descriptor.registredName).")
            
            self.setValue(descriptor.gClass, forKey: descriptor.registredName)
            self.bridgeClassDescriptors[descriptor.registredName] = descriptor
        }
        
        self.setGCEnabled(true)
    }
    
    func setValue<T>(_ value: T, forKey key: String) {
        let gsValue = GSValue(object: value, in: self)
        key.withCString { ptr in
            gravity_vm_setvalue(self.vmPtr, ptr, gsValue.value)
        }
    }
    
    subscript(_ key: String) -> GSValue {
        return self.getValue(forKey: key)
    }
    
    func getValue(forKey key: String) -> GSValue {
        let value = key.withCString { ptr in
            return gravity_vm_getvalue(self.vmPtr, ptr, UInt32(key.count))
        }
        
        return GSValue(value: value, in: self)
    }
    
}

// MARK: - Bridging Internal

extension GravityVirtualMachine {
    func getClassDescriptor(for name: String) -> GravityBridgeClassDescriptor? {
        return bridgeClassDescriptors[name]
    }
}

extension GravityVirtualMachine {
    nonisolated(unsafe) private static var virtualMachines: [GravityVirtualMachine] = []
    
    nonisolated static func getVM(_ pointer: OpaquePointer) -> GravityVirtualMachine? {
        self.virtualMachines.first(where: { $0.vmPtr == pointer })
    }
    
    nonisolated static func register(_ vm: GravityVirtualMachine) {
        self.virtualMachines.append(vm)
    }
    
    nonisolated static func unregister(_ vm: GravityVirtualMachine) {
        self.virtualMachines.removeAll(where: { $0.vmPtr == vm.vmPtr })
    }
}

extension GravityVirtualMachine {
    func getOrRegisterClass<T: GSExportable>(_ type: T.Type) -> UnsafeMutablePointer<gravity_class_t> {
        let clazzName = self.getValue(forKey: T.runtimeName)
        
        if clazzName.isClass {
            return clazzName.toGravityClass
        }
        
        let clazz = T.runtimeName.withCString { ptr in
            return gravity_class_new_pair(
                self.vmPtr, // vm
                ptr, // name
                nil, // parent class
                0, // nivar
                0 // nsvar
            )
        }
        
        return clazz!
    }
}

extension String {
    func toPointer() -> UnsafePointer<CChar>? {
        guard let data = self.data(using: .utf8) else { return nil }
        
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
        let stream = OutputStream(toBuffer: buffer, capacity: data.count)
        
        stream.open()
        data.withUnsafeBytes { (p: UnsafePointer<CChar>) -> Void in
            stream.write(p, maxLength: data.count)
        }
        
        stream.close()
        
        return UnsafePointer<CChar>(buffer)
    }
}

@MainActor
func logCallback(_ vmPointer: OpaquePointer?, message: UnsafePointer<CChar>?, xdata: UnsafeMutableRawPointer?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    vm.delegate.virtualMachineDidReciveLog(vm, message: String(cString: message!), data: xdata)
}

@MainActor
func logClear(_ vmPointer: OpaquePointer?, xdata: UnsafeMutableRawPointer?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    vm.delegate.virtualMachineDidClearLog(vm, data: xdata)
}

@MainActor
func errorCallback(_ vmPointer: OpaquePointer?, errType: error_type_t, message: UnsafePointer<CChar>!, errDesc: error_desc_t, xdata: UnsafeMutableRawPointer?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    print("Error!", String(cString: message))
}

func bridgeFree(_ vmPointer: OpaquePointer?, objptr: UnsafeMutablePointer<gravity_object_t>?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    let value = GSValue(object: objptr, in: vm)
    if let xData = value.xData {
        Unmanaged<AnyObject>.fromOpaque(xData).release()
    }
    
    vm.delegate.virtualMachine(vm, didRequestFree: value)
}

func bridgeSize(_ vmPointer: OpaquePointer?, objptr: UnsafeMutablePointer<gravity_object_t>?) -> UInt32 {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    
    let value = GSValue(object: objptr, in: vm)
    return vm.delegate.virtualMachine(vm, didRequestSizeFor: value)
}

func bridgeClone(
    vmPointer: OpaquePointer!,
    objptr: UnsafeMutableRawPointer?
) -> UnsafeMutableRawPointer? {
    guard let vm = GravityVirtualMachine.getVM(vmPointer) else { fatalError("Cannot found Virtual Machine") }
    let value = GSValue(object: objptr, in: vm)
    let clonedValue = vm.delegate.virtalMachine(vm, didRequestCloneFor: value)
    
    fatalError()
//    return UnsafeMutableRawPointer(
}

/// get description from object xdata
func bridgeString(
    vmPointer: OpaquePointer!,
    xdata: UnsafeMutableRawPointer?,
    length: UnsafeMutablePointer<UInt32>?
) -> UnsafePointer<CChar>? {
    guard let vm = GravityVirtualMachine.getVM(vmPointer) else { fatalError("Cannot found Virtual Machine") }
    let string = vm.delegate.virtualMachine(vm, didRequestStringWith: length!.pointee, data: xdata)
    return string.toPointer()
}

func bridgeEquals(
    vmPointer: OpaquePointer!,
    lhsPtr: UnsafeMutableRawPointer?,
    rhsPtr: UnsafeMutableRawPointer?
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachineBridgeEquals(vm, lhsValue: GSValue(object: lhsPtr, in: vm), rhsValue: GSValue(object: lhsPtr, in: vm))
}

func bridgeInitInstance(
    _ vmPointer: OpaquePointer!,
    xdata: UnsafeMutableRawPointer?,
    ctx: gravity_value_t,
    instance: UnsafeMutablePointer<gravity_instance_t>?,
    args: UnsafeMutablePointer<gravity_value_t>?,
    argsCount: Int16
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer) else { fatalError("Cannot found Virtual Machine") }
    
    // first arg
    let arguments: [GSValue] = (1..<argsCount).map { index in
        let arg = args![Int(index)]
        return GSValue(object: arg, in: vm)
    }
    
    let method = Unmanaged<MethodDescriptor>.fromOpaque(xdata!).takeUnretainedValue()
    
    if arguments.count > method.argsCount {
        return GravityReturn.error("Passed more arguments, then expected. Method \(method.name) expected \(method.argsCount) arguments, but passed \(arguments.count) arguments.", vm: vm)
    }
    
    guard let object = method.callStatic(with: arguments) as? AnyObject else {
        return GravityReturn.error("Return value of init supports only reference types.", vm: vm)
    }
    
    let value = Unmanaged.passRetained(object).toOpaque()
    gravity_instance_setxdata(instance, value)
    
    return GravityReturn.noValue()
}

private func bridgeExecute(
    vmPointer: OpaquePointer?,
    data: UnsafeMutableRawPointer?, // always return method descriptor
    ctx: gravity_value_t,
    args: UnsafeMutablePointer<gravity_value_t>!,
    argsCount: Int16,
    rIndex: UInt32
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    
    guard let methodDescRef = data else {
        return GravityReturn.error("Required xdata not passed", vm: vm)
    }
    
    var arguments: [GSValue] = (0..<argsCount).map { index in
        let value = args[Int(index)]
        return GSValue(object: value, in: vm)
    }
    
    // First value always contains instance
    let callee = arguments.removeFirst()
    let method = Unmanaged<MethodDescriptor>.fromOpaque(methodDescRef).takeUnretainedValue()
    
    if arguments.count > method.argsCount {
        return GravityReturn.error("Passed more arguments, then expected. Method \(method.name) expected \(method.argsCount) arguments, but passed \(arguments.count) arguments.", vm: vm)
    }
    
    if callee.xData == nil {
        return GravityReturn.error("Instance don't have any ref to allocated object.", vm: vm)
    }
    
    let value = method.call(in: callee, with: arguments)
    
    if value is Void {
        return GravityReturn.noValue()
    } else {
        return GravityReturn.value(GSValue(object: value, in: vm), rIndex: Int32(rIndex), vm: vm)
    }
}

func bridgeSetValue(
    vmPointer: OpaquePointer!,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    value: gravity_value_t
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    
    guard let xdata = xdata else {
        return GravityReturn.error("Extra data for bridging not passed!", vm: vm)
    }

    let target = GSValue(value: target, in: vm)
    let newValue = GSValue(value: value, in: vm)

    let propertyDescriptor = Unmanaged<PropertyDescriptor>.fromOpaque(xdata).takeUnretainedValue()
    
    if propertyDescriptor.isReadonly {
        return GravityReturn.error("Unexpected calling setter in readonly property!", vm: vm)
    }
    
    propertyDescriptor.setValue(newValue, in: target)

    return GravityReturn.noValue()
}

func bridgeSetUndefValue(
    vmPointer: OpaquePointer!,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    value: gravity_value_t
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    
    let value = GSValue(object: value, in: vm)
    let target = GSValue(object: target, in: vm)
    
    return vm.delegate.virtualMachine(vm, xdata: xdata, didSetUndefValue: value, in: target, forKey: String(cString: key!))
}

func bridgeGetValue(
    vmPointer: OpaquePointer!,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    rIndex: UInt32
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
        
    guard let xdata = xdata else {
        return GravityReturn.error("Extra data for bridging not passed!", vm: vm)
    }
    
    let target = GSValue(value: target, in: vm)

    let propertyDescriptor = Unmanaged<PropertyDescriptor>.fromOpaque(xdata).takeUnretainedValue()
    let value = propertyDescriptor.getValue(in: target)
    
    return GravityReturn.value(value, rIndex: Int32(rIndex), vm: vm)
}

func bridgeGetUndefValue(
    _ vmPointer: OpaquePointer?,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    vindex: UInt32
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    let target = GSValue(object: target, in: vm)
    do {
        if let value = try vm.delegate.virtualMachine(vm, xdata: xdata, didGetUndefValueFrom: target, forKey: String(cString: key!)) {
            return GravityReturn.value(value, rIndex: Int32(vindex), vm: vm)
        }
        return GravityReturn.noValue()
    } catch {
        return GravityReturn.error(error.localizedDescription, rIndex: Int32(vindex), vm: vm)
    }
}

