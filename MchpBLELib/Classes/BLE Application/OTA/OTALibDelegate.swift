//
//  OTALibDelegate.swift
//  MchpBLELib
//
//  Created by WSG Software on 2022/10/18.
//

import Foundation

@objc public protocol OTALibDelegate{
    @objc optional func OperationError(errorcode: UInt8, description: String)
    @objc optional func OTAProgressUpdate(state: UInt8, value: [UInt8], updateBytes: UInt, otaTime: String)
    @objc optional func bleConnecting(bleScanState:Bool, discoveredPeripherals:[Any])
    @objc optional func bleDidConnect(peripheralName:String)
}
