//
//  GSExportable.swift
//  
//
//  Created by v.prusakov on 6/4/22.
//

/// Base protocol to collection information about class or struct.
/// You can define class name, methods and static methods which called from Gravity Script.
public protocol GSExportable {
    static func export(in encoder: GravityExportEncoder) throws
}
