import Foundation

private class BasicFileChecker {
    enum BasicFileStatus {
        case allOK
        case notExist
        case notFile
        case notDirectory
        case notReadable
        case notWritable
        case notExecutable
    }

    class func checkStatus(atPath path: String,
                           wantFile       reqF: Bool = false,
                           wantDirectory  reqD: Bool = false,
                           wantReadable   reqR: Bool = false,
                           wantWritable   reqW: Bool = false,
                           wantExecutable reqX: Bool = false) -> BasicFileStatus {
        var isDir : ObjCBool = false
        if (FileManager.default.fileExists(atPath: path, isDirectory: &isDir) == false) {
            return .notExist
        }
        #if os(macOS)
        let isDirBoolValue = isDir.boolValue
        #else
        let isDirBoolValue = isDir
        #endif
        if (reqF == true) {
            if (isDirBoolValue == true) {
                return .notFile
            }
        }
        if (reqD == true) {
            if (isDirBoolValue == false) {
                return .notDirectory
            }
        }
        if (reqR == true) {
            if (FileManager.default.isReadableFile(atPath: path) == false) {
                return .notReadable
            }
        }
        if (reqW == true) {
            if (FileManager.default.isWritableFile(atPath: path) == false) {
                return .notWritable
            }
        }
        if (reqX == true) {
            if (FileManager.default.isExecutableFile(atPath: path) == false) {
                return .notExecutable
            }
        }
        return .allOK
    }
}

private class LineSplitter {
    private var sReader: StreamReader?

    deinit {
        self.sReader = nil
    }

    init(_ fileURL: URL, encoding: String.Encoding = .ascii) {
        self.sReader = StreamReader(url: fileURL, encoding: encoding)
    }

    var nextLine : String? {
        get {
            if let splitter = self.sReader {
                return splitter.nextLine()
            }
            return nil
        }
    }
}

private class DSFTool {
    private var execURL: URL?

    init() {
        if let dsToolURL = OrthoToolCLI.dsfToolURL {
            self.execURL = dsToolURL
        } else {
            let supportedNames = [ "DSFTool", "DSFTool.exe" ]
            for name in supportedNames {
                let url2check = OrthoToolCLI.getExecutableDirectory().appendingPathComponent(name)
                let urlExists = BasicFileChecker.checkStatus(atPath: url2check.path, wantFile: true, wantExecutable: true)
                if (urlExists == .allOK) {
                    self.execURL = url2check
                    break
                }
            }
        }
    }

    func dsf2text(for dsfURL: URL, to txtURL: URL) -> Bool {
        let dsfUrlExists = BasicFileChecker.checkStatus(atPath: dsfURL.path, wantFile: true, wantReadable: true)
        if (dsfUrlExists != .allOK) {
            Utils.default.error("ERROR: invalid/missing DSF file at \(dsfURL.path)")
            return false
        }
        let dsfToolProcess = Process()
        if let execURL = self.execURL {
            let dsfToolValid = BasicFileChecker.checkStatus(atPath: execURL.path, wantFile: true, wantExecutable: true)
            if (dsfToolValid != .allOK) {
                Utils.default.error("ERROR: invalid/missing DSFTool executable at \(execURL.path)")
                return false
            }
            dsfToolProcess.launchPath = execURL.path
            dsfToolProcess.arguments  = ["--dsf2text", "\(dsfURL.path)", "\(txtURL.path)"]
        } else { // TODO: support DSFTool in $PATH (launchPath: "/usr/bin/env", arguments: ["DSFTool", ...])
            Utils.default.error("ERROR: missing DSFTool executable")
            return false
        }
        dsfToolProcess.standardOutput = Pipe()
        dsfToolProcess.standardError  = Pipe()
        dsfToolProcess.launch()
        dsfToolProcess.waitUntilExit()
        if (dsfToolProcess.terminationStatus != 0) {
            if let stdoutText = String(data: (dsfToolProcess.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                Utils.default.error("\(stdoutText)", terminator: "")
            }
            if let stderrText = String(data: (dsfToolProcess.standardError  as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                Utils.default.error("\(stderrText)", terminator: "")
            }
        }
        return dsfToolProcess.terminationStatus == 0
    }
}

private class DSFTile {
    private var packURL: URL
    private var fileURL: URL
    private var haveLst: Bool
    private var goodLst: Bool
    private var haveChk: Bool
    private var goodChk: Bool
    private var dsfName: String
    private var ddsList: [String]?
    private var pngList: [String]?
    private var terList: [String]?

    private(set) var dependencyListGood : Bool {
        get {
            return self.haveLst == true && self.goodLst == true
        }
        set {
            self.goodLst = newValue
            self.haveLst = true
        }
    }

    private(set) var dependencyCheckGood : Bool {
        get {
            return self.haveChk == true && self.goodChk == true
        }
        set {
            self.goodChk = newValue
            self.haveChk = true
        }
    }

    private var quadrantComponent : String {
        get {
            return self.fileURL.deletingLastPathComponent().lastPathComponent
        }
    }

    init(_ inURL: URL) {
        self.haveLst = false
        self.goodLst = false
        self.haveChk = false
        self.goodChk = false
        self.ddsList = [String]()
        self.pngList = [String]()
        self.terList = [String]()
        self.dsfName = inURL.lastPathComponent
        self.fileURL = inURL.resolvingSymlinksInPath().absoluteURL
        self.packURL = self.fileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // DSF -> +XX-YYY -> Earth nav data -> X-Plane scenery pack
    }

    private func parseTextDSF(_ textURL: URL) -> Bool {
        guard var terList = self.terList else {
            return false
        }
        var splittr : LineSplitter? = LineSplitter(textURL)
        var curLine = splittr!.nextLine
        while (curLine != nil) {
            if (curLine!.hasPrefix("TERRAIN_DEF terrain/")) {
                if (curLine!.hasSuffix(".ter")) {
                    terList.append(URL(fileURLWithPath: curLine!).lastPathComponent)
                } else if (curLine!.hasSuffix(".ter\r")) {
                    terList.append(String(URL(fileURLWithPath: curLine!).lastPathComponent.dropLast()))
                }
                curLine = splittr!.nextLine
                continue
            }
            curLine = splittr!.nextLine
        }
        splittr = nil
        if (terList.isEmpty) {
            Utils.default.error("ERROR: no .ter file definitions found")
            return false
        }
        self.terList = terList
        return true
    }

    @discardableResult private func parseTerFile(_ terURL: URL) -> Bool {
        guard var ddsList = self.ddsList else {
            return false
        }
        guard var pngList = self.pngList else {
            return false
        }
        var splittr : LineSplitter? = LineSplitter(terURL)
        var curLine = splittr!.nextLine
        let l1count = ddsList.count
        let l2count = pngList.count
        let missing = curLine == nil // .ter file probably missing (else empty)
        while (curLine != nil) {
            if (curLine!.hasPrefix("BASE_TEX_NOWRAP ../textures/")) {
                if (curLine!.hasSuffix(".dds")) {
                    ddsList.append(URL(fileURLWithPath: curLine!).lastPathComponent)
                } else if (curLine!.hasSuffix(".dds\r")) {
                    ddsList.append(String(URL(fileURLWithPath: curLine!).lastPathComponent.dropLast()))
                }
                curLine = splittr!.nextLine
                continue
            }
            if (curLine!.hasPrefix("BORDER_TEX ../textures/")) {
                if (curLine!.hasSuffix(".png")) {
                    pngList.append(URL(fileURLWithPath: curLine!).lastPathComponent)
                } else if (curLine!.hasSuffix(".png\r")) {
                    pngList.append(String(URL(fileURLWithPath: curLine!).lastPathComponent.dropLast()))
                }
                curLine = splittr!.nextLine
                continue
            }
            curLine = splittr!.nextLine
        }
        splittr = nil
        if (missing == false && l1count >= ddsList.count && l2count >= pngList.count) {
            Utils.default.error("ERROR: no definitions in \(terURL.lastPathComponent)")
            return false
        }
        self.ddsList = ddsList
        self.pngList = pngList
        return true
    }

    func isInPackage(_ url: URL) -> Bool {
        return self.packURL == url.resolvingSymlinksInPath().absoluteURL
    }

    func resolveDependencies(force forced: Bool = false) -> Bool {
        if (forced == false) {
            guard self.haveLst == false else {
                return self.dependencyListGood
            }
        }
        self.dependencyListGood = self.privRresolveDependencies()
        return self.dependencyListGood
    }

    private func privRresolveDependencies() -> Bool {
        let textFile = TemporaryFile()
        if (OrthoToolCLI.defaultDSFTool.dsf2text(for: self.fileURL, to: textFile.url) == false) {
            return false
        }
        if (self.parseTextDSF(textFile.url) == false) {
            Utils.default.error("ERROR: \(self.dsfName): failed to parse DSF text")
            return false
        }
        guard let terList = self.terList else {
            return false
        }
        for relPath in terList {
            if let terURL = URL(string: relPath, relativeTo: self.packURL.appendingPathComponent("terrain")) {
                self.parseTerFile(terURL)
            } else {
                Utils.default.error("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        return true
    }

    func validateDependencies(force forced: Bool = false, verbosity chatty: Bool = true) -> Bool {
        guard self.dependencyListGood == true else {
            Utils.default.error("ERROR: \(self.dsfName): cannot validate unresolved dependencies!")
            return false
        }
        if (forced == false) {
            guard self.haveChk == false else {
                return self.dependencyCheckGood
            }
        }
        self.dependencyCheckGood = self.privValidateDependencies(chatty)
        return self.dependencyCheckGood
    }

    func privValidateDependencies(_ chatty: Bool) -> Bool {
        guard let ddsList = self.ddsList else {
            return false
        }
        guard let pngList = self.pngList else {
            return false
        }
        guard let terList = self.terList else {
            return false
        }
        var missing = false
        for relPath in terList {
            if let terURL = URL(string: relPath, relativeTo: self.packURL.appendingPathComponent("terrain")) {
                let status = BasicFileChecker.checkStatus(atPath: terURL.path, wantFile: true, wantReadable: true)
                if (status != .allOK) {
                    if (chatty) { Utils.default.error("\(self.dsfName): missing/unreadable \(relPath)") }
                    missing = true
                    continue
                }
            } else {
                Utils.default.error("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        for relPath in pngList {
            if let pngURL = URL(string: relPath, relativeTo: self.packURL.appendingPathComponent("textures")) {
                let status = BasicFileChecker.checkStatus(atPath: pngURL.path, wantFile: true, wantReadable: true)
                if (status != .allOK) {
                    if (chatty) { Utils.default.error("\(self.dsfName): missing/unreadable \(relPath)") }
                    missing = true
                    continue
                }
            } else {
                Utils.default.error("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        var jpFound = false
        for relPath in ddsList {
            if let ddsURL = URL(string: relPath, relativeTo: self.packURL.appendingPathComponent("textures")) {
                var status = BasicFileChecker.checkStatus(atPath: ddsURL.path, wantFile: true, wantReadable: true)
                if (status == .notExist) {
                    let jpgURL = ddsURL.deletingPathExtension().appendingPathExtension("jpg")
                    status = BasicFileChecker.checkStatus(atPath: jpgURL.path, wantFile: true, wantReadable: true)
                    if (status == .allOK) {
                        jpFound = true
                    }
                }
                if (status != .allOK) {
                    if (chatty) { Utils.default.error("\(self.dsfName): missing/unreadable \(relPath)") }
                    missing = true
                    continue
                }
            } else {
                Utils.default.error("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        if (missing == true) {
            if (chatty) { Utils.default.print("\(self.dsfName): bad tile, dependency check failed") }
            return false
        }
        if (jpFound == true) {
            if (chatty) { Utils.default.print("\(self.dsfName): good tile, dependency check OK (warning: unconverted JPEG files present)") }
        } else {
            if (chatty) { Utils.default.print("\(self.dsfName): good tile, dependency check OK") }
        }
        return true
    }

    func copyToURL(_ url : URL) -> Bool {
        guard self.isInPackage(url) == false else {
            Utils.default.error("ERROR: \(self.dsfName): same source/target directory, not copying")
            return false
        }
        guard self.dependencyListGood == true else {
            Utils.default.error("ERROR: \(self.dsfName): dependency check wasn't done, not copying")
            return false
        }
        guard self.dependencyCheckGood == true else {
            Utils.default.error("ERROR: \(self.dsfName): dependency check wasn't good, not copying")
            return false
        }
        guard let ddsList = self.ddsList else {
            Utils.default.error("ERROR: \(self.dsfName): unexpected error 1")
            return false
        }
        guard let pngList = self.pngList else {
            Utils.default.error("ERROR: \(self.dsfName): unexpected error 2")
            return false
        }
        guard let terList = self.terList else {
            Utils.default.error("ERROR: \(self.dsfName): unexpected error 3")
            return false
        }
        let newURL = url.resolvingSymlinksInPath().absoluteURL
        let dsfURL = newURL.appendingPathComponent("Earth nav data").appendingPathComponent(self.quadrantComponent).appendingPathComponent(self.dsfName)
        let dirURL = newURL.appendingPathComponent("Earth nav data").appendingPathComponent(self.quadrantComponent)
        let texURL = newURL.appendingPathComponent("textures")
        let terURL = newURL.appendingPathComponent("terrain")
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: terURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: texURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Utils.default.error("ERROR: unable to create directory structure at \(newURL.path)")
            return false
        }
        var fileExists = BasicFileChecker.checkStatus(atPath: dsfURL.path, wantFile: true)
        do {
            if (fileExists == .allOK) {
                try FileManager.default.removeItem(at: dsfURL)
            }
            try FileManager.default.copyItem(at: self.fileURL, to: dsfURL)
        } catch {
            Utils.default.error("ERROR: \(self.dsfName): file copy failed for \(dsfURL.path)")
            return false
        }
        for relPath in terList {
            let dstURL = terURL.appendingPathComponent(relPath)
            let srcURL = self.packURL.appendingPathComponent("terrain").appendingPathComponent(relPath)
            fileExists = BasicFileChecker.checkStatus(atPath: dstURL.path, wantFile: true)
            do {
                if (fileExists == .allOK) {
                    try FileManager.default.removeItem(at: dstURL)
                }
                try FileManager.default.copyItem(at: srcURL, to: dstURL)
            } catch {
                Utils.default.error("ERROR: \(self.dsfName): file copy failed for \(dstURL.path)")
                return false
            }
        }
        for relPath in pngList {
            let dstURL = texURL.appendingPathComponent(relPath)
            let srcURL = self.packURL.appendingPathComponent("textures").appendingPathComponent(relPath)
            fileExists = BasicFileChecker.checkStatus(atPath: dstURL.path, wantFile: true)
            do {
                if (fileExists == .allOK) {
                    try FileManager.default.removeItem(at: dstURL)
                }
                try FileManager.default.copyItem(at: srcURL, to: dstURL)
            } catch {
                Utils.default.error("ERROR: \(self.dsfName): file copy failed for \(dstURL.path)")
                return false
            }
        }
        var jFound = false
        for relPath in ddsList {
            var dstURL = texURL.appendingPathComponent(relPath)
            var srcURL = self.packURL.appendingPathComponent("textures").appendingPathComponent(relPath)
            let jpPath = srcURL.deletingPathExtension().appendingPathExtension("jpg").path
            if (BasicFileChecker.checkStatus(atPath: jpPath, wantFile: true) == .allOK) {
                srcURL = srcURL.deletingPathExtension().appendingPathExtension("jpg")
                dstURL = dstURL.deletingPathExtension().appendingPathExtension("jpg")
                jFound = true
            }
            fileExists = BasicFileChecker.checkStatus(atPath: dstURL.path, wantFile: true)
            do {
                if (fileExists == .allOK) {
                    try FileManager.default.removeItem(at: dstURL)
                }
                try FileManager.default.copyItem(at: srcURL, to: dstURL)
            } catch {
                Utils.default.error("ERROR: \(self.dsfName): file copy failed for \(dstURL.path)")
                return false
            }
        }
        if (jFound == true) {
            Utils.default.print("\(self.dsfName): tile copy OK (warning: unconverted JPEG files present)")
        } else {
            Utils.default.print("\(self.dsfName): tile copy OK")
        }
        return true
    }
}

private class Utils {
    private static var single : Utils = Utils()
    class var `default` : Utils {
        get {
            return Utils.single
        }
    }

    private var sout : FileHandle
    private var serr : FileHandle

    init() {
        self.sout = FileHandle.standardOutput
        self.serr = FileHandle.standardError
    }

    var standardOutput : FileHandle {
        get {
            return self.sout
        }
        set {
            self.sout = newValue
        }
    }

    var standardError : FileHandle {
        get {
            return self.serr
        }
        set {
            self.serr = newValue
        }
    }

    func error(_ strings: String...,
               separator s: String = "",
               terminator t: String = "\n",
               encoding e: String.Encoding = .utf8,
               allowLossyConversion b: Bool = true) {
        self.print(self.standardError, strings, separator: s, terminator: t, encoding: e, allowLossyConversion: b)
    }

    /*
     * Extremely dirrty but so fun: allow providing an optional,
     * *leading* FileHandle by leveraging variadic parameters :D
     */
    func print(_ array: Any...,
               separator s: String = "",
               terminator t: String = "\n",
               encoding e: String.Encoding = .utf8,
               allowLossyConversion b: Bool = true) {
        var text = ""
        var objs = array
        var file = self.standardOutput
        if let first = objs.first, first is FileHandle {
            file = first as! FileHandle
            objs.removeFirst()
        }
        for item in objs {
            if item is String {
                if (text.isEmpty == false && s.isEmpty == false) {
                    text += s
                }
                text += item as! String
            }
            if item is [String] {
                for string in item as! [String] {
                    if (text.isEmpty == false && s.isEmpty == false) {
                        text += s
                    }
                    text += string
                }
            }
        }
        do {
            text += t
        }
        if let d = text.data(using: e, allowLossyConversion: b) {
            file.write(d)
        }
    }

    func printResidentMemory() {
        #if os(macOS)
        var taskInfo = mach_task_basic_info()
        var size = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &size)
            }
        }
        if kerr == KERN_SUCCESS {
            self.print(self.standardError, "resident size: \(Float(taskInfo.resident_size) / 1024.0 / 1024.0) MiB")
        }
        #endif
    }
}

private class TemporaryFile {
    private static var tempDir: URL?
    private var tmpFileURL: URL

    var url : URL {
        get {
            return self.tmpFileURL
        }
    }

    var fileHandleForReading : FileHandle? {
        get {
            do {
                let handle = try FileHandle(forReadingFrom: self.tmpFileURL)
                return handle
            } catch {
                return nil
            }
        }
    }

    var fileHandleForWriting : FileHandle? {
        get {
            do {
                let handle = try FileHandle(forWritingTo: self.tmpFileURL)
                return handle
            } catch {
                return nil
            }
        }
    }

    deinit {
        if (FileManager.default.fileExists(atPath: self.tmpFileURL.path) == true) {
            do {
                try FileManager.default.removeItem(at: self.tmpFileURL)
            } catch {}
        }
        if let tempDir = TemporaryFile.tempDir { // self-cleaning: whenever it becomes empty, remove the directory
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
                if (items.isEmpty == true) {
                    do {
                        try FileManager.default.removeItem(at: tempDir)
                        TemporaryFile.tempDir = nil
                    } catch {}
                }
            } catch {}
        }
    }

    init() {
        if (TemporaryFile.tempDir == nil) {
            #if os(macOS)
            do {
                TemporaryFile.tempDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), create: true)
            } catch {
                TemporaryFile.tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true) // write directly in temporary directory instead of subdir
            }
            #else
                TemporaryFile.tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true) // write directly in temporary directory instead of subdir
            #endif
        }
        self.tmpFileURL = TemporaryFile.tempDir!.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: false)
        let _ = FileManager.default.createFile(atPath: self.tmpFileURL.path, contents: nil, attributes: nil)
    }
}

 class OrthoToolCLI {
    private var copy2URL: URL?
    private var checkDps: Bool
    private var tileURLs: [URL]

    private static var staticDSFTool : DSFTool = DSFTool()
    fileprivate class var defaultDSFTool : DSFTool {
        get {
            return OrthoToolCLI.staticDSFTool
        }
    }

    private static var dsfToolU: URL?
    class var dsfToolURL: URL? {
        get {
            return OrthoToolCLI.dsfToolU
        }
    }

    class func getExecutableDirectory() -> URL {
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    @inline(__always) private func singleTileDeps(_ url: URL) -> Bool {
        var dsfTile : DSFTile? = DSFTile(url)
        if (dsfTile!.resolveDependencies() == false) {
            dsfTile = nil
            return false
        }
        if (dsfTile!.dependencyListGood == true &&
            dsfTile!.validateDependencies() == false) {
            dsfTile = nil
            return false
        }
        dsfTile = nil
        return true
    }

    private func checkTileDependencies() -> Bool {
        var error = false
        for tileURL in self.tileURLs {
            #if os(macOS)
            autoreleasepool {
                if (self.singleTileDeps(tileURL) == false) {
                    error = true
                }
            }
            #else
                if (self.singleTileDeps(tileURL) == false) {
                    error = true
                }
            #endif
        }
        return error == false
    }

    @inline(__always) private func singleTileCopy(_ inTileURL : URL, _ outPackageURL: URL) -> Bool {
        var dsfTile : DSFTile? = DSFTile(inTileURL)
        if (dsfTile!.isInPackage(outPackageURL) == false) { // else copyToURL a no-op
            // don't return on error: not verbose, we'd exit w/out printing the error
            if (dsfTile!.resolveDependencies() == true) {
                _ = dsfTile!.validateDependencies(verbosity: false)
            }
        }
        // always call to get the error message printed for us, if any
        if (dsfTile!.copyToURL(outPackageURL) == false) {
            dsfTile = nil
            return false
        }
        dsfTile = nil
        return true
    }

    private func copyTilesToURL() -> Bool {
        var error = false
        guard let copy2URL = self.copy2URL else {
            return false
        }
        for tileURL in self.tileURLs {
            #if os(macOS)
            autoreleasepool {
                if (self.singleTileCopy(tileURL, copy2URL) == false) {
                    error = true
                }
            }
            #else
                if (self.singleTileCopy(tileURL, copy2URL) == false) {
                    error = true
                }
            #endif
        }
        return error == false
    }

    private func showHelp() {
        let helpText = """
\(URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent) [options] <file1> [additional files]

 All input files must be DSF tiles generated by Ortho4XP.

 Laminar Research's DSFTool program is required. By default,
 it should be placed in the same directory as this executable.
 You may provide another path to DSFTool via a dedicated option.

 Options:
  -h, --help        This help text.
  --check           Default tool behavior (may be omitted)
                    Verify that all files required by each tile exist
                    Result (good/bad tile) written to standard output
                    Missing files, if any, written to standard error
  --dsftool <path>  Manually specify path to the DSFTool executable

"""
        Utils.default.print(helpText)
    }

    private func parseOptions() -> Bool {
        var currIndex = 1
        var tempPaths = [String]()
        if (CommandLine.argc < 2) {
            self.showHelp()
            exit(EXIT_FAILURE)
        }
        while (currIndex < CommandLine.argc) {
            let option = CommandLine.arguments[currIndex]
            switch (option) {
            case "-h", "--help":
                self.showHelp()
                exit(EXIT_SUCCESS)
            case "--dsftool":
                if (currIndex == CommandLine.argc - 1) {
                    Utils.default.error("ERROR: option requires an argument: --dsftool")
                    return false
                }
                OrthoToolCLI.dsfToolU = URL(fileURLWithPath: CommandLine.arguments[currIndex + 1])
                currIndex += 1
                break
            case "--copy":
                if (currIndex == CommandLine.argc - 1) {
                    Utils.default.error("ERROR: option requires an argument: --copy")
                    return false
                }
                self.copy2URL = URL(fileURLWithPath: CommandLine.arguments[currIndex + 1])
                self.checkDps = false
                currIndex += 1
                break
            case "--check":
                self.checkDps = true
                break
            default:
                if (option.hasSuffix(".dsf")) {
                    tempPaths.append(URL(fileURLWithPath: CommandLine.arguments[currIndex]).resolvingSymlinksInPath().absoluteURL.path)
                    break
                }
                Utils.default.error("ERROR: illegal option: \(option)")
                return false
            }
            currIndex += 1
        }
        if (tempPaths.isEmpty == false) {
            tempPaths.sort() // sort and resolve duplicates
            var lastPath : String? = nil
            for currPath in tempPaths {
                if (lastPath == nil || lastPath != currPath) {
                    self.tileURLs.append(URL(fileURLWithPath: currPath))
                    lastPath = currPath
                }
            }
        }
        return true
    }

    init() {
        self.tileURLs = [URL]()
        self.checkDps = true // default action
    }

    func run() -> Bool {
        if (self.parseOptions() == false) {
            return false
        }
        if (self.tileURLs.isEmpty == true) {
            Utils.default.error("OrthoToolCLI: no tiles!")
            return false
        }
        if self.copy2URL != nil {
            if (self.copyTilesToURL() == false) {
                return false
            }
            return true
        }
        if (self.checkDps == true) {
            if (self.checkTileDependencies() == false) {
                return false
            }
            return true
        }
        Utils.default.error("OrthoToolCLI: nothing to do!")
        return false
    }
 }

