import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: ktstack-resolve <lang> <cwd>", code: 2) }
guard let lang = RuntimeLanguage(rawValue: args[1]) else { fail("unknown runtime: \(args[1])", code: 2) }
let cwd = URL(fileURLWithPath: args[2])

let paths = AppSupportPaths()
let resolver = ShellRuntimeBinResolver(paths: paths)
let installed = RuntimeCatalog(paths: paths).installedVersions(lang)
guard let chosen = resolver.chooseVersion(lang, cwd: cwd, installed: installed) else {
    fail("no \(lang.rawValue) runtime installed", code: 127)
}

guard let bin = try? resolver.confinedBinary(lang, version: chosen) else {
    fail("\(lang.rawValue) \(chosen) not found in runtime root", code: 127)
}

print(bin.path)
