//
//  ParserError.swift
//  MachoPatchu
//
//  Created by Marc Haisenko on 2024-11-30.
//

import Foundation

/// Parser errors.
enum ParserError: Error {
    /// The file is corrupt, offsets or sizes are beyond the file's boundaries.
    case fileTooSmall
    
    /// File is not a Mach-O file.
    case invalidMagic
    
    /// 32-bit targets are not supported.
    case unsupported32bit
    
    /// Some library paths to patch were not found.
    case librariesNotFound([String])
}


extension ParserError: CustomStringConvertible {
    
    public
    var description: String {
        switch self {
        case .fileTooSmall:
            return "File is corrupt, offsets or sizes are beyond the file's boundaries."
            
        case .invalidMagic:
            return "File is not a Mach-O file."
            
        case .unsupported32bit:
            return "32-bit targets are not supported."
            
        case .librariesNotFound(let libraries):
            if libraries.count == 1 {
                return "Library path was not found in Mach-O file: \(libraries.first!)"
            } else {
                return "Library paths were not found in Mach-O file: "
                    + libraries.joined(separator: ", ")
            }
        }
    }
    
}
