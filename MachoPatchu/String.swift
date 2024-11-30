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
    static func from(
        _ str: lc_str,
        in slice: Slice<UnsafeMutableRawBufferPointer>
    ) throws(ParserError) -> (String, Slice<UnsafeMutableRawBufferPointer>) {
        let stringOffset = Int(str.offset)
        let stringLength = slice.count - stringOffset
        let startIndex = slice.startIndex + stringOffset
        
        // As far as I know, the strings are always null-terminated.
        let endIndex: Int = slice[startIndex...].firstIndex(where: { $0 == 0x00 })
            ?? startIndex + stringLength
        let stringSlice = slice[startIndex ..< endIndex]
        return (String(decoding: stringSlice, as: Unicode.UTF8.self), stringSlice)
    }
    
}
