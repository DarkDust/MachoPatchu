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
        }
    }
    
}
