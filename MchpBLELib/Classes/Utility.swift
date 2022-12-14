//
//  Utility.swift
//  MchpBLELib
//
//  Created by WSG Software on 2022/10/14.
//

import Foundation

class Utility{
    static func getCurrentTime() -> String {
        let now = Date()
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
        let timeString = outputFormatter.string(from: now)
        return timeString
    }
}
