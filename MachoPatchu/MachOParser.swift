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


struct MachOParser {
    
    /// The file data.
    let data: Data
    
    /// Lookup dictionary: the library paths to replace.
    let replace: [String: String]
    
    let verbose: Bool
    
    /// Designated initializer.
    init(data: Data, replace: [(String, String)], verbose: Bool) {
        self.data = data
        self.replace = replace.reduce(into: [:], { $0[$1.0] = $1.1 })
        self.verbose = verbose
    }
    
}


extension MachOParser {
    
    /// Result of the parsing process.
    struct Result {
        /// The patched data.
        let data: Data
        
        /// Whether the Mach-O file is signed. The signature is now invalid.
        let hasSignature: Bool
    }
    
    
    /// Parse and process the file.
    func parse() throws(ParserError) -> Result {
        do {
            var data = self.data
            var context = Context()
            try data.withUnsafeMutableBytes {
                (pointer) throws /* (ParserError) */ in
                // See https://github.com/swiftlang/swift/issues/77880
                
                try enumerateArchitectures(pointer, context: &context, handler: parseLoadCommands)
            }
            
            if context.didReplace.count != self.replace.count {
                let missing = self.replace.keys.filter { !context.didReplace.contains($0) }
                throw ParserError.librariesNotFound(missing.sorted())
            }
            
            return Result(data: data, hasSignature: context.hasSignature)
            
        } catch let error as ParserError {
            throw error
        } catch {
            preconditionFailure("Invalid error thrown: \(error)")
        }
    }
    
}


private
extension MachOParser {
    
    struct Context {
        var didReplace: Set<String> = []
        var hasSignature: Bool = false
    }
    
    /// Print a message if verbose mode is enabled.
    func print(_ message: String) {
        if self.verbose {
            Swift.print(message)
        }
    }
    
    
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
        context: inout Context,
        handler: (UnsafeMutableRawBufferPointer, inout Context) throws(ParserError) -> Void
    ) throws(ParserError) {
        switch try parseMagic(pointer) {
        case .plain:
            // It's a plain MachO file, can parse it directly.
            try handler(pointer, &context)
            
        case .fat32bit:
            try enumerateArchitectures32bit(pointer, context: &context, handler: handler)
            
        case .fat64bit:
            try enumerateArchitectures64bit(pointer, context: &context, handler: handler)
        }
    }
    
    
    func enumerateArchitectures32bit(
        _ pointer: UnsafeMutableRawBufferPointer,
        context: inout Context,
        handler: (UnsafeMutableRawBufferPointer, inout Context) throws(ParserError) -> Void
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
                    try handler(rebased, &context)
                    
                default:
                    throw .invalidMagic
                }
            }
        }
    }
    
    
    func enumerateArchitectures64bit(
        _ pointer: UnsafeMutableRawBufferPointer,
        context: inout Context,
        handler: (UnsafeMutableRawBufferPointer, inout Context) throws(ParserError) -> Void
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
                    try handler(rebased, &context)
                    
                default:
                    throw .invalidMagic
                }
            }
        }
    }
    
    
    /// Parse the load commands of a Mach object.
    /// Only 64-bit Mach objects are supported.
    func parseLoadCommands(
        _ machObjectPointer: UnsafeMutableRawBufferPointer,
        context: inout Context
    ) throws(ParserError) {
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
                let uuidCommand = commandSlice.load(as: uuid_command.self)
                print("\tUUID: \(UUID(uuid: uuidCommand.uuid))")
                
            case UInt32(LC_CODE_SIGNATURE):
                context.hasSignature = true
                
            case UInt32(LC_LOAD_DYLIB):
                try processLoadCommand(
                    name: "Load dynamic library",
                    commandSlice: commandSlice,
                    context: &context
                )
                
            case UInt32(LC_LOAD_WEAK_DYLIB):
                try processLoadCommand(
                    name: "Load weak dynamic library",
                    commandSlice: commandSlice,
                    context: &context
                )

            case UInt32(LC_LAZY_LOAD_DYLIB):
                try processLoadCommand(
                    name: "Lazy load dynamic library",
                    commandSlice: commandSlice,
                    context: &context
                )

            default:
                break
            }
            
            accumulatedCommandSizes += cmdsize
            offset += Int(cmdsize)
        }
        
        assert(sizeofcmds == accumulatedCommandSizes)
    }
    
    
    func processLoadCommand(
        name: String,
        commandSlice: UnsafeMutableRawBufferPointer.SubSequence,
        context: inout Context
    ) throws(ParserError) {
        let dylibCommand = commandSlice.load(as: dylib_command.self)
        
        // There is a second format, `dyld_use_command`. It can be identified by
        // dylibCommand.dylib.timestamp == DYLIB_USE_MARKER (probably need to watch out for
        // endianess). For our use, the difference doesn't matter.
        
        let (path, pathslice) = try String.from(dylibCommand.dylib.name, in: commandSlice)
        print("\t\(name): '\(path)'")
        
        guard var replacement = self.replace[path] else { return }
        
        print("\t\tReplacing with: \(replacement)")
        assert(replacement.count <= path.count, "This should have been handled earlier")
        
        // Clear out old path.
        pathslice.initializeMemory(as: UInt8.self, repeating: 0)
        // Copy in new path.
        replacement.withUTF8 {
            pathslice.copyBytes(from: $0)
        }
        
        context.didReplace.insert(replacement)
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
