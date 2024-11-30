//
//  MachoPatchu.swift
//  MachoPatchu
//
//  Created by Marc Haisenko on 2024-11-29.
//

import Foundation
import ArgumentParser


@main
struct MachoPatchu: ParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: "MachoPatchu",
        abstract: "Patches library paths to load in Mach-O binaries.",
        discussion:
            "This command can edit existing Mach-O binaries to replace paths of libraries to load. "
            + "It is used to work around Xcode linker issues that result in the linker to "
            + "reference incorrect library paths in some scenarios.")
    
    @Argument(help: "Path to the executable to patch.")
    var inputFile: String
    
    @Argument(help: "Path to the patched output file. If missing, the input file is overwritten.")
    var outputFile: String?
    
    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "List of library paths to replace in the format 'old=new'.",
            discussion: "Limitation: the new name must be equal or shorter than the old name.",
            valueName: "old=new"
        ),
        transform: {
            (string) -> (String, String) in
            let parts = string.split(separator: "=")
            guard parts.count == 2 else {
                throw ArgumentParser.ValidationError("Expected 'old=new' format.")
            }
            
            let old = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let new = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard old.count >= new.count else {
                throw ArgumentParser.ValidationError(
                    "'\(new)' must be equal or shorter than '\(old)'."
                )
            }
            
            return (old, new)
        }
    )
    var replace: [(String, String)]
    
    
    mutating func run() {
        let data: Data
        let inputURL = URL(
            filePath: inputFile,
            directoryHint: .checkFileSystem,
            relativeTo: .currentDirectory()
        )
        
        do {
            data = try Data(contentsOf: inputURL)
        } catch {
            print(stderr, "Error reading \(inputFile): \(error)")
            return
        }
        
        let parser = MachoOParser(data: data)
        do {
            try parser.parse()
        } catch {
            print(stderr, "Failed to process \(inputURL.lastPathComponent): \(error)")
        }
    }
    
}
