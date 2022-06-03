import CGravity

@_implementationOnly import Foundation

public protocol GravityVirtualMachineDelegate: AnyObject {
    
    func virtualMachineDidReciveLog(_ virtualMachine: GravityVirtualMachine, message: String, data: UnsafeMutableRawPointer?)
    func virtualMachineDidClearLog(_ virtualMachine: GravityVirtualMachine, data: UnsafeMutableRawPointer?)
    
    func virtualMachineBridgeEquals(_ virtualMachine: GravityVirtualMachine, lhsObject: GSObject, rhsObject: GSObject) -> Bool
    
    func virtalMachine(_ virtualMachine: GravityVirtualMachine, didRequestCloneFor object: GSObject) -> GSObject
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine)
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didExecuteIn ctx: gravity_value_t,
        arguments: [gravity_value_t],
        argumentsCount: Int16,
        vIndex: UInt32,
        data: UnsafeMutableRawPointer?
    ) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didSetValue value: gravity_value_t,
        in target: gravity_value_t,
        forKey key: String
    ) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didGetValueFrom target: gravity_value_t,
        forKey: String,
        vIndex: UInt32
    ) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didSetUndefValue value: gravity_value_t,
        in target: gravity_value_t,
        forKey key: String
    ) -> Bool
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didGetUndefValueFrom target: gravity_value_t,
        forKey: String,
        vIndex: UInt32
    ) -> Bool
    
    // MARK: Memory managment
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestStringWith length: UInt32, data: UnsafeMutableRawPointer?) -> String
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestFree object: gravity_object_t)
    
    func virtualMachine(_ virtualMachine: GravityVirtualMachine, didRequestSizeFor object: gravity_object_t) -> UInt32
    
    func virtualMachine(
        _ virtualMachine: GravityVirtualMachine,
        didInitObjectIn ctx: gravity_value_t,
        instance:  UnsafeMutablePointer<gravity_instance_t>?,
        arguments: [gravity_value_t],
        argumentsCount: Int16,
        data: UnsafeMutableRawPointer?
    ) -> Bool
}

public final class GravityVirtualMachine {
    
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
    
    private var instances: [GSInstance] = []
    
    unowned let delegate: GravityVirtualMachineDelegate
    
    private var registredClass: [String: UnsafeMutablePointer<gravity_class_t>] = [:]
    
    internal private(set) var vmPtr: OpaquePointer
    
    public init(settings: Settings, delegate: GravityVirtualMachineDelegate) {
        var vmDelegate = gravity_delegate_t(
            xdata: settings.xdata,
            report_null_errors: settings.reportNullErrors,
            disable_gccheck_1: settings.disableGarbageCollectorCheck,
            log_callback: logCallback,
            log_clear: logClear,
            error_callback: errorCallback,
            unittest_callback: { _, errType, desc, note, value, row, col, xdata in
                fatalError("")
            },
            parser_callback: { token, xdata in
                return
            },
            type_callback: { token, type, xdata in
                return
            },
            precode_callback: { xdata in
                return nil
            },
            loadfile_callback: { fileName, size, fileId, xdata, isStatic in
                return nil
            },
            filename_callback: { fileId, xdata in
                return nil
            },
            optional_classes: { xdata in
                return nil
            },
            bridge_initinstance: bridgeInitInstance,
            bridge_setvalue: bridgeSetValue,
            bridge_getvalue: bridgeGetValue,
            bridge_setundef: bridgeSetUndefValue,
            bridge_getundef: bridgeGetUndefValue,
            bridge_execute: bridgeExecute,
            bridge_blacken: { _, xdata in
                fatalError("")
            },
            bridge_string: bridgeString,
            bridge_equals: bridgeEquals,
            bridge_clone: bridgeClone,
            bridge_size: bridgeSize,
            bridge_free: bridgeFree)
        
        self.vmPtr = gravity_vm_new(&vmDelegate)
        self.delegate = delegate
        
        Self.register(self)
    }
    
    deinit {
        gravity_vm_free(self.vmPtr)
        Self.unregister(self)
    }
    
    // MARK: - Public
    
    @discardableResult
    public func executeMain(for binary: UnsafeMutablePointer<gravity_closure_t>!) -> GSValue {
        let runFinished = gravity_vm_runmain(self.vmPtr, binary)
        
        if runFinished {
            let result = gravity_vm_result(self.vmPtr)
            return GSValue(value: result, vm: self)
        }
        
        fatalError()
    }
    
    @discardableResult
    public func execute(binary: UnsafeMutablePointer<gravity_closure_t>!) {
//        gravity_vm_runclosure(self.virtualMachine, binary, <#T##sender: gravity_value_t##gravity_value_t#>, <#T##params: UnsafeMutablePointer<gravity_value_t>!##UnsafeMutablePointer<gravity_value_t>!#>, <#T##nparams: UInt16##UInt16#>)
        
        fatalError()
    }
}

public extension GravityVirtualMachine {
    func bindClass<T: GravityExportable>(with type: T.Type) {
        let encoder = GravityExportEncoder(vm: self)
        try! type.export(in: encoder)
    }
    
    func setValue<T>(_ value: T, forKey key: String) {
        let gsValue = GSValue(object: value, in: self)
        gravity_vm_setvalue(self.vmPtr, key.toPointer(), gsValue.value)
    }
    
    subscript(_ key: String) -> GSValue {
        let value = gravity_vm_getvalue(self.vmPtr, key.toPointer(), UInt32(key.count))
        return GSValue(value: value, vm: self)
    }
    
    func setInstance(_ instance: GSInstance) {
        self.instances.append(instance)
    }
    
    func freeIntance(_ instance: GSInstance) {
        self.instances.removeAll { $0 === instance }
    }
}

extension GravityVirtualMachine {
    private static var virtualMachines: [GravityVirtualMachine] = []
    
    static func getVM(_ pointer: OpaquePointer) -> GravityVirtualMachine? {
        self.virtualMachines.first(where: { $0.vmPtr == pointer })
    }
    
    static func register(_ vm: GravityVirtualMachine) {
        self.virtualMachines.append(vm)
    }
    
    static func unregister(_ vm: GravityVirtualMachine) {
        self.virtualMachines.removeAll(where: { $0.vmPtr == vm.vmPtr })
    }
}

extension GravityVirtualMachine {
    
    func getOrRegisterClass<T>(_ type: T.Type) -> UnsafeMutablePointer<gravity_class_t> {
        
        let string = String(describing: type)
        
        if let clazz = self.registredClass[string] {
            return clazz
        }
        
        let clazz = gravity_class_new_pair(
            self.vmPtr, // vm
            string.toPointer(), // name
            nil, // parent class
            0, // nivar
            0 // nsvar
        )
        
        self.registredClass[string] = clazz
        
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

func logCallback(_ vmPointer: OpaquePointer?, message: UnsafePointer<CChar>?, xdata: UnsafeMutableRawPointer?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    vm.delegate.virtualMachineDidReciveLog(vm, message: String(cString: message!), data: xdata)
}

func logClear(_ vmPointer: OpaquePointer?, xdata: UnsafeMutableRawPointer?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    vm.delegate.virtualMachineDidClearLog(vm, data: xdata)
}

func errorCallback(_ vmPointer: OpaquePointer?, errType: error_type_t, message: UnsafePointer<CChar>?, errDesc: error_desc_t, xdata: UnsafeMutableRawPointer?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
}

//func unittestCallback

func bridgeExecute(_ vmPointer: OpaquePointer?, data: UnsafeMutableRawPointer?, ctx: gravity_value_t, argsPtr: UnsafeMutablePointer<gravity_value_t>?, argsCount: Int16, vIndex: UInt32) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(
        vm,
        didExecuteIn: ctx,
        arguments: [],
        argumentsCount: argsCount,
        vIndex: vIndex,
        data: data
    )
}

func bridgeFree(_ vmPointer: OpaquePointer?, objptr: UnsafeMutablePointer<gravity_object_t>?) {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    
    vm.delegate.virtualMachine(vm, didRequestFree: objptr!.pointee)
}

func bridgeSize(_ vmPointer: OpaquePointer?, objptr: UnsafeMutablePointer<gravity_object_t>?) -> UInt32 {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(vm, didRequestSizeFor: objptr!.pointee)
}

func bridgeClone(_ vmPointer: OpaquePointer?, objptr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    let obj = GSObject(ref: objptr!, vm: vm)
    return vm.delegate.virtalMachine(vm, didRequestCloneFor: obj).ref
}

func bridgeString(_ vmPointer: OpaquePointer?, xdata: UnsafeMutableRawPointer?, length: UnsafeMutablePointer<UInt32>?) -> UnsafePointer<CChar>? {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    let string = vm.delegate.virtualMachine(vm, didRequestStringWith: length!.pointee, data: xdata)
    return string.toPointer()
}

func bridgeEquals(_ vmPointer: OpaquePointer?, lhsPtr: UnsafeMutableRawPointer?, rhsPtr: UnsafeMutableRawPointer?) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachineBridgeEquals(vm, lhsObject: GSObject(ref: lhsPtr!, vm: vm), rhsObject: GSObject(ref: rhsPtr!, vm: vm))
}

func bridgeInitInstance(
    _ vmPointer: OpaquePointer?,
    xdata: UnsafeMutableRawPointer?,
    ctx: gravity_value_t,
    instance: UnsafeMutablePointer<gravity_instance_t>?,
    args: UnsafeMutablePointer<gravity_value_t>?,
    argsCount: Int16
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(vm, didInitObjectIn: ctx, instance: instance, arguments: [], argumentsCount: argsCount, data: xdata)
}

func bridgeSetValue(
    _ vmPointer: OpaquePointer?,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    value: gravity_value_t
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(vm, didSetValue: value, in: target, forKey: String(cString: key!))
}

func bridgeSetUndefValue(
    _ vmPointer: OpaquePointer?,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    value: gravity_value_t
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(vm, didSetUndefValue: value, in: target, forKey: String(cString: key!))
}

func bridgeGetValue(
    _ vmPointer: OpaquePointer?,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    vindex: UInt32
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(vm, didGetValueFrom: target, forKey: String(cString: key!), vIndex: vindex)
}


func bridgeGetUndefValue(
    _ vmPointer: OpaquePointer?,
    xdata: UnsafeMutableRawPointer?,
    target: gravity_value_t,
    key: UnsafePointer<CChar>?,
    vindex: UInt32
) -> Bool {
    guard let vm = GravityVirtualMachine.getVM(vmPointer!) else { fatalError("Cannot found Virtual Machine") }
    return vm.delegate.virtualMachine(vm, didGetUndefValueFrom: target, forKey: String(cString: key!), vIndex: vindex)
}

public class GSInstance {
    
    var instance: UnsafeMutablePointer<gravity_instance_t>?
    
    init?<T>(for object: inout T, in vm: GravityVirtualMachine) {
        let clazz = vm.getOrRegisterClass(T.self)
        let instance = gravity_instance_new(vm.vmPtr, clazz)
        gravity_instance_setxdata(instance, &object)
        
        self.instance = instance
    }
    
//    init<T>(for type: T.Type, in vm: GravityVirtualMachine) {
//        let clazz = vm.getOrRegisterClass(T.self)
//        
//        self.instance = instance
//    }
    
    deinit {
        print("kek")
    }
}

