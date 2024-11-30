//
//  main.swift
//  MachoPatchu
//
//  Created by Marc Haisenko on 2024-11-29.
//

import Foundation

guard let executableURL = Bundle.main.executableURL else {
    preconditionFailure("Cannot get own path")
}

guard let data = try? Data(contentsOf: executableURL) else {
    preconditionFailure("Cannot read executable")
}

let parser = MachoOParser(data: data)
do {
    try parser.parse()
} catch {
    print("Error: \(error)")
}
