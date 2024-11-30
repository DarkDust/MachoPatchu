//
//  MachOParser.swift
//  MachoPatchu
//
//  Created by Marc Haisenko on 2024-11-29.
//

import Foundation
import MachO


/// Type of the MachO file.
private
enum FileType {
    /// Plain 64-bit MachO file.
    case plain
    
    /// Fat (multi-architecture) 32-bit MachO file.
    case fat32bit
    
    /// Fat (multi-architecture) 64-bit MachO file.
    case fat64bit
}


struct MachoOParser {
    
    /// The file data.
    let data: Data
    
    /// Designated initializer.
    init(data: Data) {
        self.data = data
    }
    
}


extension MachoOParser {
    
    /// Parse and process the file.
    func parse() throws(ParserError) {
        do {
            var data = self.data
            try data.withUnsafeMutableBytes {
                (pointer) throws /* (ParserError) */ in
                // See https://github.com/swiftlang/swift/issues/77880
                
                try enumerateArchitectures(pointer, handler: parseLoadCommands)
            }
        } catch let error as ParserError {
            throw error
        } catch {
            preconditionFailure("Invalid error thrown: \(error)")
        }
    }
    
}


private
extension MachoOParser {
    
    /// Parse the magic number to determine the type of file to deal with.
    func parseMagic(_ pointer: UnsafeMutableRawBufferPointer) throws(ParserError) -> FileType {
        guard pointer.count >= MemoryLayout<UInt32>.size else {
            throw .fileTooSmall
        }
        guard let magic = pointer.baseAddress?.load(as: UInt32.self) else {
            throw .invalidMagic
        }
        
        switch magic {
        case MH_MAGIC, MH_CIGAM:
            throw .unsupported32bit
            
        case MH_MAGIC_64, MH_CIGAM_64:
            return .plain
            
        case FAT_MAGIC, FAT_CIGAM:
            return .fat32bit
            
        case FAT_MAGIC_64, FAT_CIGAM_64:
            return .fat64bit
            
        default:
            throw .invalidMagic
        }
    }
    
    
    /// Parse the header and enumerate each architecture in the file.
    func enumerateArchitectures(
        _ pointer: UnsafeMutableRawBufferPointer,
        handler: (UnsafeMutableRawBufferPointer) throws(ParserError) -> Void
    ) throws(ParserError) {
        switch try parseMagic(pointer) {
        case .plain:
            // It's a plain MachO file, can parse it directly.
            try handler(pointer)
            
        case .fat32bit:
            try enumerateArchitectures32bit(pointer, handler: handler)
            
        case .fat64bit:
            try enumerateArchitectures64bit(pointer, handler: handler)
        }
    }
    
    
    func enumerateArchitectures32bit(
        _ pointer: UnsafeMutableRawBufferPointer,
        handler: (UnsafeMutableRawBufferPointer) throws(ParserError) -> Void
    ) throws(ParserError) {
        let headerSize = MemoryLayout<fat_header>.size
        guard pointer.count >= headerSize, let baseAddress = pointer.baseAddress else {
            throw .fileTooSmall
        }
        
        let fatHeader = baseAddress.load(as: fat_header.self)
        let count: UInt32
        let needsSwap = fatHeader.magic == FAT_CIGAM
        if needsSwap {
            count = fatHeader.nfat_arch.byteSwapped
        } else {
            count = fatHeader.nfat_arch
        }
        
        print("\(count) architectures (32 bit fat)")
        let archsSize = Int(count) * MemoryLayout<fat_arch>.size
        guard pointer.count >= headerSize + archsSize else {
            throw .fileTooSmall
        }
        
        let archsSlice = pointer[headerSize ..< headerSize + archsSize]
        try archsSlice.withMemoryRebound(to: fat_arch.self) {
            (archs) throws(ParserError) in
            print("Iterating \(archs.count) archs")
            for arch in archs {
                let offset: UInt32
                let size: UInt32
                if needsSwap {
                    offset = arch.offset.byteSwapped
                    size = arch.size.byteSwapped
                } else {
                    offset = arch.offset
                    size = arch.size
                }
                
                guard pointer.count >= offset + size else {
                    throw .fileTooSmall
                }
                
                let magic = pointer[Int(offset) ..< Int(offset) + MemoryLayout<UInt32>.size]
                    .load(as: UInt32.self)
                switch magic {
                case MH_MAGIC, MH_CIGAM:
                    throw .unsupported32bit
                    
                case MH_MAGIC_64, MH_CIGAM_64:
                    let rebased = UnsafeMutableRawBufferPointer(
                        rebasing: pointer[Int(offset) ..< Int(offset) + Int(size)])
                    try handler(rebased)
                    
                default:
                    throw .invalidMagic
                }
            }
        }
    }
    
    
    func enumerateArchitectures64bit(
        _ pointer: UnsafeMutableRawBufferPointer,
        handler: (UnsafeMutableRawBufferPointer) throws(ParserError) -> Void
    ) throws(ParserError) {
        let headerSize = MemoryLayout<fat_header>.size
        guard pointer.count >= headerSize, let baseAddress = pointer.baseAddress else {
            throw .fileTooSmall
        }
        
        let fatHeader = baseAddress.load(as: fat_header.self)
        let count: UInt32
        let needsSwap = fatHeader.magic == FAT_CIGAM_64
        if needsSwap {
            count = fatHeader.nfat_arch.byteSwapped
        } else {
            count = fatHeader.nfat_arch
        }
        
        print("\(count) architectures (64 bit fat)")
        let archsSize = Int(count) * MemoryLayout<fat_arch_64>.size
        guard pointer.count >= headerSize + archsSize else {
            throw .fileTooSmall
        }
        
        let archsSlice = pointer[headerSize ..< headerSize + archsSize]
        try archsSlice.withMemoryRebound(to: fat_arch_64.self) {
            (archs) throws(ParserError) in
            print("Iterating \(archs.count) archs")
            for arch in archs {
                let offset: UInt64
                let size: UInt64
                if needsSwap {
                    offset = arch.offset.byteSwapped
                    size = arch.size.byteSwapped
                } else {
                    offset = arch.offset
                    size = arch.size
                }
                
                guard pointer.count >= offset + size else {
                    throw .fileTooSmall
                }
                
                let magic = pointer[Int(offset) ..< Int(offset) + MemoryLayout<UInt32>.size]
                    .load(as: UInt32.self)
                switch magic {
                case MH_MAGIC, MH_CIGAM:
                    throw .unsupported32bit
                    
                case MH_MAGIC_64, MH_CIGAM_64:
                    precondition(size <= UInt64(Int.max), "Mach object too large")
                    let rebased = UnsafeMutableRawBufferPointer(
                        rebasing: pointer[Int(offset) ..< Int(offset) + Int(size)])
                    try handler(rebased)
                    
                default:
                    throw .invalidMagic
                }
            }
        }
    }
    
    
    /// Parse the load commands of a Mach object.
    /// Only 64-bit Mach objects are supported.
    func parseLoadCommands(_ machObjectPointer: UnsafeMutableRawBufferPointer) throws(ParserError) {
        guard
            machObjectPointer.count >= MemoryLayout<mach_header_64>.size,
            let baseAddress = machObjectPointer.baseAddress
        else {
            throw .fileTooSmall
        }
        
        let machHeader = baseAddress.load(as: mach_header_64.self)
        let machHeaderSize = MemoryLayout<mach_header_64>.size
        
        let ncmds: UInt32
        let sizeofcmds: UInt32
        let cpuType: Int32
        let needsSwap = machHeader.magic == MH_CIGAM_64
        if needsSwap {
            ncmds = machHeader.ncmds.byteSwapped
            sizeofcmds = machHeader.sizeofcmds.byteSwapped
            cpuType = machHeader.cputype.byteSwapped
        } else {
            ncmds = machHeader.ncmds
            sizeofcmds = machHeader.sizeofcmds
            cpuType = machHeader.cputype
        }
        
        print("Architecture: \(nameForCPUType(cpuType))")
        print("\(ncmds) commands")
        print("\(sizeofcmds) bytes for all commands")
        
        let requiredSize = machHeaderSize + Int(sizeofcmds)
        if machObjectPointer.count < requiredSize {
            throw .fileTooSmall
        }
        
        var offset = machHeaderSize
        var accumulatedCommandSizes: UInt32 = 0
        let loadCommandSize = MemoryLayout<load_command>.size
        for _ in 0 ..< Int(ncmds) {
            let loadCommand = machObjectPointer[offset ..< offset + loadCommandSize]
                .load(as: load_command.self)
            let cmd: UInt32
            let cmdsize: UInt32
            if needsSwap {
                cmd = loadCommand.cmd.byteSwapped
                cmdsize = loadCommand.cmdsize.byteSwapped
            } else {
                cmd = loadCommand.cmd
                cmdsize = loadCommand.cmdsize
            }
            
            assert(offset + Int(cmdsize) <= machObjectPointer.count)
            let commandSlice = machObjectPointer[offset ..< offset + Int(cmdsize)]
            
            switch cmd {
            case UInt32(LC_UUID):
                assert(cmdsize == MemoryLayout<uuid_command>.size)
                let uuidCommand = commandSlice.load(as: uuid_command.self)
                print("UUID: \(UUID(uuid: uuidCommand.uuid))")
                
            case UInt32(LC_LOAD_DYLIB):
                assert(cmdsize >= MemoryLayout<dylib_command>.size)
                let dylibCommand = commandSlice.load(as: dylib_command.self)
                let name = String(dylibCommand.dylib.name, in: commandSlice)
                print("Load dynamic library: '\(name)'")
                
            case UInt32(LC_LOAD_WEAK_DYLIB):
                assert(cmdsize >= MemoryLayout<dylib_command>.size)
                let dylibCommand = commandSlice.load(as: dylib_command.self)
                let name = String(dylibCommand.dylib.name, in: commandSlice)
                print("Load weak dynamic library: '\(name)'")
                
            case UInt32(LC_LAZY_LOAD_DYLIB):
                print("Lazy load dynamic library")
                
            default:
                break
            }
            
            accumulatedCommandSizes += cmdsize
            offset += Int(cmdsize)
        }
        
        assert(sizeofcmds == accumulatedCommandSizes)
    }
    
    
    func nameForCPUType(_ rawCPUType: Int32) -> String {
        let cpuType = cpu_type_t(rawCPUType)
        switch cpuType {
        case CPU_TYPE_X86: return "x86_32"
        case CPU_TYPE_X86_64: return "x86_64"
        case CPU_TYPE_ARM: return "arm"
        case CPU_TYPE_ARM64: return "arm64"
        case CPU_TYPE_ARM64_32: return "arm64_32"
        default: return "unknown (\(rawCPUType))"
        }
    }
    
}
