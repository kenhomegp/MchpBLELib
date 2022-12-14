//
//  bleUARTDelegate.swift
//  BleUARTLib
//
//  Created by WSG Software on 2021/5/11.
//

import Foundation

@objc public protocol bleUARTDelegate{
    @objc optional func bleConnecting(bleScanState:Bool, discoveredPeripherals:[Any])
    @objc optional func bleDidConnect(peripheralName:String)
    @objc optional func bleDidDisconnect(error:String)
    @objc optional func bleDidUpdateStatus(status:String)
    @objc optional func DidWriteRawData(data:Data)
    @objc optional func DidUpdateRawData(data:Data)
    @objc optional func bleThroughputUpdate(Downlink:String?, Uplink:String?)
    @objc optional func didEnableRemoteControlMode()
}

