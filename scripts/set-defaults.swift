import AppKit
import UniformTypeIdentifiers

// Usage: swift scripts/set-defaults.swift /Applications/Folio.app [ext ...]
let args = Array(CommandLine.arguments.dropFirst())
guard let appPath = args.first else {
    print("usage: set-defaults.swift <app> [ext ...]")
    exit(1)
}
let app = URL(fileURLWithPath: appPath)
let exts = args.count > 1 ? Array(args.dropFirst()) : ["md", "txt", "py", "json", "yaml"]

var failed = false
for ext in exts {
    guard let type = UTType(filenameExtension: ext), !type.isDynamic else {
        print("skip .\(ext): no system type")
        continue
    }
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
        if let error {
            print("fail .\(ext) (\(type.identifier)): \(error.localizedDescription)")
            failed = true
        } else {
            print("ok   .\(ext) (\(type.identifier))")
        }
        done.signal()
    }
    while done.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
exit(failed ? 1 : 0)
