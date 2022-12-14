//
//  bleUART.swift
//  BleUARTLib
//
//  Created by WSG Software on 2021/5/6.
//

import Foundation
import CoreBluetooth

typealias BLEUARTConnectionCallback = (bleUARTPeripheralDelegate)->Void

typealias FileName = String

typealias CharacteristicUUID = String

public typealias deviceUUID = String

public typealias deviceName = String

public typealias deviceRSSI = NSNumber

public typealias bleUartError = String

protocol bleUARTPeripheralDelegate {
    
    var didWriteValue: ((Any, bleUartError?)->Void)? {get set}
    var didUpdateValue: ((Any, Data, bleUartError?)->Void)? {get set}
    
    func WriteValue(value: Data, IsCommand: Bool)
    func WriteValueToCharacteristic(ServiceUUID: CBUUID, CharUUID: CBUUID, value: Data)
}

extension Date {
    var millisecondsSince1970: Int64 {
        Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}



class BleUARTImpl{
    var RemoteCommandDelegate : RemoteCommandModeDelegate?
    var delegate: bleUARTImplDelegate?
    var peripheralDelegate: bleUARTPeripheralDelegate?
    var bleUart: BLEUARTPeripheral?
    var bleUartCommand = BLE_UART_Command()
    
    var TaskUARTCallback: ((bleUartError?) -> Void)?
    
    var BleUartMode: BLE_UART_OP_Mode! = BLE_UART_OP_Mode(rawValue: 4){
        didSet {
            print("BleUartMode didChange.\(BleUartMode)")
        }
    }
    
    var Profile: bleUARTProfile = .TRP
    var TxDataSize = 0
    var RxDataSize = 0
    var TxBuffer = Data()
    var TxFragementSize: Int = 0
    var TxBytes: Int = 0
    var RxBytes: Int = 0
    var Checksum: UInt8 = 0
    var Response_Checksum: UInt8 = 0
    var LastNumberHighByte: UInt8 = 0  //Fixed pattern
    var LastNumberLowByte: UInt8 = 0
    var RxBuffer = Data()
    var CancelTransmission: Bool = false
    var fileURL: URL?
    var fileURLs = Dictionary<String,URL>()
    var TransmissionComplete: Timer?
    var TransmissionCounter: Int = 0
    var DeviceBLEUARTSupport: UInt8 = 0x0f
    var throughputUpdateSize: Int = 0
    var TimeTxStart: Int64 = 0
    var TimeRxStart: Int64 = 0
    
    init(peripheral: BLEUARTPeripheral, delegate: bleUARTPeripheralDelegate, testPattern: Dictionary<String,URL>){
        self.bleUart = peripheral
        self.peripheralDelegate = delegate
        self.fileURLs = testPattern
    }
    
    deinit {
        print("BleUARTImpl deinit")
    }
    
    func BLEUARTInitial(){
        bleUart?.didWriteValue = {
            (PeripheralResponseData, Error) in
            if(Error == nil){
                if PeripheralResponseData is CBUUID{
                    self.BLEUARTDataResponseHandler(CharUUID: PeripheralResponseData as! CBUUID)
                }
                else if PeripheralResponseData is Int{
                    self.TxBytes += (PeripheralResponseData as! Int)
                    print("[TRCBP]TxBytes = \(self.TxBytes)")
                    
                    if(!self.CancelTransmission){
                        self.Transmit_throughput(direction: true, time1: self.TimeTxStart, time2: Date().millisecondsSince1970, data_size: self.TxBytes)
                        
                        if(self.TxBytes == self.TxDataSize){
                            print("[TRCBP]Transmission Complete.\(self.TxDataSize)")
                            self.TxBytes = 0
                            self.TxBuffer.removeAll()
                            if(self.BleUartMode != .loopback){
                                self.TransmissionCompletion(error: nil)
                            }
                        }
                    }
                }
            }
        }
        
        bleUart?.didUpdateValue = {(PeripheralResponseData, Data, Error) in
            if self.RemoteCommandDelegate != nil{
                self.RemoteCommandDelegate?.didUpdateValue(CharUUID: PeripheralResponseData as! CBUUID, data: Data, error: Error)
            }
            else{
                if(Error == nil){
                    if PeripheralResponseData is CBUUID{
                        self.BLEUARTDataResponseHandler(CharUUID: PeripheralResponseData as! CBUUID, data: Data)
                    }
                    else if PeripheralResponseData is Int{
                        if(self.RxBytes == 0){
                            let mtu = Data.count
                            if(mtu != 0){
                                self.throughputUpdateSize = mtu*(1000/mtu+1)
                                print("TRCBP Rx,throughputUpdateSize = \(self.throughputUpdateSize)")
                            }
                        }
                        
                        if(!Data.isEmpty){
                            self.ProcessRxData(data: Data)
                        }
                    }
                }
            }
        }

        bleUart?.DISUpdateValues = { (deviceUUID, DIS_Information) in
            print("\nDeviceID = \(deviceUUID)")
            print("\nDIS information = \(DIS_Information)")
        }
        
        if(throughputUpdateSize == 0){
            let mtu = bleUart?.TransparentConfig?.mtu
            throughputUpdateSize = mtu!*(1000/mtu!+1)
            print("throughputUpdateSize = \(throughputUpdateSize)")
        }
    }
    
    func CompareFile() {
        if(self.BleUartMode != .checksum && self.BleUartMode != .fixed_pattern){
            print("CompareFile \(self.RxBytes),\(self.RxBuffer.count)")
            var url: URL?
            var fileName = ""
            
            if(!fileURLs.isEmpty){
                switch self.RxBytes {
                case 0..<601:
                    fileName = "1k.txt"
                    url = fileURLs[fileName]
                case 601..<10009:
                    fileName = "10k.txt"
                    url = fileURLs[fileName]
                case 10009..<100009:
                    fileName = "100k.txt"
                    url = fileURLs[fileName]
                case 100009..<200005:
                    fileName = "200k.txt"
                    url = fileURLs[fileName]
                case 200005..<500005:
                    fileName = "500k.txt"
                    url = fileURLs[fileName]
                default:
                    fileName = "100k.txt"
                    url = fileURLs[fileName]
                }
            }
            else{
                print("Error.urlFiles is empty")
                if(!self.RxBuffer.isEmpty){
                    if(fileURL == nil){
                        self.delegate?.DidUpdateData(deviceID: (bleUart?.peripheral?.identifier.uuidString)!, data: self.RxBuffer)
                    }
                    self.RxBuffer.removeAll()
                    self.RxDataSize = 0
                }
            }
            
            if(fileURL != nil){
                do{
                    if(url == nil){print("Error.")}
                    
                    let file = try FileHandle(forReadingFrom: url!)
                    
                    let compare = file.readDataToEndOfFile()
                    
                    print("[URL file]compare data")
                    
                    if(self.RxBuffer == compare){
                        if self.BleUartMode != .go_through_uart{
                            print("Loopback:PASS")
                            TransmissionCompletion(error: nil)
                        }
                        else{
                            print("UART UpLink:PASS")
                            if Profile == .TRP{
                                delegate?.DidUpdateStatus(status: "TRP, " + fileName + " ,UART UpLink: PASS")
                            }else{
                                delegate?.DidUpdateStatus(status: "TRCBP, " + fileName + " ,UART UpLink: PASS")
                            }
                        
                        }
                    }
                    else{
                        let str = String(format: "Compare data fail,data length:tx=%d,rx=%d", self.TxBytes,self.RxBytes)
                        
                        if self.BleUartMode != .go_through_uart{
                            TransmissionCompletion(error: str)
                        }else{
                            if Profile == .TRP{
                                delegate?.DidUpdateStatus(status: "TRP, " + fileName + " ,UART UpLink: FAIL")
                            }else{
                                delegate?.DidUpdateStatus(status: "TRCBP, " + fileName + " ,UART UpLink: FAIL")
                            }
                        }
                    }
                }
                catch{
                    print("Can't get file handle")
                }
            }
            else{
                //print("No url file to compare data")
                
                self.delegate?.DidUpdateData(deviceID: (bleUart?.peripheral?.identifier.uuidString)!, data: self.RxBuffer)
                
                if(BleUartMode == .loopback){
                    print("RawData loopback mode: complete")
                    TransmissionCompletion(error: nil)
                }
                 
                self.RxBuffer.removeAll()
            }
        }
        
        if(BleUartMode == .loopback){
            self.TxBytes = 0
        }
        self.RxBytes = 0
        self.RxBuffer.removeAll()
    }
    
    func ChangeProfile(profile : bleUARTProfile) -> Bool?{
        if(bleUart?.TransparentConfig?.deviceProfile == .TRP_TRCBP){
            if(profile != self.Profile){
                self.Profile = profile
                print("Changed Profile = \(profile)")
                bleUart?.DataPathDidChanged(profile: profile)
                return true
            }
        }
        return nil
    }
    
    public func bleUART_Tx(profile: bleUARTProfile, fileurl: URL? = nil, mode: BLE_UART_OP_Mode, data: Data? = nil, completion: @escaping (bleUartError?)-> Void){
        
        let bitMask = NSDecimalNumber(decimal: pow(2, Int(BleUartMode.rawValue)-1)).uint8Value
        if((DeviceBLEUARTSupport & bitMask) == 0){
            print("Device not supported.\(BleUartMode.rawValue)")
            completion("Device not supported.")
            return
        }
        
        self.CancelTransmission = false
        self.TaskUARTCallback = completion
        self.TxBuffer.removeAll()
        self.RxBuffer.removeAll()
        self.TxDataSize = 0
        self.RxDataSize = 0
        
        if(fileurl != nil){
            self.fileURL = fileurl
            do{
                let file = try FileHandle(forReadingFrom: fileurl!)
        
                if self.TxBuffer.isEmpty{
                    if mode != .fixed_pattern{
                        self.TxBuffer.append(file.readDataToEndOfFile())
                    }
                }
            }
            catch {
                completion("Can't open file")
                return
            }
        }
        else{
            self.fileURL = nil
        }
        
        if(self.TxBuffer.isEmpty){
            if(data != nil){
                if mode != .fixed_pattern{
                    self.TxBuffer.append(data!)
                }
            }
        }
        
        print("data length = \(self.TxBuffer.count)")
        
        TxDataSize = self.TxBuffer.count
        
        self.TxFragementSize = (bleUart?.TransparentConfig?.mtu)!
        
        print("\(self.TxFragementSize),\(TxDataSize)")
        
        self.BleUartMode = mode
        
        if mode == .loopback{
            self.RxBytes = 0
            RxDataSize = TxBuffer.count
            BLEUARTCommand(groupCommand: .loopback_mode, subCommand: .transmission_start)
        }
        else if mode == .checksum{
            Checksum = CalculateChecksum(dat: self.TxBuffer)
            BLEUARTCommand(groupCommand: .checksum_mode, subCommand: .transmission_start)
        }
        else if mode == .go_through_uart{
            BLEUARTCommand(groupCommand: .uart_mode, subCommand: .transmission_start)
        }
        else if mode == .fixed_pattern{
            self.RxBytes = 0
            self.RxBuffer.removeAll()
            BLEUARTCommand(groupCommand: .fixedPattern_mode, subCommand: .transmission_start)
        }
    }
    
    func BLEUARTCommand(groupCommand: BLE_UART_Group_Command, subCommand: BLE_UART_Sub_Command, extraData: [UInt8] = []){
        bleUartCommand = BLE_UART_Command()
        bleUartCommand.group_command = groupCommand
        bleUartCommand.sub_command = subCommand.rawValue
        if(!(extraData.isEmpty)){
            bleUartCommand.command_parameters = extraData
        }
        
        let dat = BLE_UART_Command.write_data(format: bleUartCommand)
        
        peripheralDelegate?.WriteValue(value: dat, IsCommand: true)
    }
    
    func BLEUARTUpdateState(group_id: BLE_UART_Group_Command, sub_id: UInt8){
        print("[BLEUARTUpdateState] group id = \(group_id), sub id  = \(sub_id)")
        if(group_id == .checksum_mode){
            if(sub_id == BLE_UART_Sub_Command.transmission_start.rawValue){
                if self.Profile == .TRP{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x01])
                }
                else{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x02])
                }
            }
            if(sub_id == 0x02){//APP receive checksum
                if(self.BleUartMode != .go_through_uart){
                    //self.bleAdapter?.BLE_Data_Transmission_End()
                    if self.Profile == .TRP{
                        //BLEUARTCommand(dataPath: .GATT, groupCommand: .control, subCommand: .transmission_end, extraData: [])
                    }
                    else{
                        //BLEUARTCommand(dataPath: .L2CAP, groupCommand: .control, subCommand: .transmission_end, extraData: [])
                    }
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_end)
                }
            }
        }
        else if(group_id == .loopback_mode && sub_id == BLE_UART_Sub_Command.transmission_start.rawValue){
            if self.BleUartMode == .loopback{
                if self.Profile == .TRP{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x01])
                }
                else{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x02])
                }
            }
        }
        else if(group_id == .uart_mode && sub_id == BLE_UART_Sub_Command.transmission_start.rawValue){
            if self.Profile == .TRP{
                BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x01])
            }
            else{
                BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x02])
            }
        }
        
        if(group_id == .fixedPattern_mode){
            if(sub_id == BLE_UART_Sub_Command.transmission_start.rawValue){
                print("Enable Fixed pattern mode")
                
                if self.Profile == .TRP{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x01])
                }
                else{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_path, extraData: [0x02])
                }
            }
        }
        else if(group_id == .control){
            if(sub_id == BLE_UART_Sub_Command.transmission_data_length.rawValue){
                BLEUARTCommand(groupCommand: .control, subCommand: .transmission_start)
            }
            else if(sub_id == BLE_UART_Sub_Command.transmission_start.rawValue){
                if self.BleUartMode != .fixed_pattern{
                    TransmissionStart()
                }
            }
            else if(sub_id == BLE_UART_Sub_Command.transmission_end.rawValue){
                if(self.Checksum != 0 && self.BleUartMode == .checksum) {
                    SendChecksum()
                    
                    if(Checksum == Response_Checksum){
                        print("Compare checksum : PASS")
                        
                        self.TaskUARTCallback?(nil)
                    }
                    else{
                        print("Compare checksum : FAIL")
                        let str = String(format: "Checksum fail,Tx data length = %d", self.TxDataSize)
                        
                        self.TaskUARTCallback?(str)
                    }
                }
                else if self.BleUartMode == .fixed_pattern{
                    //print("[Fixed pattern] Data End!.\(getCurrentTime())")
                }
            }
            else if(sub_id == BLE_UART_Sub_Command.transmission_path.rawValue){
                if(self.BleUartMode == .checksum || self.BleUartMode == .loopback){
                    let len = UInt32(TxDataSize)
                    var dat = [UInt8](repeating: 0, count: 4)
                    dat[0] = UInt8((len & 0xFF000000) >> 24)
                    dat[1] = UInt8((len & 0x00FF0000) >> 16)
                    dat[2] = UInt8((len & 0x0000FF00) >> 8)
                    dat[3] = UInt8(len & 0x000000FF)
                    
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_data_length, extraData: dat)
                }
                else if self.BleUartMode == .fixed_pattern{
                    BLEUARTCommand(groupCommand: .control, subCommand: .transmission_start)
                }
                else{
                    //UART mode
                    TransmissionStart()
                }
            }
        }
        else if(group_id == .ble_parameter_update){
            if(sub_id == 0){
                print("Connection parameter update : Pass")

                self.TaskUARTCallback?(nil)
            }
            else{
                print("Connection parameter update : Fail")

                self.TaskUARTCallback?("Failed to update connection parameters")
            }

            self.TaskUARTCallback = nil
        }
    }
    
    func BLEUARTDataResponseHandler(CharUUID: CBUUID, data: Data = Data()){
        if(CharUUID == ProfileServiceUUID.MCHP_TRANS_TX) {
            FragementDataTransmit()
        }
        else if(CharUUID == ProfileServiceUUID.MCHP_TRANS_RX) {
            if(!(data.isEmpty)){
                ProcessRxData(data: data)
            }
            else{
                FragementDataTransmit()
            }
        }
        else if(CharUUID == ProfileServiceUUID.MCHP_TRANS_CTRL || CharUUID == ProfileServiceUUID.MCHP_TRCBP_CTRL){
            if(data.isEmpty){
                let group_id = bleUartCommand.group_command
                let sub_id = bleUartCommand.sub_command
                if(group_id != .default_value){
                    //bleUartCommand = BLE_UART_Command()
                    bleUartCommand.group_command = .default_value
                    bleUartCommand.sub_command = 0
                    print("Event complete.group_id = \(group_id),sub_id = \(sub_id)")
                    BLEUARTUpdateState(group_id: group_id, sub_id: sub_id)
                }
            }
            else{
                //print("bleUART:didUpdateValueFor. data = \(data as NSData)")
                let ble_uart_event = BLE_UART_Command.Received_Event(receive: data)
                
                if(ble_uart_event != nil){
                    ProcessBLEUARTCommand(responseData: ble_uart_event)
                }
                else{
                    //print("DecodeReliableBurstTransmitEvent. \(data as NSData)")
                    bleUart?.TransparentConfig?.transmit?.decodeReliableBurstTransmitEvent(eventData: data as NSData)
                }
            }
        }
    }
    
    func TransmissionStart(){
        print(#function)
        
        if(self.TxBuffer.isEmpty){
            print("No output data")
            return
        }
        
        let time = Date()
        self.TimeTxStart = Int64((time.timeIntervalSince1970 * 1000).rounded())
        //print("time = " + Utility.getCurrentTime())
        //print("Tx start time = " + Utility.getCurrentTime())
        
        if(self.Profile == .TRCBP) {
            self.TxBytes = 0
            
            peripheralDelegate?.WriteValue(value: TxBuffer, IsCommand: false)
        }
        else {
            self.TxBytes = 0
            
            if self.TxDataSize > self.TxFragementSize{
                let output = self.TxBuffer.subdata(in: 0..<self.TxFragementSize)
            
                peripheralDelegate?.WriteValue(value: output, IsCommand: false)
            }
            else{
                peripheralDelegate?.WriteValue(value: self.TxBuffer, IsCommand: false)
            }
        }
    }
    
    func TransmissionStop(){
        if BleUartMode != .fixed_pattern{
            print("\(Profile),TransmissionStop")
            
            self.CancelTransmission = true

            if Profile == .TRCBP{
                self.bleUart?.L2CapCoC?.stop()
            }
            
            CancelTimer()
            self.TxBuffer.removeAll()
            TransmissionCompletion(error: "Data transfer was canceled!")
        }
    }
    
    func FragementDataTransmit(){
        if(self.TxBytes == 0) {
            if(self.TxBuffer.count <= self.TxFragementSize){
                self.TxBytes += self.TxBuffer.count
                self.TxBuffer.removeAll()
            }
            else {
                self.TxBytes += self.TxFragementSize
                self.TxBuffer = self.TxBuffer.advanced(by: self.TxFragementSize)
            }
        }
        
        if(self.TxBuffer.count > 0){
            if(self.CancelTransmission){
                return
            }
            
            if ((self.TxDataSize - self.TxBytes) >= self.TxFragementSize){
                
                let outData = self.TxBuffer.subdata(in: 0..<self.TxFragementSize)
            
                peripheralDelegate?.WriteValue(value: outData, IsCommand: false)
                
                self.TxBuffer = self.TxBuffer.advanced(by: self.TxFragementSize)
                
                self.TxBytes += self.TxFragementSize
            }
            else{
                peripheralDelegate?.WriteValue(value: self.TxBuffer, IsCommand: false)
                
                self.TxBytes += self.TxBuffer.count
            }

            //print("TxBytes = \(self.TxBytes)")
            ThroughputUpdate(Tx: true)
            
            if self.TxBytes == self.TxDataSize{
                print("Clear TxBuffer. \(self.fileURL)")
                self.TxBuffer.removeAll()
            }
        }
        else{
            if !self.CancelTransmission{
                self.TxBytes = 0
            }
            print("GATT_Write_Complete.\(self.TxBytes)")
            
            if self.BleUartMode == .go_through_uart{
                if(!self.CancelTransmission){
                    print("UART DownLink:Complete")
                    self.TxBytes = 0
                    TransmissionCompletion(error: nil)
                }
            }
        }
    }
    
    func CancelTimer(){
        if(TransmissionComplete != nil){
            print(#function)
            TransmissionComplete?.invalidate()
            TransmissionComplete = nil
        }
    }
    
    @objc func TransmissionTimeout(){
        TransmissionCounter -= 1
        if(TransmissionCounter == 0){
            print(#function)
            
            //print("time:" + Utility.getCurrentTime())
        
            CancelTimer()
            
            if BleUartMode == .fixed_pattern{
                FixedPatternCompare()
            }
            else{
                if BleUartMode == .go_through_uart{
                    //UART Uplink
                    if Profile == .TRP{
                        ThroughputUpdate(mode: .go_through_uart, Tx: false, timeout: Transmission_timeout.GATT_timeout)
                    }
                    else{
                        ThroughputUpdate(mode: .go_through_uart, Tx: false, timeout: Transmission_timeout.L2CAP_timeout)
                    }
                }
                CompareFile()
            }
        }
    }
    
    func TransmissionCompletion(error: bleUartError?){
        //print("TransmissionCompletion, uuid = \(bleUart?.peripheral.identifier.uuidString ?? "")")
        self.TaskUARTCallback?(error)
        self.TaskUARTCallback = nil
    }
    
    func SetBLEUARTMode(new: BLE_UART_OP_Mode){
        if new != BleUartMode{
            print(#function)
            BleUartMode = new
            
            if(BleUartMode == .go_through_uart){
                BLEUARTCommand(groupCommand: .uart_mode, subCommand: .transmission_start)
            }
        }
    }
    
    func ProcessBLEUARTCommand(responseData: BLE_UART_Command?){
        let groupID = responseData?.group_command
        let subcommandID = responseData?.sub_command
        print("bleUARTEvent.\(groupID!),\(subcommandID!)")
        
        if(self.CancelTransmission){
            return
        }
        
        if(groupID == .ble_parameter_update){
            if(responseData?.command_parameters.count == 1){
                print("[ble parameter update] result code = \(responseData?.command_parameters[0] ?? 0)")
                let result = responseData?.command_parameters[0]
                if(result == 0){
                    self.TaskUARTCallback?(nil)
                }
                else{
                    self.TaskUARTCallback?("result code = " + String(result!))
                }
            }
        }
        
        if(subcommandID == BLE_UART_Sub_Command.error_response.rawValue){
            let bitMask = NSDecimalNumber(decimal: pow(2, Int(BleUartMode.rawValue)-1)).uint8Value
            DeviceBLEUARTSupport &= ~(bitMask)
        }
        
        if(groupID == .checksum_mode && subcommandID == Checksum_Sub_Command.checksum_value.rawValue){
            self.Response_Checksum = (responseData?.command_parameters[0])!
            print("Receive checksum = \(self.Response_Checksum)")
            BLEUARTCommand(groupCommand: .control, subCommand: .transmission_end)
        }
        
        if(groupID == .control && subcommandID == BLE_UART_Sub_Command.transmission_end.rawValue){
            if(BleUartMode == .fixed_pattern){
                print("[Fixed pattern] transmission complete")
                ThroughputUpdate(Tx: false)
            }
        }
        
        if(groupID == .fixedPattern_mode && subcommandID == BLE_UART_Sub_Command.transmission_data_length.rawValue){
            if(!(responseData?.command_parameters.isEmpty)!){
                LastNumberHighByte = (responseData?.command_parameters[0])!
                LastNumberLowByte = (responseData?.command_parameters[1])!
                print("[Fixed pattern]Last number = \(LastNumberHighByte),\(LastNumberLowByte)")
            }
        }
    }
    
    func ProcessRxData(data: Data){
        if(self.CancelTransmission){
            return
        }
        
        if(TransmissionComplete == nil){
            TransmissionCounter = Transmission_timeout.GATT_timeout/500
            TransmissionComplete = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(BleUARTImpl.TransmissionTimeout), userInfo: nil, repeats: true)
            print("Create timer")
            
            let time = Date()
            self.TimeRxStart = Int64(time.timeIntervalSince1970 * 1000)
            //print("Rx start time = " + Utility.getCurrentTime())
        }
        else{
            TransmissionCounter = Transmission_timeout.GATT_timeout/500
        }
        
        self.RxBytes += data.count
        
        self.RxBuffer.append(data)
        
        print("RxBytes = \(self.RxBytes)")
        ThroughputUpdate(Tx: false)
        
        if(BleUartMode == .loopback){
            if(RxBytes == RxDataSize){
                CancelTimer()
                CompareFile()
            }
        }
    }
    
    func CancelConnection(){
        print(#function)
        self.peripheralDelegate = nil
        CancelTimer()
        print("\(self.bleUart?.TransparentConfig?.ActiveDataPath)")
        if(self.bleUart?.TransparentConfig?.ActiveDataPath == .L2CAP){
            self.bleUart?.DisconnectL2CapCoc()
        }
        //self.bleUart?.BLEUARTConnectionHandler = nil
        self.bleUart?.TransparentServiceEnabled = nil
        self.bleUart?.TransparentConfig = nil
        
        self.bleUart = nil
    }
    
    func GetDeviceSupportProfile() -> bleUARTProfile?{
        return bleUart?.TransparentConfig?.deviceProfile
    }
    
    func BleParameterUpdate(data: Data, completion: @escaping (bleUartError?)-> Void){
        var bleParameters = Data()
        bleParameters.append(0x80)
        bleParameters.append(BLE_UART_Group_Command.ble_parameter_update.rawValue)
        bleParameters.append(0x01)
        bleParameters.append(data)
        
        print("BleParameterUpdate. dat = \(bleParameters as NSData)")
        
        self.TaskUARTCallback = completion
        
        peripheralDelegate?.WriteValueToCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_CTRL, value: bleParameters)
    }
    
    func SendChecksum(){
        var command = BLE_UART_Command()
        command.group_command = .checksum_mode
        command.sub_command = Checksum_Sub_Command.checksum_value.rawValue
        command.command_parameters = [Checksum]
        
        let data = BLE_UART_Command.write_data(format: command)
        peripheralDelegate?.WriteValue(value: data, IsCommand: true)
        print(#function)
    }
    
    func CalculateChecksum(dat: Data) -> UInt8{
        var sum : UInt32 = 0
        
        let bytes : NSData = dat as NSData
        var buf = [UInt8](repeating:0, count:bytes.length)
        bytes.getBytes(&buf, length: bytes.length)
        
        print(#function)
        //print("dat = \(dat as NSData)")
        print("data length = \(dat.count)")
        
        for i in 0..<dat.count {
            sum += UInt32(buf[i])
        }
        print("sum = \(sum)")
        
        var bigEndian = sum.bigEndian
        let count = MemoryLayout<UInt32>.size
        //print("UInt32.size = \(count)")
        let bytePtr = withUnsafePointer(to: &bigEndian){
            $0.withMemoryRebound(to: UInt8.self, capacity: count){
                       UnsafeBufferPointer(start: $0, count: count)
                
            }
        }
        let byteArray = Array(bytePtr)
        //let checksum = ~(byteArray[3]) + 1
        
        //print("BLE_UART_Data_Checksum = \(checksum)")
        print("TransmitData checksum = \(byteArray[3])")
        
        return byteArray[3]
    }
    
    func SendFixedPatternLastNumber(high_byte: UInt8, Low_byte: UInt8){
        var command = BLE_UART_Command()
        command.group_command = .fixedPattern_mode
        command.sub_command = BLE_UART_Sub_Command.transmission_data_length.rawValue
        command.command_parameters.append(high_byte)
        command.command_parameters.append(Low_byte)
        
        let data = BLE_UART_Command.write_data(format: command)
        peripheralDelegate?.WriteValue(value: data, IsCommand: true)
        print(#function)
    }
    
    func FixedPatternCompare(){
        
        if(self.RxBuffer.count != 0 && (self.RxBuffer.count % 2) == 0){
            ThroughputUpdate(mode: .fixed_pattern, Tx: false)
            
            var Compare_data = Data()
            
            var index: Int = 0

            for _ in 0..<(self.RxBuffer.count/2){
                if(index != 0 &&  (index % 65536) == 0){
                    let block = index/65536
                    index -= (65536 * block)
                }
                
                let u16: UInt16 = UInt16(index)
                var big_endian = u16.bigEndian
                let u16_data = Data(bytes: &(big_endian), count: MemoryLayout<UInt16>.size)
                Compare_data.append(u16_data)
                index += 1
            }
            
            print("Compare_data.count = \(Compare_data.count)")
            
            let array = [UInt8](self.RxBuffer)
            print("Receive last number = \(array[Compare_data.count-2]),\(array[Compare_data.count-1])")
            
            let high_byte = array[Compare_data.count-2]
            let low_byte = array[Compare_data.count-1]
            
            SendFixedPatternLastNumber(high_byte: high_byte, Low_byte: low_byte)
            
            if(self.RxBuffer == Compare_data){
                //self.AppLog.insertText("Last number = " + String(format: "0x%X%X", high_byte, low_byte) + "\n")
                
                if(high_byte == LastNumberHighByte && low_byte == LastNumberLowByte){
                    TransmissionCompletion(error: nil)
                }
                else{
                    print("[Fixed pattern] Last number is not correct!")
                    TransmissionCompletion(error: "Last number compare fail")
                }
            }
            else{
                print("[Fixed pattern] data error!,\(self.RxBuffer.count)")
                //print("Receive data = \(self.RxBuffer as NSData)")
                TransmissionCompletion(error: "Data compare fail")
            }
        }
    }
    
    func ThroughputUpdate(mode: BLE_UART_OP_Mode? = nil, Tx: Bool, timeout: Int = 0){
        
        if(Tx){
            if((TxBytes >= throughputUpdateSize) && ((TxBytes % throughputUpdateSize) == 0)){
                Transmit_throughput(direction: true, time1: TimeTxStart, time2: Date().millisecondsSince1970, data_size: TxBytes)
            }
            else if(TxBytes == TxDataSize){
                Transmit_throughput(direction: true, time1: TimeTxStart, time2: Date().millisecondsSince1970, data_size: TxBytes)
            }
        }
        else{//Rx
            if mode == nil{
                if((RxBytes >= throughputUpdateSize) && ((RxBytes % throughputUpdateSize) == 0)){
                    Transmit_throughput(direction: false, time1: TimeRxStart, time2: Date().millisecondsSince1970, data_size: RxBytes)
                }
                else{
                    //Loopback
                    if(RxBytes == RxDataSize && BleUartMode == .loopback){
                        Transmit_throughput(direction: false, time1: TimeRxStart, time2: Date().millisecondsSince1970, data_size: RxBytes)
                    }
                }
            }
            else{
                if mode == .fixed_pattern || mode == .go_through_uart{
                    if timeout != 0{
                        Transmit_throughput(direction: false, time1: TimeRxStart, time2: Date().millisecondsSince1970, data_size: RxBytes, timeout: timeout)
                    }
                    else{
                        Transmit_throughput(direction: false, time1: TimeRxStart, time2: Date().millisecondsSince1970, data_size: RxBytes)
                    }
                }
            }
        }
    }
    
    func Transmit_throughput(direction: Bool, time1: Int64, time2: Int64, data_size: Int, timeout:Int = 0){
        
        if(CancelTransmission){
            return
        }
        
        let elapsed_time_ms = time2 - time1
        print("elapsed = \(elapsed_time_ms)")
        
        if timeout != 0{
            if(elapsed_time_ms > timeout){
                let new_elapsed_time = Int(elapsed_time_ms) - timeout
                print("elapsed - timeout = \(new_elapsed_time)")
                let throughput = Double(data_size) / Double(new_elapsed_time)
                
                if(direction) {
                    self.delegate?.ThroughputUpdate(Downlink: String(format: "Downlink: %d bytes, %.2f KB/s", TxBytes, throughput), Uplink: nil)
                }
                else{
                    self.delegate?.ThroughputUpdate(Downlink: nil, Uplink: String(format: "Uplink: %d bytes, %.2f KB/s", RxBytes, throughput))
                }
            }
        }
        else{
            let throughput = Double(data_size) / Double(elapsed_time_ms)
            if(direction) {
                self.delegate?.ThroughputUpdate(Downlink: String(format: "Downlink: %d bytes, %.2f KB/s", TxBytes, throughput), Uplink: nil)
            }
            else{
                self.delegate?.ThroughputUpdate(Downlink: nil, Uplink: String(format: "Uplink: %d bytes, %.2f KB/s", RxBytes, throughput))
            }
        }
    }
}

struct BLE_UART_Command {
    var vendor_op: UInt8 = 0x80
    var group_command: BLE_UART_Group_Command = .default_value
    var sub_command: UInt8 = 0
    var command_parameters: [UInt8] = []
    
    init() {}
    
    static func write_data(format: BLE_UART_Command) -> Data{
        let ble_uart_comd = format
        var dat = Data()
        dat.append(ble_uart_comd.vendor_op)
        dat.append(ble_uart_comd.group_command.rawValue)
        dat.append(ble_uart_comd.sub_command)
        if ble_uart_comd.command_parameters.count != 0{
            dat.append(contentsOf: ble_uart_comd.command_parameters)
        }
        return dat
    }
    
    static func Received_Event(receive: Data) -> BLE_UART_Command?{
        if(receive.count >= 3){
            var event = BLE_UART_Command()
            let bytes = [UInt8](receive)
            
            if(bytes[0] == 0x80){
                print("ble uart parse event = \(receive as NSData)")
                
                event.vendor_op = bytes[0]
                event.group_command = BLE_UART_Group_Command(rawValue: bytes[1])!
                event.sub_command = bytes[2]
            
                if(receive.count > 3){
                    for i in 0..<(receive.count-3){
                        event.command_parameters.append(bytes[i+3])
                    }
                }
                return event
            }
            return nil
        }
        return nil
    }
}

enum BLE_UART_Group_Command: UInt8 {
    case default_value = 0
    case checksum_mode = 0x01
    case loopback_mode = 0x02
    case fixedPattern_mode = 0x03
    case uart_mode = 0x04
    case control = 0x05
    case ble_parameter_update = 0x06
    case changeProfile = 0x07
}

enum Checksum_Sub_Command: UInt8 {
    case transmission_end = 0x00
    case transmission_start = 0x01
    case checksum_value = 0x02
}

enum BLE_UART_Sub_Command: UInt8 {
    case transmission_end = 0x00
    case transmission_start = 0x01
    case transmission_data_length = 0x02
    case transmission_path = 0x04
    case error_response = 0x03
    case default_value = 0xff
}

///BLE UART Command Opcode
public enum BLE_UART_OP_Mode: UInt8 {
    ///APP sends data to the device. After the transmission is completed, checksum value will be sent to the device for data comparison
    case checksum = 1
    ///APP sends data to the device. The device sends the received data back to the APP
    case loopback = 2
    ///Device sends fixed data pattern to the APP
    case fixed_pattern = 3
    ///The device sends the data received from the APP to the UART port, and vice versa
    case go_through_uart = 4
}

enum PeripheralDataPath: UInt8 {
    case GATT = 0x01
    case L2CAP = 0x02
}

public struct Transmission_timeout {
    public static let GATT_timeout = 3000
    public static let L2CAP_timeout = 2000
}

public enum bleUARTProfile {
    case TRP
    case TRCBP
    case TRP_TRCBP
}

protocol bleUARTImplDelegate {
    func ThroughputUpdate(Downlink: String?, Uplink: String?)
    func DidUpdateData(deviceID: deviceUUID, data: Data)
    func DidUpdateStatus(status:String)
}

//Remote command mode
protocol RemoteCommandModeDelegate{
    func didUpdateValue(CharUUID:CBUUID, data:Data, error:bleUartError?)
}

public class bleUART: NSObject, bleUARTImplDelegate , RemoteCommandModeDelegate{
    
    public var delegate : bleUARTDelegate?
    
    var TaskUARTCallback: ((bleUartError?) -> Void)?
    
    var fileURLs = Dictionary<FileName,URL>()
    
    var bleAdapter: BLEAdapter?
    
    var peripherals: Array<peripheralInfo> = Array()
        
    private static var mInstance: bleUART?
    
    var BleUARTLink = Dictionary<deviceUUID,BleUARTImpl?>()
    
    var remoteControlMode:Bool = false
    
    func bleUARTManagerInit(){
        
        bleAdapter?.ConnectionStatusUpdate = { (error, peripheral) in
            if(error != nil){
                if(!self.BleUARTLink.isEmpty){
                    self.BleUARTLink[peripheral.identifier.uuidString]?!.CancelConnection()
                    self.BleUARTLink[peripheral.identifier.uuidString] = nil
                    print("Disconnected! Remove peripheral. \(self.BleUARTLink.count) ")
                    self.delegate?.bleDidDisconnect?(error: error!)
                }
            }
            else{
                print("Establish BLE connection complete!")

                var delegate : bleUARTPeripheralDelegate?
                var bleUart : BLEUARTPeripheral?
                bleUart = BLEUARTPeripheral(peripheral: peripheral){ connection in
                    print("connection = \(connection).")
                    delegate = connection
                }
                
                bleUart!.DiscoverBLEServices(){error in
                    if(error == nil){
                        print("[BLE UART] DiscoverBLEServices.\(peripheral.identifier.uuidString)")
                        print("\(bleUart)")
                        
                        let BleUartDataFlowControl = BleUARTImpl(peripheral: bleUart!, delegate: delegate!, testPattern: self.fileURLs)
                        BleUartDataFlowControl.delegate = self
                        BleUartDataFlowControl.BLEUARTInitial()
                        self.BleUARTLink[peripheral.identifier.uuidString] = BleUartDataFlowControl
                        print("Establish one BLEUartConnection.\(self.BleUARTLink.count)")
                        self.delegate?.bleDidConnect?(peripheralName: self.bleAdapter?.PeripheralName() ?? "")
                        //delegate = nil
                        //bleUart = nil
                    }
                    else{
                        print("Failed to discover BLE Services.")
                    }
                }
            }
        }
        
        bleAdapter?.BLE_didDiscoverUpdateState = {(IsScanning) in
            let deviceInfo = self.bleAdapter?.GetPeripheralNameRSSIList()
            if(!self.peripherals.isEmpty){
                self.peripherals.removeAll()
            }
            for (name, rssi) in deviceInfo!{
                self.peripherals.append((name , rssi))
            }
            
            self.delegate?.bleConnecting?(bleScanState: IsScanning, discoveredPeripherals: self.peripherals)
        }
    }
    
    // MARK: - Public API
    
    public class func sharedInstace(option : CentralOption) -> bleUART {
        if(mInstance == nil) {
            mInstance = bleUART(option: option)
            print("bleUART create instance. option = \(option)")
        }
        return mInstance!
    }
    
    public init(option: CentralOption) {
        print("bleUART init.")
        super.init()
        
        if self.bleAdapter == nil{
            print("bleAdapter is nil")

            bleAdapter = BLEAdapter.sharedInstace(option: option)
            
            bleUARTManagerInit()
            
            #if STAGED
                print("BleUART-Framework-Staged")
            #endif
        }
    }
    
    deinit {
        print("bleUART deinit")
    }
    
    public func bleUARTtest(){
        #if DEBUG
        print("bleUART framework: \(Utility.getCurrentTime)")
        #endif
    }
    
    public func DestroyInstance(){
        self.bleAdapter?.DestroyInstance()
        bleAdapter = nil
        bleUART.mInstance = nil
    }
    
    public func ImportBLEUARTTestFile(filename: String?, fileURL: URL?){
        if(filename != nil && fileURL != nil){

            fileURLs[filename!] = fileURL
            
            if(BleUARTLink.count == 1 && filename == "100k.txt"){
                let bleUARTConnect = BleUARTLink.first?.value
                if bleUARTConnect?.fileURL == nil{
                    bleUARTConnect?.fileURL = fileURL
                    print("BurstMode...")
                    print("Initial bleUART test file:100k.txt")
                }
                bleUARTConnect?.fileURLs = fileURLs
                //print("test pattern = \(bleUARTConnect?.fileURLs)")
            }
        }
        else{
            if(BleUARTLink.count == 1){
                let bleUARTConnect = BleUARTLink.first?.value
                bleUARTConnect?.fileURL = nil
                print("TextMode...")
            }
        }
    }
    
    public func bleStopScan() -> Bool{
        if((self.bleAdapter?.centralManager?.isScanning) != nil){
            //print(#function)
            let state = self.bleAdapter?.centralManager?.isScanning
            //if(state!){
            //    self.bleAdapter?.centralManager?.stopScan()
            //}
            if(state! == false){
                print("bleStopScan. isScanning = false")
                self.bleAdapter?.DestroyInstance()
                self.bleAdapter = nil
                self.TaskUARTCallback = nil
                self.delegate = nil
                bleUART.mInstance = nil
                return true
            }
        }
        return false
    }
    
    /**
     Scans for BLE peripheral with a timer. If timeout, stop scanning the peripherals

     - parameter scanTimeout: BLE scan time. default is 60 seconds
     - parameter scanConfig: Peripheral scan option
     - returns: None
    */
    public func bleScan(scanTimeout:Int = 60, scanConfig:ScanOption = .Scan, filter:[FilterOption:Any] = [:]){
        print(#function)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if(!filter.isEmpty){
                self.bleAdapter?.SetFilter(filter: filter)
            }
            
            self.bleAdapter?.findAllBLEPeripherals(Double(scanTimeout), scanOption: scanConfig)
        }
    }
    
    /**
     Connect to a peripheral

     - parameter device_id: The uuid string of peripheral to which the central is attempting to connect
     - returns: None
    */
    public func bleConnect(deviceUUID: String = "", deviceName: String = ""){
        print(#function)
        
        if(deviceUUID != ""){
            bleAdapter?.ConnectPeripheral(peripheral_uuid: deviceUUID)
        }
        else{
            if(deviceName != ""){
                bleAdapter?.ConnectPeripheral(peripheral_name: deviceName)
            }
        }
    }
    
    /**
     Cancel  an  active connection to a peripheral

     - returns: None
    */
    public func bleDisconnect(peripheralUUID: String = ""){
        print(#function)
        
        if(BleUARTLink.count == 1){
            bleAdapter?.disconnectPeripheral()
        }
        else{
            if(peripheralUUID != ""){
                
            }
        }
    }
    
    /**
     BLE UART transmit data

     - parameter profile: ble profile data path
     - parameter mode: ble uart operation mode
     - parameter data: data to be send
     - parameters:
        - completion: completion handler is called with the execution result and an optional error
    */
    public func TransmitData(peripheralUUID: String = "", profile: bleUARTProfile, mode: BLE_UART_OP_Mode, data: Data, completion: @escaping (bleUartError?)-> Void){
        
        if(!BleUARTLink.isEmpty){
            if(peripheralUUID == "" && BleUARTLink.count == 1){
                let bleUARTConnect = BleUARTLink.first?.value
                
                self.TaskUARTCallback = completion
                
                bleUARTConnect?.fileURLs = fileURLs
                
                bleUARTConnect?.bleUART_Tx(profile: profile, mode: mode, data: data, completion: {error in
                    if(error == nil){
                        print("bleUARTTask is done")
                        self.TaskUARTCallback?(nil)
                    }
                    else{
                        print("error = \(error ?? "")")
                        self.TaskUARTCallback?(error)
                    }
                    self.TaskUARTCallback = nil
                })
            }
            else{
                self.TaskUARTCallback = completion
                
                if let bleUARTConnect = BleUARTLink[peripheralUUID]{
                    //print("connection = \(bleUARTConnect)")
                    
                    bleUARTConnect?.bleUART_Tx(profile: profile, mode: mode, data: data, completion: {error in
                        if(error == nil){
                            print("bleUARTTask is done")
                            self.TaskUARTCallback?(nil)
                        }
                        else{
                            print("error = \(error ?? "")")
                            self.TaskUARTCallback?(error)
                        }
                        self.TaskUARTCallback = nil
                    })
                }
            }
        }else{
            completion(nil)
        }
    }
    
    public func BurstTransmit(peripheralUUID: String = "", profile: bleUARTProfile, mode: BLE_UART_OP_Mode, fileurl: URL, completion: @escaping (bleUartError?)-> Void){
        
        if(!BleUARTLink.isEmpty){
            do{
                print("bleUART.bleUART_Tx.URL = \(fileurl)")
                
                let file = try FileHandle(forReadingFrom: fileurl)
                    
                let dat = file.readDataToEndOfFile()
                
                print("dat.count = \(dat.count).\(fileurl.lastPathComponent)")
                
                if(peripheralUUID == "" && BleUARTLink.count == 1){
                    let bleUARTConnect = BleUARTLink.first?.value
                    
                    self.TaskUARTCallback = completion

                    bleUARTConnect?.fileURLs = fileURLs
                    
                    bleUARTConnect?.bleUART_Tx(profile: profile, fileurl: fileurl, mode: mode, completion: { error in
                        if(error == nil){
                            print("bleUARTTask is done")
                            self.TaskUARTCallback?(nil)
                        }
                        else{
                            print("error = \(error ?? "")")
                            self.TaskUARTCallback?(error)
                        }
                    })
                    return
                }
                else{
                    if let bleUARTConnect = BleUARTLink[peripheralUUID]{
                        
                        self.TaskUARTCallback = completion
                        
                        print("bleUARTConnect = \(bleUARTConnect)")
                        print(peripheralUUID)
                        
                        bleUARTConnect?.bleUART_Tx(profile: profile, fileurl: fileurl, mode: mode, completion: {error in
                            if(error == nil){
                                print("bleUARTTask is done")
                                self.TaskUARTCallback?(nil)
                            }
                            else{
                                print("error = \(error ?? "")")
                                self.TaskUARTCallback?(error)
                            }
                        })
                        return
                    }
                }
            }
            catch{
                print("Can't get the file from URL")
            }
        }
        completion(nil)
    }
    
    public func CancelTransmission(peripheralUUID: String = ""){
        if(BleUARTLink.count == 1){
            let bleUARTConnect = BleUARTLink.first?.value
            bleUARTConnect?.TransmissionStop()
        }
        else{
            if(peripheralUUID != ""){
                
            }
        }
    }
    
    /**
     Set BLE UART profile

     - parameter profile: ble profile data path
     - parameters:
        - completion: completion handler is called with the execution result and an optional error
    */
    public func ChangeProfile(peripheralUUID: String = "", profile: bleUARTProfile, completion: @escaping (bleUartError?)-> Void){
        
        if(BleUARTLink.count == 1){
            let bleUARTConnect = BleUARTLink.first?.value
            let ret = bleUARTConnect?.ChangeProfile(profile: profile)
                
            if let result = ret{
                if(result){
                    completion(nil)
                }
            }
            else{
                completion("Failed to change profile")
            }
        }
        else{
            if(peripheralUUID != ""){
                completion(nil)
            }
        }
    }
    
    public func GetDeviceName(peripheralUUID: String = "") -> String?{
        if(BleUARTLink.count == 1){
            return (self.bleAdapter?.PeripheralName() ?? "No name")
        }
        else{
            if(peripheralUUID != ""){
                return "MultiLinkTest"
            }
        }
        return nil
    }
    
    public func GetSetCharacteristicWriteType(peripheralUUID: String = "", writeType: CBCharacteristicWriteType? = nil) -> CBCharacteristicWriteType?{

        if(BleUARTLink.count == 1){
            //SingleLink
            let bleUARTConnect = BleUARTLink.first?.value
            
            if(writeType != nil){
                if(bleUARTConnect?.bleUart?.TransparentConfig?.WriteType.rawValue != writeType!.rawValue){
                    bleUARTConnect?.bleUart?.TransparentConfig?.SetWriteType(NewType: writeType!)
                    return writeType!
                }
            }
            else{
                return bleUARTConnect?.bleUart?.TransparentConfig?.WriteType
            }
        }
        else{
            if(peripheralUUID != ""){
                return nil
            }
        }
        return nil
    }
    
    public func GetBleUartProfile(peripheralUUID: String = "") -> (bleUARTProfile?, bleUARTProfile?) {
        if(BleUARTLink.count == 1){
            let bleUARTConnect = BleUARTLink.first?.value
            let deviceProfile = bleUARTConnect?.GetDeviceSupportProfile()
            return (bleUARTConnect?.Profile, deviceProfile)
        }
        else{
            if(peripheralUUID != ""){
                return (.TRP, .TRP)
            }
        }
        return (nil, nil)
    }
    
    public func SetBLEUARTMode(peripheralUUID: String = "", mode: BLE_UART_OP_Mode) -> Bool?{
        if(BleUARTLink.count == 1){
            let bleUARTConnect = BleUARTLink.first?.value
            bleUARTConnect?.SetBLEUARTMode(new: mode)
            return true
        }
        else{
            if(peripheralUUID != ""){
                print(#function)
                if let bleUARTConnect = BleUARTLink[peripheralUUID]{
                    bleUARTConnect?.SetBLEUARTMode(new: mode)
                    return true
                }
            }
        }
        return nil
    }
    
    public func ConnectionParameterUpdate(peripheralUUID: String = "", parameters: Data, completion: @escaping (bleUartError?)-> Void){
        if(BleUARTLink.isEmpty){
            completion(nil)
        }
        
        if(BleUARTLink.count == 1){
            
            self.TaskUARTCallback = completion
            
            let bleUARTConnect = BleUARTLink.first?.value
            bleUARTConnect?.BleParameterUpdate(data: parameters, completion: {error in
                if(error == nil){
                    self.TaskUARTCallback?(nil)
                }
                else{
                    print("error = \(error ?? "")")
                    self.TaskUARTCallback?(error)
                }
            })
        }
        else{
            if(peripheralUUID != ""){
                
            }
        }
    }

    public func GetDeviceInformation(peripheralUUID: String = "") -> [DIS_Index:String]{
        if(BleUARTLink.count == 1){
            let bleUARTConnect = BleUARTLink.first?.value
            let dat = bleUARTConnect?.bleUart?.DIS.DISArray
            if((dat != nil) && (!dat!.isEmpty)){
                return dat!
            }
        }
        else{
            if(peripheralUUID != ""){
                print(#function)
            }
        }
        return [:]
    }
    
    public func GetIsSupportRemoteControl() -> Bool{
        let bleUARTConnect = BleUARTLink.first?.value
        return ((bleUARTConnect?.bleUart?.isSupportRemoteComtrolMode) != nil) //.isSupportRemoteComtrolMode
    }
    
    public func enableRemoteControlMode(pin:Data){
        var data = pin
        data.insert(0x59, at: 0)
        let bleUARTConnect = BleUARTLink.first?.value
        bleUARTConnect?.RemoteCommandDelegate = self
        bleUARTConnect?.bleUart?.WriteValueToCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_CTRL, value: data)
        remoteControlMode = false
    }
    
    public func disableRemoteControlMode(){
        var data:Data = Data()
        data.insert(0x46, at: 0)
        let bleUARTConnect = BleUARTLink.first?.value
        bleUARTConnect?.RemoteCommandDelegate = nil
        bleUARTConnect?.bleUart?.WriteValueToCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_CTRL, value: data)
        //remoteControlMode = false
    }
    
    public func sendRemoteCrotrolCommand(command:Data){
        let bleUARTConnect = BleUARTLink.first?.value
        var data = command
        data.append(0x0D)
        bleUARTConnect?.bleUart?.WriteValueToCharacteristic(ServiceUUID: ProfileServiceUUID.MCHP_PROPRIETARY_SERVICE, CharUUID: ProfileServiceUUID.MCHP_TRANS_TX, value: data)
        self.delegate?.DidWriteRawData?(data: data)
    }
    
    // MARK: - bleUARTImpl Delegate
    func DidUpdateStatus(status:String) {
        print("DidUpdateStatus. \(status)")
        self.delegate?.bleDidUpdateStatus?(status: status)
    }
    
    func ThroughputUpdate(Downlink: String?, Uplink: String?) {
        self.delegate?.bleThroughputUpdate?(Downlink: Downlink, Uplink: Uplink)
    }
    
    func DidUpdateData(deviceID: deviceUUID, data: Data) {
        self.delegate?.DidUpdateRawData?(data: data)
    }
    
    // MARK: - Remote command mode
    func didUpdateValue(CharUUID:CBUUID, data:Data, error:bleUartError?) {
        print("Remote Control delegate - didUpdateValue")
        if !remoteControlMode{
            let str = String(data: data, encoding: .utf8)
            if ((str?.contains("RMT>")) != nil){
                remoteControlMode = true
                self.delegate?.didEnableRemoteControlMode?()
            }
        }
        self.delegate?.DidUpdateRawData?(data: data)
        
    }
}
