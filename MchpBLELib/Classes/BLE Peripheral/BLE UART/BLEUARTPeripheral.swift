//
//  BLEUARTConnection.swift
//  BleUARTLib
//
//  Created by WSG Software on 2022/7/27.
//

import Foundation
import CoreBluetooth

protocol TRCBP_Profile{
    var peripheral: CBPeripheral? { get set }
    //var BLEUARTConnectionHandler: BLEUARTConnectionCallback? { get set }
    var TransparentServiceEnabled: ((bleUartError?) -> Void)? { get set }
    var TransparentConfig: LEConfiguration? { get set }
    
    var L2CapCoC: L2CapConnection? {get set}
    var L2CapCoCPSM: UInt16? { get set }
    var L2CapConnections: Dictionary<UUID,L2CapConnection>? {get set}
    
    func L2CapConnect(peripheral: CBPeripheral, psm: UInt16, connectionHandler:  @escaping L2CapConnectionCallback)
    func ConnectL2CapCoC()
    func DisconnectL2CapCoc()
}

struct LEConfiguration{
    var mtu : Int = 0
    var WriteType: CBCharacteristicWriteType = .withoutResponse{
        didSet{
            print("WriteType is changed! \(self.WriteType)")
        }
    }
    var ReliableWriteLen: Int = 0
    var transmit: ReliableBurstTransmit?
    var ActiveDataPath: PeripheralDataPath = .GATT {
        didSet{
            print("ActiveDataPath is changed! \(self.ActiveDataPath)")
        }
    }
    
    var deviceProfile: bleUARTProfile = .TRP
    
    mutating func SetWriteType(NewType : CBCharacteristicWriteType){
        self.WriteType = NewType
    }
    
    mutating func SetDataPath(NewPath : PeripheralDataPath){
        self.ActiveDataPath = NewPath
    }
    
    mutating func SetDeviceSupportProfile(profile: bleUARTProfile){
        self.deviceProfile = profile
    }
}
    
class BLEUARTPeripheral : NSObject, CBPeripheralDelegate, bleUARTPeripheralDelegate, ReliableBurstTransmitDelegate, TRCBP_Profile, DIS_Profile{
    
    var DIS: DeviceInformationService

    var DISUpdateValues: ((deviceUUID, [DIS_Index : String]) -> Void)?
    
    var peripheral: CBPeripheral?
    
    //var BLEUARTConnectionHandler: BLEUARTConnectionCallback?
    
    var TransparentServiceEnabled: ((bleUartError?) -> Void)?
    
    var TransparentConfig: LEConfiguration?
    
    var TransparentTrcbpControl: CBCharacteristic?
    
    var L2CapCoC: L2CapConnection?
    
    var L2CapCoCPSM: UInt16?
    
    var L2CapConnections: Dictionary<UUID, L2CapConnection>?
    
    var didUpdateValue: ((Any, Data, bleUartError?) -> Void)?
    
    var didWriteValue: ((Any, bleUartError?) -> Void)?
    
    var isSupportRemoteComtrolMode:Bool
    
        
    init(peripheral: CBPeripheral, connectionCallback: @escaping BLEUARTConnectionCallback) {
        self.peripheral = peripheral
        self.L2CapConnections = [:]
        self.L2CapCoC = nil
        //self.BLEUARTConnectionHandler = connectionCallback
        self.DIS = DeviceInformationService()
        self.isSupportRemoteComtrolMode = false
        super.init()
        self.peripheral!.delegate = self
        print("BLEUARTPeripheral init")
        //self.BLEUARTConnectionHandler!(self)
        connectionCallback(self)
        self.TransparentConfig = LEConfiguration()
        
    }
    
    deinit{
        print("Bye,BLEUARTPeripheral.\(peripheral?.identifier.uuidString ?? "")")
    }
    
    func DiscoverBLEServices(completion: @escaping (bleUartError?)-> Void){
        //BLEUARTConnectionHandler = nil
        self.TransparentServiceEnabled = completion
        self.peripheral!.discoverServices(nil)
        print(#function)
    }
    
    func GetCharacteristic(ServiceUUID: CBUUID, CharUUID: CBUUID) -> CBCharacteristic?{
        if let services = peripheral!.services?.filter({$0.uuid == ServiceUUID}){
            if(!services.isEmpty){
                if let Characteristics = services.first?.characteristics?.filter({$0.uuid == CharUUID}){
                    if(!Characteristics.isEmpty){
                        //print("GetCharacteristic uuid = \(Characteristics[0].uuid.uuidString)")
                        return Characteristics.first
                    }
                }
            }
        }
        return nil
    }
    
    func DataPathDidChanged(profile: bleUARTProfile){
        if(profile == .TRP){
            TransparentConfig?.SetDataPath(NewPath: .GATT)
        }
        else if(profile == .TRCBP){
            if(self.L2CapCoC == nil){
                TransparentConfig?.SetDataPath(NewPath: .L2CAP)
                ConnectL2CapCoC()
            }
        }
    }
    
    func sendTransparentData(data: Data) {
        if(TransparentConfig?.WriteType == CBCharacteristicWriteType.withoutResponse){
            if(TransparentConfig?.transmit == nil) {
                print("ReliableBurstTransmit init fail!")
                return
            }
            
            if((TransparentConfig?.transmit?.canSendReliableBurstTransmit())! && (TransparentConfig?.transmit?.isReliableBurstTransmitSupport())!){
                print("Can't send reliableburstdata, Not support!")
                return
            }
            
            let characteristic = GetCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_TX)
            
            if let char = characteristic{
                if(TransparentConfig?.ActiveDataPath == .GATT){
                    self.TransparentConfig?.transmit?.reliableBurstTransmit(data: data, transparentDataWriteChar: char)
                }
            }
        }
        else{
            let characteristic = GetCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_TX)
            
            if let char = characteristic{
                print("Write vale with response.\(data)")
                peripheral!.writeValue(data, for: char, type: .withResponse)
            }
        }
    }
    
    func GetIsSupportRemoteControlMode() -> Bool{
        return isSupportRemoteComtrolMode
    }
    
    // MARK: - TRCBP(L2CAP CoC)
    func DisconnectL2CapCoc(){
        if(self.L2CapCoC != nil){
            print(#function)
            self.L2CapCoC?.stop()
            let _ = self.L2CapCoC?.CloseStream()
            self.L2CapCoC?.readDataCallback = nil
            self.L2CapCoC?.writeDataCallback = nil
            self.L2CapCoC = nil
            self.L2CapConnections?.removeAll()
        }
    }
    
    func ConnectL2CapCoC(){
        L2CapConnect(peripheral: peripheral!, psm: L2CapCoCPSM!){
            connection in
            self.L2CapCoC = connection
            print("L2CapCoC connection = \(self.L2CapCoC!)")

            let characteristic = self.GetCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_TRCBP_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRCBP_CTRL)
            if let char = characteristic{
                self.peripheral?.setNotifyValue(true, for: char)
                print("Enable L2capControl characteristic")
            }
                
            self.peripheral?.delegate = self
                
            self.L2CapCoC?.readDataCallback = {
                (data) in
                //print("[L2CapCoC]readDataCallback. bytesRead = \(data.count)")
                self.didUpdateValue?(data.count, data, nil)
            }
                
            self.L2CapCoC?.writeDataCallback = {
                (bytesWrite) in
                //print("[L2CapCoC]writeDataCallback. bytesWrite = \(bytesWrite)")
                    
                self.didWriteValue?(bytesWrite, nil)
            }
        }
    }
    
    func L2CapConnect(peripheral: CBPeripheral, psm: UInt16, connectionHandler: @escaping L2CapConnectionCallback) {
        let l2Connection = L2CapCentralConnection(peripheral: peripheral, psm: psm, connectionCallback: connectionHandler)

        self.L2CapConnections?[peripheral.identifier] = l2Connection
    }
    
    // MARK: - bleUARTPeripheral Delegate
    func WriteValue(value: Data, IsCommand: Bool) {
        if(IsCommand){
            //print("WriteCommandToCharacteristic, cmd = \(value as NSData)")
            if(TransparentConfig?.ActiveDataPath == .GATT){
                print("MCHP_TRANS_CTRL,WriteCommandToCharacteristic, cmd = \(value as NSData)")
                let characteristic = GetCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_CTRL)
                
                if let char = characteristic{
                    peripheral!.writeValue(value, for: char, type: .withResponse)
                }
            }
            else{
                print("MCHP_TRCBP_CTRL,WriteCommandToCharacteristic, cmd = \(value as NSData)")
                let characteristic = GetCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_TRCBP_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRCBP_CTRL)
                
                if let char = characteristic{
                    peripheral!.writeValue(value, for: char, type: .withResponse)
                }
            }
        }
        else{
            if(TransparentConfig?.ActiveDataPath == .GATT){
                //print("sendTransparentData.data len = \(value.count)")
                sendTransparentData(data: value)
            }
            else{
                if let l2CapCoC = L2CapCoC{
                    print("L2CapCoC send data.\(value)")
                    l2CapCoC.send(data: value)
                }
            }
        }
    }
    
    func WriteValueToCharacteristic(ServiceUUID: CBUUID, CharUUID: CBUUID, value: Data) {
        
        let characteristic = GetCharacteristic(ServiceUUID: ServiceUUID, CharUUID: CharUUID)
        
        if let char = characteristic{
            print("WriteValueToCharacteristic. char uuid = \(char.uuid.uuidString)")
            peripheral!.writeValue(value, for: char, type: .withResponse)
        }
    }
    
    // MARK: - DIS
    func GetDeviceInformation() {
        //print("DIS delegate = \(self.DISUpdateValues)")
        
        if let services = peripheral!.services?.filter({$0.uuid == DeviceInformationService.DEVICE_INFO_SERVICE}){
            if(!services.isEmpty){
                print(#function)
                DIS.ClearData()
                let Characteristics = services.first?.characteristics
                if let DIS_Characteristics = Characteristics{
                    if(!DIS_Characteristics.isEmpty){
                        for char in DIS_Characteristics{
                            let disIndex = DIS.CBUUIDToDISIndex(uuid: char.uuid)
                            if disIndex != nil{
                                print("Read DIS characteristic = \(disIndex)")
                                DIS.SetValue(index: disIndex!, value: "")
                                self.peripheral?.readValue(for: char)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func DIS_Peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) -> Bool? {
        let disIndex = DIS.CBUUIDToDISIndex(uuid: characteristic.uuid)
        if(disIndex != nil){
            //print("Update DIS value. \(disIndex)")
            let disValueStr = String(data: characteristic.value!, encoding: .utf8)
            if disValueStr != nil{
                if characteristic.uuid == DeviceInformationService.DIS_PNP_ID_CHAR{
                    let data = characteristic.value! as Data
                    let dataBytes = [UInt8](data)
                    print("data = ",dataBytes)
                    //if disValueStr == "00CD9B01"{
                    if dataBytes[1] == 0x00 && dataBytes[2] == 0xCD && dataBytes[3] == 0x9B && dataBytes[4] == 0x01 {
                        isSupportRemoteComtrolMode = true
                    }
                }
                DIS.SetValue(index: disIndex!, value: disValueStr!)
            }
            
            if(DIS.DataReady()){
                print("DIS PASS")
                self.DISUpdateValues?(peripheral.identifier.uuidString, DIS.DISArray)
            }
            return true
        }
        return nil
    }
  
    // MARK: - CoreBluetooth delegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error == nil) {
            print("Peripheral UUID : \(peripheral.identifier.uuidString.utf8) found\r\n" );
            
            for service in peripheral.services! {
                let thisService = service as CBService
                print("Service uuid = \(thisService.uuid.uuidString)")
                
                self.peripheral!.discoverCharacteristics(nil, for: thisService)
            }
        } else {
            print("Service discovery was unsuccessfull");
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if(error == nil) {
            print("didDiscoverCharacteristics");
            
            for Char in service.characteristics! {
                let thisChar = Char as CBCharacteristic
                print("Characteristic uuid = \(thisChar.uuid.uuidString)")
                
                if(service.uuid == ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE) {
                    print("ISSC_PROPRIETARY_SERVICE")
                    
                    if(thisChar.uuid == ProfileServiceUUID.MCHP_TRANS_TX) {
                        print("MCHP_TRANS_TX")
                        
                        if Char.properties.contains(.write){
                            print("MCHP_TRANS_TX Char property : Write")
                        }
                    }
                    else if(thisChar.uuid == ProfileServiceUUID.MCHP_TRANS_RX) {
                        print("MCHP_TRANS_RX. \(Char.properties)")

                        //Set Notify
                        peripheral.setNotifyValue(true, for: thisChar)
                    }
                    else if(thisChar.uuid == ProfileServiceUUID.MCHP_TRANS_CTRL) {
                        
                        print("MCHP_TRANS_CTRL")
                        self.TransparentConfig?.transmit = ReliableBurstTransmit()
                        self.TransparentConfig?.transmit?.delegate = self
                        self.TransparentConfig?.transmit?.switchLibrary(false)
                        let characteristic = GetCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_CTRL)
                        if let char = characteristic{
                            self.TransparentConfig?.transmit?.enableReliableBurstTransmit(peripheral: self.peripheral!, airPatchCharacteristic: char)
                        }
                    }
                }
                
                if(service.uuid == ProfileServiceUUID.MCHP_TRCBP_SERVICE) {
                    if(Char.uuid == ProfileServiceUUID.MCHP_TRCBP_CHAR) {
                        //peripheral.setNotifyValue(true, for: Char)
                        peripheral.readValue(for: Char)
                    }
                }
            }
        }
        else {
            print("Characteristics discovery was unsuccessfull");
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            //print("[Connection]didWriteValueForCharacteristic");
            //print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            
            self.didWriteValue?(characteristic.uuid, nil)
        }
        else {
            print("didWriteValueForCharacteristic,Error = \(error!.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            print("[Connection]didUpdateValueForCharacteristic");
            print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            
            if(characteristic.uuid == ProfileServiceUUID.MCHP_TRCBP_CHAR){
                if let psmValue = characteristic.value?.withUnsafeBytes({$0.load(as: UInt16.self).bigEndian}){
                    print("PSM value = \(psmValue)")
                    L2CapCoCPSM = psmValue
                    TransparentConfig?.SetDeviceSupportProfile(profile: .TRP_TRCBP)
                }
            }
            else{
                //print("didUpdateValueForCharacteristic, uuid = \(characteristic.uuid.uuidString)")

                let result = DIS_Peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
                if(result == nil){
                    self.didUpdateValue?(characteristic.uuid, characteristic.value!, nil)
                }
            }
        }
        else {
            print("didUpdateValueForCharacteristic,Error")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            print("didUpdateNotificationStateForCharacteristic");
            print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            
            if(characteristic.isNotifying) {
                if(characteristic.uuid == ProfileServiceUUID.MCHP_TRANS_RX) {
                    print("p = \(peripheral.identifier.uuidString)")
                    print("Transparent CCCD is enabled!,uuid = \(ProfileServiceUUID.MCHP_TRANS_RX)")

                    self.TransparentConfig?.mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
                    self.TransparentServiceEnabled?(nil)
                    self.TransparentServiceEnabled = nil
                    
                    if(self.DISUpdateValues != nil){
                        GetDeviceInformation()
                    }
                }
            }
        }
        else {
            print("didUpdateNotificationStateForCharacteristic,Error")
            print(characteristic.uuid.uuidString)
        }
    }
    
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        //print("peripheralIsReady = \(peripheral.canSendWriteWithoutResponse)")
    }
    
    // MARK: - ReliableBurstTransmit delegate
    func didSendDataWithCharacteristic(_ transparentDataWriteChar: CBCharacteristic) {
        //print("[ReliableBurstTransmit]didSendDataWithCharacteristic, uuid = \(transparentDataWriteChar.uuid.uuidString)")
        //print("[Connection]ReliableBurstTransmit")
        self.didWriteValue?(transparentDataWriteChar.uuid, nil)
    }
    
    func didWriteDataLength(_ len: Int) {
        
    }
}

