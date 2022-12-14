//
//  BleOTALib.swift
//  BleOTALib
//
//  Created by WSG Software on 30/10/2017.
//  Copyright © 2017 WSG Software. All rights reserved.
//

import Foundation
import CoreBluetooth

typealias OTAConnectionCallback = (OTADataConnection)->Void
typealias OTADataCallback = (CBPeripheral, CBCharacteristic, Data)->Void

protocol OTADataConnection {
    var OTACommandEventCallback: OTADataCallback? {get set}
    func OTAWriteCommand(command: OTA_Command)
    func OTAWriteData(dat: Data)
}

public typealias OTAError = String

enum OTA_Opcode: UInt8 {
    case RFU = 0
    case Response_Code = 0x01
    case Firmware_Update_Request = 0x02
    case Firmware_Update_Start = 0x03
    case Firmware_update_Complete = 0x04
    case Device_Reset_Request = 0x05
}

enum OTA_Result_Code: UInt8 {
    case Success = 0
    case Invalid_State = 0x01
    case Not_Supported = 0x02
    case Operation_Failed = 0x03
    case Invalid_Parameter = 0x04
    case Unspecified_Error = 0x05
}

enum Support_Image_Type: UInt8 {
    case Firmware_Image_Supported = 0x01
    case Metadata_Supported = 0x02
}

enum Firmware_Extended_Feature: UInt8 {
    case Supported_Feature_Mask1 = 0x01
}

struct OTA_Command {
    var opcode: OTA_Opcode = .RFU
    var parameters: [UInt8] = []
    
    init() {}
    
    static func format(ota_cmd: OTA_Command) -> Data {
        var dat = Data()
        dat.append(ota_cmd.opcode.rawValue)
        if ota_cmd.parameters.count != 0{
            dat.append(contentsOf: ota_cmd.parameters)
        }
        return dat
    }
}

struct OTA_Event {
    var response: UInt8 = 0
    var request_opcode: OTA_Opcode = .RFU
    var result_code: UInt8 = 0
    var response_parameters: [UInt8] = []
    
    init() {}
    
    static func format(evnet_data: Data) -> OTA_Event?{
        if(evnet_data.count >= 3){
            var event = OTA_Event()
            let bytes = [UInt8](evnet_data)
        
            if bytes[0] == 0x01{
                event.response = bytes[0]
                event.request_opcode = OTA_Opcode.init(rawValue: bytes[1])!
                event.result_code = bytes[2]
                
                if(evnet_data.count > 3){
                    for i in 0..<(evnet_data.count-3){
                        event.response_parameters.append(bytes[i+3])
                    }
                }
                return event
            }
        }
        return nil
    }
}

struct OTAU_HEADER_FORMAT
{
    var header_version: UInt8 = 0
    var img_dec: UInt8 = 0
    var checksum = [UInt8](repeating: 0, count: 2)
    var flash_img_ID = [UInt8](repeating: 0, count: 4)
    var flash_img_revision = [UInt8](repeating: 0, count: 4)
    var file_type: UInt8 = 0
    var reserved: UInt8 = 0
    var crc_16 = [UInt8](repeating: 0, count: 2)
    init(){}
    
    static func archive(format:OTAU_HEADER_FORMAT) -> Data {
        var fw = format
        var value = [UInt8](repeating: 0, count: 16)
        value[0] = fw.header_version
        value[1] = fw.img_dec
        memcpy(&value[2], &fw.checksum, 2)
        memcpy(&value[4], &fw.flash_img_ID, 4)
        memcpy(&value[8], &fw.flash_img_revision, 4)
        value[12] = fw.file_type
        value[13] = fw.reserved
        memcpy(&value[14], &fw.crc_16, 2)
        let data = Data(bytes: UnsafePointer<UInt8>(&value), count: value.count)
        return data
    }
    
    static func unarchive(data:[UInt8]) -> OTAU_HEADER_FORMAT? {
        var w = OTAU_HEADER_FORMAT()
        w.header_version = data[0]
        w.img_dec = data[1]
        for i in 0..<2{
            w.checksum[i] = data[i+2]
            w.crc_16[i] = data[i+14]
        }
        for i in 0..<4{
            w.flash_img_ID[i] = data[i+4]
            w.flash_img_revision[i] = data[i+8]
        }
        w.file_type = data[12]
        w.reserved = data[13]
        return w
    }
    
    static func getChecksum(format:OTAU_HEADER_FORMAT) -> UInt{
        var fw = format
        var checksum:UInt = 0
        
        checksum += UInt(fw.header_version)
        checksum += UInt(fw.img_dec)
        for i in 0..<2{
            checksum += UInt(fw.crc_16[i])
        }
        for i in 0..<4{
            checksum += UInt(fw.flash_img_ID[i])
            checksum += UInt(fw.flash_img_revision[i])
        }
        checksum += UInt(fw.file_type)
        checksum += UInt(fw.reserved)
        
        return checksum
    }
}


public enum OTA_State: UInt8{
    case Disconnected
    case Idle
    case UpdateRequest
    case UpdateStart
    case ValidationRequest
    case UpdateComplete
    case ResetRequest
}

public enum OTA_ErrorCode: UInt8 {
    case OTA_FeatureNotSupport = 0
    case BLE_ConnectionFail
    case BLE_AbnormalDisconnect
    case BleAdapter_PeripheralNotReady
    case OTA_Command_InvalidState
    case OTA_Command_NotSupported
    case OTA_Command_OperationFailed
    case OTA_Command_InvalidParameter
    case OTA_Command_UnspecifiedError
    case OTA_Data_Result_Error
}

public class OTAManager: NSObject{
    private static var mInstance : OTAManager?
    
    public var otaDelegate : OTALibDelegate?
    
    var bleAdapter : BLEAdapter?
    
    var ImageSize : UInt = 0
    
    //var ImageVersion = [UInt8]()
    
    var UpdateMTU : UInt = 20
    
    var Max_fragmented_Image_Size : UInt16 = 0
    
    //var EncrypedData : UInt8 = 0
    
    var DeviceVersion =  ""
    
    var UpdateState : OTA_State = .Disconnected
    
    var CharOTAControl : CBCharacteristic!
    
    var CharOTAData : CBCharacteristic!
    
    var CharOTAFeature : CBCharacteristic!
    
    var UpdateOffset : UInt = 0
    
    var otaImage = Data()
    
    var progressValue = 0.0
    
    var complete : ((OTAError?) -> Void)?
    
    var DataAckTimer : Timer?
    
    var peripherals: Array<peripheralInfo> = Array()
    
    var time_start: Double = 0

    private var otaPeripheral: OTADataConnection?
    
    var support_image_type: UInt8 = 0
    
    var fw_extended_feature: UInt8 = 0
    
    var otau_header: OTAU_HEADER_FORMAT?
    
    // MARK: - Public API
    
    public class func sharedInstace(peripheral: CBPeripheral? = nil) -> OTAManager {
        if(mInstance == nil) {
            mInstance = OTAManager()
            print("OTAInterface create instance.")
        }
        return mInstance!
    }
    
    public func DestroyInstance(){
        self.bleAdapter?.DestroyInstance()
        bleAdapter = nil
        OTAManager.mInstance = nil
        otau_header = nil
    }
    
    /**
     Scans for BLE peripheral with a timer. If timeout, stop scanning the peripherals

     - parameter scanTimeout: BLE scan time. default is 60 seconds
     - parameter scanConfig: Peripheral scan option
     - returns: None
    */
    public func bleScan(scanTimeout:Int = 60, scanConfig:ScanOption = .Scan){
        print(#function)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
    public func bleDisconnect(){
        print(#function)
        
        bleAdapter?.disconnectPeripheral()
    }
    
    public func GetDeviceName() -> String{
        return (self.bleAdapter?.PeripheralName() ?? "No name")
    }
    
    public func OTA_SetData(imageData: Data, completion: @escaping (OTAError?)-> Void){
        self.complete = completion
        
        var result = false
        var message = ""
        
        var VerifyingSuccess = true
        
        if(imageData.count > 507904 || imageData.count < 0x10){
            VerifyingSuccess = false
        }
        else{

            (result, message) = GetOTAImageInformation(OTAImage: imageData)
            if(!result){
                VerifyingSuccess = false
            }
        }
        
        if(!VerifyingSuccess){
            print("Invalid_OTA_Data")
            self.complete?(message)
            self.complete = nil
            return
        }

        self.otaImage = Data(imageData.subdata(in: 0x10..<imageData.count))
        
        self.ImageSize = UInt(self.otaImage.count)
        print("OTA Image size = \(otaImage.count)")
        
        UpdateRequest()
    }
    
    public func OTA_SetData(format: String, data: Data, version:[UInt8], completion: @escaping (OTAError?)-> Void){
        self.complete = completion
        
        var result = false
        var message = ""
        
        var VerifyingSuccess = true
        
        if(data.count > 507904 || data.count < 512 || version.count != 4){
            VerifyingSuccess = false
        }
        else{
            (result, message) = GetOTAImageInformation(OTAImage: data)
            if(!result){
                VerifyingSuccess = false
            }
        }
        
        if(!VerifyingSuccess){
            print("Invalid_OTA_Data")
            self.complete?(message)
            self.complete = nil
            return
        }

        self.otaImage = Data(data.subdata(in: 0x10..<data.count))
        
        self.ImageSize = UInt(self.otaImage.count)
        print("OTA Image size = \(otaImage.count)")
        
        UpdateRequest()
    }
    
    public func OTA_Start(ota_data: Data? = nil){
        print("OTA Start")

        if UpdateState != .UpdateRequest{
            print("Invalid state. \(UpdateState)")
            return
        }

        UpdateStart()
    }
    
    public func OTA_Stop(){
        if self.UpdateState == .UpdateStart{
            print(#function)
            self.UpdateState = .Idle
        }
    }
    
    public func OTA_Cancel(){
        if(UpdateState == .UpdateRequest){
            print(#function)
            
            UpdateComplete()
            
            UpdateState = .UpdateRequest
        }
    }
    
    // MARK: - Internal
    override init() {
        print("OTAInterface init.")
        
        super.init()
    
        print("Version = \(getCurrentTime())")
        
        if bleAdapter == nil{
            print("bleAdapter is nil")

            otaInit()
        }
    }
    
    deinit {
        print("OTAManager deinit")
    }
    
    func getCurrentTime() -> String {
        let now = Date()
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
        let timeString = outputFormatter.string(from: now)
        return timeString
    }
    
    func otaInit() {
        print(#function)
        
        bleAdapter = BLEAdapter.sharedInstace(option: .Normal)

        bleAdapter?.ConnectionStatusUpdate = { (status, peripheral) in
            if(status != nil){
                print("BLE disconnect.\(status ?? "")")
                if self.UpdateState == .Disconnected{
                    self.otaDelegate?.OperationError?(errorcode: OTA_ErrorCode.BLE_ConnectionFail.rawValue, description: status!)
                }
                else{
                    if(self.UpdateState == .UpdateStart){
                        self.CancelTimer()
                    }
                    
                    if (self.UpdateState == .UpdateRequest) || (self.UpdateState == .UpdateStart) || (self.UpdateState == .Idle){
                        self.otaDelegate?.OperationError?(errorcode: OTA_ErrorCode.BLE_AbnormalDisconnect.rawValue, description: status!)
                    }
                    
                    self.UpdateState = .Disconnected
                }
            }
            else{
                print("Establish BLE connection.")
                
                let ota = OTAPeripheral(peripheral: peripheral){ connection in
                    self.otaPeripheral = connection
                    print("\(connection)")
                }
                print("ota = \(ota)")
                ota.DiscoverOTAService(){error in
                    if(error == nil){
                        print("Discover OTAService success")
                        self.otaPeripheral?.OTACommandEventCallback = { (peripheral , char , data) in
                            if(char.uuid == ProfileServiceUUID.MCHP_OTA_DATA){
                                if(data.count == 1){//OTA data result
                                    //print("OTA data result = \(data[0])")
                                    self.ProcessDataResponse(data: data)
                                }
                            }
                            else if(char.uuid == ProfileServiceUUID.MCHP_OTA_CONTROL) {
                                if let event = OTA_Event.format(evnet_data: data){
                                    self.ProcessOTAEvent(event: event)
                                }
                            }
                            else if(char.uuid == ProfileServiceUUID.MCHP_OTA_FEATURE){
                                print("Read OTA feature, data = \(char.value! as NSData)")
                                let data = [UInt8](char.value!)
                                self.support_image_type = data[0]
                                if data.count > 1 {
                                    self.fw_extended_feature = data[1]
                                }
                            }
                        }
                    }
                }
                
                self.UpdateMTU = UInt((self.bleAdapter?.activePeripheral?.maximumWriteValueLength(for: .withoutResponse))!)
                
                self.otaDelegate?.bleDidConnect?(peripheralName: self.bleAdapter?.PeripheralName() ?? "")
                
                self.UpdateState = .Idle
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
            
            self.otaDelegate?.bleConnecting?(bleScanState: IsScanning, discoveredPeripherals: self.peripherals)
        }
    }
    
    public static func OTAImageHeader(OTAImage:Data) -> (String?, String?){
        print(#function)
        
        var header =  OTAU_HEADER_FORMAT.unarchive(data: [UInt8](OTAImage))
        //let otauH = OTAImage.subdata(in: 0..<0x10)
        
        let flashImage = OTAImage.subdata(in: 0x10..<OTAImage.count)
        print("flashImage bytes = \(flashImage.count)")
        
        //let otauH_Bytes = [UInt8](otauH)
        //let otauH_Bytes = OTAU_HEADER_FORMAT.archive(format: header!)
        //print("otaUHeader bytes = \(otauH_Bytes.count)")
        
        let flashImage_Bytes = [UInt8](flashImage)
        
        /*if(otauH_Bytes[0x00] != 0x01){
            print("OTAU Header version error.\(otauH_Bytes[0x00])")
            return (nil, nil)
        }

        if(otauH_Bytes[0x0c] != 0x01){
            print("OTAU File Type = \(otauH_Bytes[0x0c])")
            return (nil, nil)
        }*/
        
        if(header!.header_version != 0x01 && header!.header_version != 0x02){
            print("OTAU Header version error.\(header!.header_version)")
            return (nil, nil)
        }

        if(header!.file_type != 0x01){
            print("OTAU File Type = \(header!.file_type)")
            return (nil, nil)
        }

        //let imageID = otauH.subdata(in: 0x04..<0x08)
        //print("Firmware image id = \(imageID as NSData)")
        print("Firmware image id = \(header!.flash_img_ID)")
        
        //let version = otauH.subdata(in: 0x08..<0x0C)
        //print("Firmware image version = \(version as NSData)")
        print("Firmware image version = \(header!.flash_img_revision)")
        
        //print("OTAU Checksum = \(otauH_Bytes[0x02]),\(otauH_Bytes[0x03])")
        print("OTAU Checksum = \(header!.checksum)")
        
        var checksum: UInt = 0
        
        for index in 0..<flashImage.count{
            checksum += UInt(flashImage_Bytes[index])
        }
        print("checksumA = \(checksum)")
            
        /*for index in 0..<0x10{
            if(index != 0x02 && index != 0x03){
                checksum += UInt(otauH_Bytes[index])
            }
        }*/
        
        checksum += OTAU_HEADER_FORMAT.getChecksum(format: header!)
        
        print("checksumB = \(checksum),\(checksum&0xffff)")
        checksum &= 0xffff
        
        print("checksumC = \(0xffff-checksum+1)")
        
        //let compareChecksum = (UInt(otauH_Bytes[0x03]) << 8) + UInt(otauH_Bytes[0x02])
        let compareChecksum = (UInt(header!.checksum[0x01]) << 8) + UInt(header!.checksum[0x00])
        print("Compared checksum = \(compareChecksum)")
        
        if(compareChecksum != (0xffff-checksum+1)){
            print("Compare checksum : FAIL")
            return (nil, nil)
        }
        else{
            print("Compare checksum : PASS")
            
            //let id_value = String(format: "0x%02x%02x%02x%02x",otauH_Bytes[0x07],otauH_Bytes[0x06],otauH_Bytes[0x05],otauH_Bytes[0x04])
            let id_value = String(format: "0x%02x%02x%02x%02x",header!.flash_img_ID[3],header!.flash_img_ID[2],header!.flash_img_ID[1],header!.flash_img_ID[0])
            var application = "Unknown"

            let image_id_Dict = [Data([0x01,0x00,0x00,0x9B]): "RNBD451(0x9B000001)", Data([0x02,0x00,0x00,0x9B]): "RNBD450(0x9B000002)",
                              Data([0x03,0x00,0x00,0x9B]): "WBZ451 BLE_UART(0x9B000003)", Data([0x04,0x00,0x00,0x9B]): "WBZ451 BLE_Sensor(0x9B000004)",
                              Data([0x01,0x00,0x00,0x9E]): "RNBD351(0x9E000001)", Data([0x02,0x00,0x00,0x9E]): "RNBD350(0x9E000002)",
                              Data([0x03,0x00,0x00,0x9E]): "WBZ351 BLE_UART(0x9E000003)", Data([0x04,0x00,0x00,0x9E]): "WBZ351 BLE_Sensor(0x9E000004)"]
            
            let id = NSData(bytes: &header!.flash_img_ID, length: header!.flash_img_ID.count)
            
            for(image_id, image_name) in image_id_Dict{
                /*if(imageID as NSData).isEqual(to: image_id){
                    application = image_name
                }*/
                
                if(id).isEqual(to: image_id){
                    application = image_name
                }
            }
            
            if application == "Unknown"{
                application = "Unknown" + "(" + id_value + ")"
            }
            
            //let image_rev = String(format: "%d.%d.%d.%d", otauH_Bytes[0x0b],otauH_Bytes[0x0a],otauH_Bytes[0x09],otauH_Bytes[0x08])
            let image_rev = String(format: "%d.%d.%d.%d", header!.flash_img_revision[0x03],header!.flash_img_revision[0x02],header!.flash_img_revision[0x01],header!.flash_img_revision[0x00])

            return (application, image_rev)
        }
    }
    
    func GetOTAImageInformation(OTAImage:Data) -> (Bool, String){
        print(#function)
        otau_header =  OTAU_HEADER_FORMAT.unarchive(data: [UInt8](OTAImage))
        
        //let otauH = OTAImage.subdata(in: 0..<0x10)
        
        //let otauH_Bytes = [UInt8](otauH)
        //print("otaUHeader bytes = \(otauH_Bytes.count)")
        if otau_header!.header_version != 0x01 && otau_header!.header_version != 0x02{
            print("OTAU Header version error.\(otau_header!.header_version)")
            return (false, "OTAU Header version error")
        }
        /*if(otauH_Bytes[0x00] != 0x01){
            print("OTAU Header version error.\(otauH_Bytes[0x00])")
            return (false, "OTAU Header version error")
        }*/

        if otau_header?.file_type != 0x01{
            print("OTAU File Type = \(String(describing: otau_header?.file_type))")
            return (false, "OTAU File Type error")
        }
        /*if(otauH_Bytes[0x0c] != 0x01){
            print("OTAU File Type = \(otauH_Bytes[0x0c])")
            return (false, "OTAU File Type error")
        }*/
        
        let method = (otau_header?.img_dec == 0x00) ? "Plain" : "AES"
        print("Firmware image decryption method = " + method)
        //EncrypedData = otau_header!.img_dec
        
        /*let method = (otauH_Bytes[0x01] == 0x00) ? "Plain" : "AES"
        print("Firmware image decryption method = " + method)
        EncrypedData = otauH_Bytes[0x01]*/

        print("Firmware image id = \(otau_header!.flash_img_ID)")
        //let imageID = otauH.subdata(in: 0x04..<0x08)
        //print("Firmware image id = \(imageID as NSData)")¸¸¸
        
        print("Firmware image version = \(otau_header!.flash_img_revision)")
        //let version = otauH.subdata(in: 0x08..<0x0C)
        //print("Firmware image version = \(version as NSData)")
        
        print("OTAU Checksum = \(otau_header!.checksum[0]),\(otau_header!.checksum[1]))")
        //print("OTAU Checksum = \(otauH_Bytes[0x02]),\(otauH_Bytes[0x03])")
        
        /*ImageVersion.removeAll()
        ImageVersion.append(otauH_Bytes[0x04])
        ImageVersion.append(otauH_Bytes[0x05])
        ImageVersion.append(otauH_Bytes[0x06])
        ImageVersion.append(otauH_Bytes[0x07])
        ImageVersion.append(otauH_Bytes[0x08])
        ImageVersion.append(otauH_Bytes[0x09])
        ImageVersion.append(otauH_Bytes[0x0a])
        ImageVersion.append(otauH_Bytes[0x0b])*/
        
        print("OTA_SetData. flash image id  = \(otau_header!.flash_img_ID)")
        print("OTA_SetData. flash image rev = \(otau_header!.flash_img_revision)")
        
        return (true, "")
    }
    
    func ProcessOTAEvent(event: OTA_Event){
        print(#function)
        
        if event.result_code == OTA_Result_Code.Success.rawValue{
            switch(event.request_opcode){
                case .RFU:
                    print("RFU")
                case .Response_Code:
                    print("Response_Code")
                case .Firmware_Update_Start:
                    if self.UpdateState == .UpdateStart{
                        print("Firmware_Update_Start")
                        self.UpdateOffset = 0
                        self.progressValue = 0.0
                        self.CancelTimer()
                        print("time = \(self.getCurrentTime())")
                        self.time_start = Date().timeIntervalSince1970
                        self.UpdateData()
                    }
                case .Firmware_update_Complete:
                    if self.UpdateState == .UpdateComplete{
                        print("Firmware_update_Complete")
                        self.ResetRequest()
                        let ota_elapsed_time = Date().timeIntervalSince1970 - self.time_start
                        print("OTA elapsed time = \(ota_elapsed_time),\(String(format: "%.3f", ota_elapsed_time))")
                        print("time = \(self.getCurrentTime())")
                        self.otaDelegate?.OTAProgressUpdate?(state: OTA_State.UpdateComplete.rawValue, value: [100], updateBytes: self.ImageSize, otaTime: String(format: "%.2f s", ota_elapsed_time))
                    }
                case .Device_Reset_Request:
                    print("Device_Reset_Request")
                case .Firmware_Update_Request:
                    print("Firmware_Update_Request. response parameters = \(event.response_parameters)")
                    if event.response_parameters.count == 10{
                        //Max_Fragmented_Image_Size: 2 Octets
                        //Image_Start_index: 4
                        //Current_Firmware_Image_Version: 4
                        if self.UpdateState == .UpdateRequest{
                            self.Max_fragmented_Image_Size = (UInt16(event.response_parameters[1]) << 8) + UInt16(event.response_parameters[0])
                            print("Max_Fragmented_Image_Size = \(self.Max_fragmented_Image_Size)")
                            
                            print("Image start index = " + String(format: "%x%x%x%x", event.response_parameters[5],event.response_parameters[4],event.response_parameters[3],event.response_parameters[2]))
                            
                            print("Image_Version = " + String.init(format: "%d.%d.%d.%d", event.response_parameters[9],event.response_parameters[8],event.response_parameters[7],event.response_parameters[6]))
                            
                            self.DeviceVersion = String(format: "%d.%d.%d.%d", event.response_parameters[9],event.response_parameters[8],event.response_parameters[7],event.response_parameters[6])
                            
                            var mVersion = [UInt8]()
                            //Current version
                            mVersion.append(event.response_parameters[6])
                            mVersion.append(event.response_parameters[7])
                            mVersion.append(event.response_parameters[8])
                            mVersion.append(event.response_parameters[9])
                            //Update version
                            /*mVersion.append(self.ImageVersion[4])
                            mVersion.append(self.ImageVersion[5])
                            mVersion.append(self.ImageVersion[6])
                            mVersion.append(self.ImageVersion[7])*/
                            mVersion.append(self.otau_header!.flash_img_revision[0])
                            mVersion.append(self.otau_header!.flash_img_revision[1])
                            mVersion.append(self.otau_header!.flash_img_revision[2])
                            mVersion.append(self.otau_header!.flash_img_revision[3])
                            
                            self.otaDelegate?.OTAProgressUpdate?(state: self.UpdateState.rawValue, value: mVersion, updateBytes: 0, otaTime: "")
                            if self.complete != nil{
                                self.complete?(nil)
                                self.complete = nil
                            }
                        }
                    }
                    else{
                        print("Firmware_Update_Request: Invalid response data")
                        self.otaDelegate?.OperationError?(errorcode: OTA_ErrorCode.OTA_Command_InvalidParameter.rawValue, description: "OTA command error: " + String(event.request_opcode.rawValue))
                    }
            }
        }
        else{
            print("Error. opcode = \(event.request_opcode), result = \(event.result_code)")
            switch event.result_code {
            case OTA_Result_Code.Invalid_State.rawValue,
            OTA_Result_Code.Not_Supported.rawValue,
            OTA_Result_Code.Operation_Failed.rawValue,
            OTA_Result_Code.Invalid_Parameter.rawValue,
            OTA_Result_Code.Unspecified_Error.rawValue:
                self.otaDelegate?.OperationError?(errorcode: event.result_code+3, description: "OTA command error: " + String(event.request_opcode.rawValue))
            default:
                self.otaDelegate?.OperationError?(errorcode: event.result_code, description: "OTA command error: Unknown")
            }
        }
    }
    
    func ProcessDataResponse(data: Data) {
        self.CancelTimer()

        if(data[0] != OTA_Result_Code.Success.rawValue){
            print("Response error code = \(data[0])")
        }
        else{
            //print("OTA data result = \(data[0])")
            if self.UpdateState == .UpdateStart{
                self.UpdateData()
            }
        }
    }
    
    func ReadOTAFeature() {
        print(#function)
        bleAdapter?.activePeripheral?.readValue(for: CharOTAFeature)
    }
    
    func UpdateRequest() {
        UpdateState = .UpdateRequest
        
        var tmp: UInt8 = 0
        var cmd = OTA_Command()
        cmd.opcode = .Firmware_Update_Request
        //Firmware Image size(4 octets)
        tmp = UInt8(ImageSize & 0x00ff)
        cmd.parameters.append(tmp)
        tmp = UInt8((ImageSize&0x0000ff00) >> 8)
        cmd.parameters.append(tmp)
        tmp = UInt8((ImageSize&0xff0000) >> 16)
        cmd.parameters.append(tmp)
        tmp = UInt8((ImageSize&0xff000000) >> 24)
        cmd.parameters.append(tmp)
        //Firmware Image id(4 octets)
        /*cmd.parameters.append(ImageVersion[0])
        cmd.parameters.append(ImageVersion[1])
        cmd.parameters.append(ImageVersion[2])
        cmd.parameters.append(ImageVersion[3])
        //Firmware Image version(4 octets)
        cmd.parameters.append(ImageVersion[4])
        cmd.parameters.append(ImageVersion[5])
        cmd.parameters.append(ImageVersion[6])
        cmd.parameters.append(ImageVersion[7])*/
        cmd.parameters.append(otau_header!.flash_img_ID[0])
        cmd.parameters.append(otau_header!.flash_img_ID[1])
        cmd.parameters.append(otau_header!.flash_img_ID[2])
        cmd.parameters.append(otau_header!.flash_img_ID[3])
        //Firmware Image version(4 octets)
        cmd.parameters.append(otau_header!.flash_img_revision[0])
        cmd.parameters.append(otau_header!.flash_img_revision[1])
        cmd.parameters.append(otau_header!.flash_img_revision[2])
        cmd.parameters.append(otau_header!.flash_img_revision[3])
        //Firmware Image Encryption
        //cmd.parameters.append(EncrypedData)
        cmd.parameters.append(otau_header!.img_dec)
        
        if ((fw_extended_feature & Firmware_Extended_Feature.Supported_Feature_Mask1.rawValue)  == Firmware_Extended_Feature.Supported_Feature_Mask1.rawValue){
            cmd.parameters.append(otau_header!.checksum[0])
            cmd.parameters.append(otau_header!.checksum[1])
            cmd.parameters.append(otau_header!.file_type)
            cmd.parameters.append(otau_header!.crc_16[0])
            cmd.parameters.append(otau_header!.crc_16[1])
        }
        
        print("Update Request command = \(cmd)")
        
        self.otaPeripheral?.OTAWriteCommand(command: cmd)
    }
    
    func UpdateStart() {
        UpdateState = .UpdateStart
        
        var cmd = OTA_Command()
        cmd.opcode = .Firmware_Update_Start
        cmd.parameters.append(0x01)
        
        print("Update Start command = \(cmd)")

        self.otaPeripheral?.OTAWriteCommand(command: cmd)
    }
    
    func UpdateComplete() {
        UpdateState = .UpdateComplete
        
        var cmd = OTA_Command()
        cmd.opcode = .Firmware_update_Complete
        
        print("Update Complete command = \(cmd)")

        self.otaPeripheral?.OTAWriteCommand(command: cmd)
    }
    
    func ResetRequest() {
        UpdateState = .ResetRequest
        
        var cmd = OTA_Command()
        cmd.opcode = .Device_Reset_Request
        
        print("Reset Request command = \(cmd)")

        self.otaPeripheral?.OTAWriteCommand(command: cmd)
    }
    
    @objc func DataACKTimeout() {
        print("DataACKTimeout handler")
        
        UpdateComplete()
        
        UpdateState = .Idle
        
        CancelTimer()
        
        self.otaDelegate?.OperationError?(errorcode: OTA_ErrorCode.OTA_Data_Result_Error.rawValue, description: "Data ACK timeout(2s)")
    }
    
    func CancelTimer(){
        if(DataAckTimer != nil){
            DataAckTimer?.invalidate()
            DataAckTimer = nil
        }
    }
    
    func InitAckTimer(){
        if(DataAckTimer == nil){
            DataAckTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(OTAManager.DataACKTimeout), userInfo: nil, repeats: false)
        }
    }
    
    func UpdateData(){
        if(UpdateOffset < ImageSize) {
            var len : UInt = 0
            var tr_len : UInt = 0
            
            let segment_len = (ImageSize - UpdateOffset) >= UInt(Max_fragmented_Image_Size) ? UInt(Max_fragmented_Image_Size) : (ImageSize - UpdateOffset)
            
            while(len < segment_len){
                
                if UpdateState == .Idle{
                    print("Update data:break")
                    break
                }
                
                if(segment_len == UInt(Max_fragmented_Image_Size)) {
                    tr_len = (UInt(Max_fragmented_Image_Size) - len) >= UpdateMTU ? UpdateMTU : (UInt(Max_fragmented_Image_Size) - len)
                    
                    if((segment_len%UpdateMTU) != 0){
                        if(tr_len < UpdateMTU){
                            InitAckTimer()
                        }
                    }
                }
                else {
                    tr_len = (ImageSize - (UpdateOffset+len)) >= UpdateMTU ? UpdateMTU : (ImageSize - (UpdateOffset+len))
                    
                    if(tr_len < UpdateMTU){
                        InitAckTimer()
                    }
                }
                
                let dat = (otaImage as NSData).subdata(with: NSMakeRange(Int(len)+Int(UpdateOffset), Int(tr_len)))
                
                self.otaPeripheral?.OTAWriteData(dat: dat)
                
                len += tr_len
            }
            
            UpdateOffset += segment_len
            
            if Double(UpdateOffset*100/ImageSize) > progressValue {
                progressValue = Double(UpdateOffset*100/ImageSize)
                
                print("\(UInt8(progressValue))")
                
                let ota_elapsed_time = Date().timeIntervalSince1970 - self.time_start
                
                otaDelegate?.OTAProgressUpdate?(state: self.UpdateState.rawValue, value: [UInt8(progressValue)], updateBytes: UpdateOffset, otaTime: String(format: "%.2f s", ota_elapsed_time))
            }
        }
        else {
            print("OTA Update : done")
            UpdateComplete()
        }
    }
}
