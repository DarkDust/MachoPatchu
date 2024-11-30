//
//  String.swift
//  MachoPatchu
//
//  Created by Marc Haisenko on 2024-11-30.
//

import Foundation
import MachO


extension String {
    
    /// Initialize with a MachO string from a load command.
    init(_ str: lc_str, in slice: UnsafeMutableRawBufferPointer.SubSequence) {
        let stringOffset = Int(str.offset)
        let stringLength = slice.count - stringOffset
        let startIndex = slice.startIndex + stringOffset
        let endIndex = startIndex + stringLength
        let stringSlice = slice[startIndex ..< endIndex]
        self.init(decoding: stringSlice, as: Unicode.UTF8.self)
    }
    
}
