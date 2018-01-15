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
        if (reqF == true) {
            if (isDir.boolValue == true) {
                return .notFile
            }
        }
        if (reqD == true) {
            if (isDir.boolValue == false) {
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
            Utils.err("ERROR: invalid/missing DSF file at \(dsfURL.path)")
            return false
        }
        let dsfToolProcess = Process()
        if let execURL = self.execURL {
            let dsfToolValid = BasicFileChecker.checkStatus(atPath: execURL.path, wantFile: true, wantExecutable: true)
            if (dsfToolValid != .allOK) {
                Utils.err("ERROR: invalid/missing DSFTool executable at \(execURL.path)")
                return false
            }
            dsfToolProcess.launchPath = execURL.path
            dsfToolProcess.arguments  = ["--dsf2text", "\(dsfURL.path)", "\(txtURL.path)"]
        } else { // TODO: support DSFTool in $PATH (launchPath: "/usr/bin/env", arguments: ["DSFTool", ...])
            Utils.err("ERROR: missing DSFTool executable")
            return false
        }
        dsfToolProcess.standardOutput = Pipe()
        dsfToolProcess.standardError  = Pipe()
        dsfToolProcess.launch()
        dsfToolProcess.waitUntilExit()
        if (dsfToolProcess.terminationStatus != 0) {
            if let stdoutText = String(data: (dsfToolProcess.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                Utils.err("\(stdoutText)", terminator: "")
            }
            if let stderrText = String(data: (dsfToolProcess.standardError  as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                Utils.err("\(stderrText)", terminator: "")
            }
        }
        return dsfToolProcess.terminationStatus == 0
    }
}

private class DSFTile {
    private var packURL: URL
    private var fileURL: URL
    private var resDone: Bool
    private var dsfName: String
    private var ddsList: [String]?
    private var pngList: [String]?
    private var terList: [String]?

    init(_ inURL: URL) {
        self.resDone = false
        self.ddsList = [String]()
        self.pngList = [String]()
        self.terList = [String]()
        self.dsfName = inURL.lastPathComponent
        self.fileURL = inURL.resolvingSymlinksInPath()
        self.packURL = self.fileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // DSF -> +XX-YYY -> Earth nav data -> X-Plane scenery pack
    }

    private func parseTextDSF(_ textURL: URL) -> Bool {
        guard self.resDone == false else {
            return true
        }
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
            Utils.err("ERROR: no .ter file definitions found")
            return false
        }
        self.terList = terList
        return true
    }

    @discardableResult private func parseTerFile(_ terURL: URL) -> Bool {
        guard self.resDone == false else {
            return true
        }
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
            Utils.err("ERROR: no definitions in \(terURL.lastPathComponent)")
            return false
        }
        self.ddsList = ddsList
        self.pngList = pngList
        return true
    }

    func resolveDependencies() -> Bool {
        guard self.resDone == false else {
            return true
        }
        let textFile = TemporaryFile()
        if (OrthoToolCLI.defaultDSFTool.dsf2text(for: self.fileURL, to: textFile.url) == false) {
            return false
        }
        if (self.parseTextDSF(textFile.url) == false) {
            Utils.err("ERROR: \(self.dsfName): failed to parse DSF text")
            return false
        }
        guard let terList = self.terList else {
            return false
        }
        for relPath in terList {
            if let terURL = URL(string: relPath, relativeTo: self.packURL.appendingPathComponent("terrain")) {
                self.parseTerFile(terURL)
            } else {
                Utils.err("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        self.resDone = true
        return true
    }

    func validateDependencies() -> Bool {
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
                    Utils.err("\(self.dsfName): missing/unreadable \(relPath)")
                    missing = true
                    continue
                }
            } else {
                Utils.err("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        for relPath in pngList {
            if let pngURL = URL(string: relPath, relativeTo: self.packURL.appendingPathComponent("textures")) {
                let status = BasicFileChecker.checkStatus(atPath: pngURL.path, wantFile: true, wantReadable: true)
                if (status != .allOK) {
                    Utils.err("\(self.dsfName): missing/unreadable \(relPath)")
                    missing = true
                    continue
                }
            } else {
                Utils.err("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
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
                    Utils.err("\(self.dsfName): missing/unreadable \(relPath)")
                    missing = true
                    continue
                }
            } else {
                Utils.err("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        if (missing == true) {
            Utils.out("Bad tile \(self.dsfName): dependency check failed")
            return false
        }
        if (jpFound == true) {
            Utils.out("Good tile \(self.dsfName): dependency check OK (warning: unconverted JPEG files present)")
        } else {
            Utils.out("Good tile \(self.dsfName): dependency check OK")
        }
        return true
    }
}

private class Utils {
    class func out(_ s: String, terminator t: String = "\n") {
        Utils.writeTextToFile(s + t, file: FileHandle.standardOutput)
    }

    class func err(_ s: String, terminator t: String = "\n") {
        Utils.writeTextToFile(s + t, file: FileHandle.standardError)
    }

    class func writeTextToFile(_ s: String, file fh: FileHandle) {
        if let data = s.data(using: .utf8, allowLossyConversion: true) {
            fh.write(data)
        }
    }

    class func printResidentMemory() {
        var taskInfo = mach_task_basic_info()
        var size = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &size)
            }
        }
        if kerr == KERN_SUCCESS {
            Utils.err("resident size: \(Float(taskInfo.resident_size) / 1024.0 / 1024.0) MiB")
        }
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
            do {
                TemporaryFile.tempDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), create: true)
            } catch {
                TemporaryFile.tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true) // write directly in temporary directory instead of subdir
            }
        }
        self.tmpFileURL = TemporaryFile.tempDir!.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: false)
        FileManager.default.createFile(atPath: self.tmpFileURL.path, contents: nil, attributes: nil)
    }
}

 class OrthoToolCLI {
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

    private func checkTileDependencies() -> Bool {
        var error = false
        for tileURL in self.tileURLs {
            autoreleasepool {
                var dsfTile : DSFTile? = DSFTile(tileURL)
                if (dsfTile!.resolveDependencies() == false) {
                    error = true
                }
                if (dsfTile!.validateDependencies() == false) {
                    error = true
                }
                dsfTile = nil
            }
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
        Utils.out(helpText)
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
                    Utils.err("ERROR: option requires an argument: --dsftool")
                    return false
                }
                OrthoToolCLI.dsfToolU = URL(fileURLWithPath: CommandLine.arguments[currIndex + 1])
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
                Utils.err("ERROR: illegal option: \(option)")
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
        if (self.checkDps == true) {
            if (self.tileURLs.isEmpty == true) {
                Utils.err("OrthoToolCLI: no tiles!")
                return false
            }
            if (self.checkTileDependencies() == false) {
                return false
            }
            return true
        }
        Utils.err("OrthoToolCLI: nothing to do!")
        return false
    }
 }

