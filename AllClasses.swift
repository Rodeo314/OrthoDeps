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

private class LineParser {
    private var hundredsOfMegs: String?
    private var allLines: [String]?
    private var initDone: Bool
    private var lastDone: Bool
    private var nxtIndex: Int
    private var fileURL: URL

    init(withURL fileURL: URL) {
        self.fileURL        = fileURL
        self.initDone       = false
        self.lastDone       = false
        self.nxtIndex       = 0
//        print("DEBUG :init: LineParser \(self.fileURL.path)")
    }

    deinit {
//        print("DEBUG DEINIT LineParser \(self.fileURL.path)")
    }

    func getNextLine() -> String? {
        if (self.initDone == false && self.lastDone == false) {
            /*
             * TODO: use a stream reader!!!
             *
             * ---> 478003200  maximum resident set size
             *              0  average shared memory size
             *              0  average unshared data size
             *              0  average unshared stack size
             *         122461  page reclaims
             *            107  page faults
             *              0  swaps
             *             95  block input operations
             *             34  block output operations
             *              0  messages sent
             *              0  messages received
             *              0  signals received
             *            107  voluntary context switches
             *           2382  involuntary context switches
             */
            do {
                self.hundredsOfMegs = try String(contentsOf: self.fileURL)
            } catch {
                if (self.hundredsOfMegs != nil) {
                    self.hundredsOfMegs!.removeAll(); self.hundredsOfMegs = nil
                }
                self.initDone = true
                self.lastDone = true
                print("\(error)")
                return nil
            }
            if (self.hundredsOfMegs == nil) {
                self.initDone = true
                self.lastDone = true
                return nil
            }
            self.allLines = self.hundredsOfMegs!.components(separatedBy: .newlines)
            if (self.allLines == nil) {
                if (self.hundredsOfMegs != nil) {
                    self.hundredsOfMegs!.removeAll(); self.hundredsOfMegs = nil
                }
                self.initDone = true
                self.lastDone = true
                return nil
            }
            if (self.allLines!.isEmpty) {
                if (self.hundredsOfMegs != nil) {
                    self.hundredsOfMegs!.removeAll(); self.hundredsOfMegs = nil
                }
                self.initDone = true
                self.lastDone = true
                self.allLines = nil
                return nil
            }
            if (self.hundredsOfMegs != nil) {
                self.hundredsOfMegs!.removeAll(); self.hundredsOfMegs = nil
            }
            self.initDone = true
        }
        if (self.initDone == true && self.lastDone == false) {
            if (self.allLines != nil) {
                self.nxtIndex += 1
                if (self.nxtIndex <= self.allLines!.count) {
                    return allLines![self.nxtIndex - 1]
                }
            }
        }
        if (self.hundredsOfMegs != nil) {
            self.hundredsOfMegs!.removeAll(); self.hundredsOfMegs = nil
        }
        if (self.allLines != nil) {
            self.allLines!.removeAll(); self.allLines = nil
        }
        self.initDone = true; self.lastDone = true
        return nil // no more lines
    }
}

private class DSFTool {
    private var tempURL: URL
    private var soutURL: URL
    private var serrURL: URL
    private var execURL: URL?
    private var process: Process?
    private var stdoutH: FileHandle?
    private var stderrH: FileHandle?

    init() {
        self.tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        self.soutURL = self.tempURL.appendingPathComponent("stdout.txt")
        self.serrURL = self.tempURL.appendingPathComponent("stderr.txt")
        let supportedNames = [ "DSFTool", "DSFTool.app", "DSFTool.exe" ]
        for name in supportedNames {
            let url2check = OrthoToolCLI.getExecutableDirectory().appendingPathComponent(name)
            let urlExists = BasicFileChecker.checkStatus(atPath: url2check.path, wantFile: true, wantExecutable: true)
            if (urlExists == .allOK) {
                self.execURL = url2check
                break
            }
        }
        if (self.execURL == nil) { // TODO: support querying OrthoToolCLI for DSFTool path
            print("Warning: DSFTool not found")
        }
        if (self.process == nil && self.execURL != nil) { // TODO: drop latter part of the check
            self.process = Process()
        }
        if (self.process != nil) {
            FileManager.default.createFile(atPath: self.soutURL.path, contents: nil, attributes: nil)
            FileManager.default.createFile(atPath: self.serrURL.path, contents: nil, attributes: nil)
            self.stdoutH = FileHandle(forUpdatingAtPath: self.soutURL.path)
            self.stderrH = FileHandle(forUpdatingAtPath: self.serrURL.path)
            if (self.stdoutH != nil && self.stderrH != nil) {
                self.process!.standardOutput = self.stdoutH!
                self.process!.standardError  = self.stderrH!
            } else {
                self.process!.standardOutput = FileHandle.nullDevice
                self.process!.standardError  = FileHandle.nullDevice
                print("WARNING: unable to redirect process output")
            }
        }
    }

    func dsf2text(forDSF dsfURL: URL, toFile txtURL: URL) -> Bool {
        if (self.process == nil) {
            print("ERROR: DSFTool: no process!")
        }
        let urlExists = BasicFileChecker.checkStatus(atPath: dsfURL.path, wantFile: true, wantReadable: true)
        if (urlExists != .allOK) {
            print("ERROR: invalid/missing DSF file at \(dsfURL.path)")
            return false
        }
        self.process!.arguments  = ["--dsf2text", "\(dsfURL.path)", "\(txtURL.path)"]
        if (self.execURL != nil) {
            self.process!.launchPath = self.execURL!.path
        } else {
            // TODO: support searching $PATH (execURL == "path/to/env", prepend "DSFTool" to process arguments)
            // only under Unix-like OSes though (detect Linux, macOS)
        }
        self.process!.launch()
        self.process!.waitUntilExit()
        if (self.process!.terminationStatus != 0) {
            do {
                let stdoutPut = try String(contentsOf: self.soutURL)
                print("\(stdoutPut)", terminator: "")
                let stderrPut = try String(contentsOf: self.serrURL)
                print("\(stderrPut)", terminator: "")
            } catch {
                print("\(error)")
            }
            print("ERROR: \(dsfURL.lastPathComponent): DSFTool exit status \(self.process!.terminationStatus)")
            return false
        }
        return true
    }
}

private class DSFTile : Comparable {
    private var packURL: URL
    private var fileURL: URL
    private var resDone: Bool
    private var jpFound: Bool
    private var dsfName: String
    private var ddsList: [String]?
    private var pngList: [String]?
    private var terList: [String]?
    
    static func == (lhs: DSFTile, rhs: DSFTile) -> Bool { // Comparable : Equatable
        return lhs.fileURL.absoluteURL.path == rhs.fileURL.absoluteURL.path
    }

    static func < (lhs: DSFTile, rhs: DSFTile) -> Bool { // Comparable
        return lhs.fileURL.absoluteURL.path < rhs.fileURL.absoluteURL.path
    }

    init(withURL inURL: URL) {
        self.resDone = false
        self.jpFound = false
        self.ddsList = [String]()
        self.pngList = [String]()
        self.terList = [String]()
        self.dsfName = inURL.lastPathComponent
        self.fileURL = inURL.resolvingSymlinksInPath()
        self.packURL = self.fileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // DSF -> +XX-YYY -> Earth nav data -> X-Plane scenery pack
//        print("DEBUG :init: DSFTile \(self.dsfName)")
    }

    deinit {
//        print("DEBUG DEINIT DSFTile \(self.dsfName)")
    }

    private func parseTextDSF(at textURL: URL) -> Bool {
        if (self.resDone == true) {
            return true
        }
        if (terList == nil) {
            return false
        }
        let lParser = LineParser(withURL: textURL)
        var curLine = lParser.getNextLine()
        while (curLine != nil) {
            if (curLine!.hasPrefix("TERRAIN_DEF terrain/") && curLine!.hasSuffix(".ter")) {
                terList!.append("terrain/" + URL(fileURLWithPath: curLine!).lastPathComponent)
                curLine = lParser.getNextLine()
                continue
            }
            curLine = lParser.getNextLine()
        }
        if (terList!.isEmpty) {
            print("ERROR: no .ter file definitions found")
            return false
        }
        return true
    }

    private func parseTerFile(at terURL: URL) -> Bool {
        if (self.resDone == true) {
            return true
        }
        if (ddsList == nil) {
            return false
        }
        if (pngList == nil) {
            return false
        }
        let lParser = LineParser(withURL: terURL)
        var curLine = lParser.getNextLine()
        let l1count = ddsList!.count
        let l2count = pngList!.count
        while (curLine != nil) {
            if (curLine!.hasPrefix("BASE_TEX_NOWRAP ../textures/") && curLine!.hasSuffix(".dds")) {
                ddsList!.append("textures/" + URL(fileURLWithPath: curLine!).lastPathComponent)
                curLine = lParser.getNextLine()
                continue
            }
            if (curLine!.hasPrefix("BORDER_TEX ../textures/") && curLine!.hasSuffix(".png")) {
                pngList!.append("textures/" + URL(fileURLWithPath: curLine!).lastPathComponent)
                curLine = lParser.getNextLine()
                continue
            }
            curLine = lParser.getNextLine()
        }
        if (l1count >= ddsList!.count && l2count >= pngList!.count) {
            print("ERROR: no definitions in \(terURL.lastPathComponent)")
            return false
        }
        return true
    }

    func resolveDependencies() -> Bool {
        if (self.resDone == true) {
            return true
        }
        let textURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(self.dsfName)
        if (OrthoToolCLI.defaultDSFTool.dsf2text(forDSF: self.fileURL, toFile: textURL) == false) {
            return false
        }
        if (self.parseTextDSF(at: textURL) == false) {
            print("ERROR: \(self.dsfName): failed to parse DSF text")
            return false
        }
        do {
            try FileManager.default.removeItem(at: textURL)
        } catch {
            // do nothing
        }
        if (self.terList == nil) {
            return false
        }
        for relPath in self.terList! {
            if let terURL = URL(string: relPath, relativeTo: self.packURL) {
                let status = BasicFileChecker.checkStatus(atPath: terURL.path, wantFile: true, wantReadable: true)
                if (status != .allOK) {
                    print("Bad tile \(self.dsfName): missing/unreadable \(relPath)")
                    return false
                }
                if (self.parseTerFile(at: terURL) == false) {
                    return false
                }
            } else {
                print("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        if (self.pngList == nil) {
            return false
        }
        for relPath in self.pngList! {
            if let pngURL = URL(string: relPath, relativeTo: self.packURL) {
                let status = BasicFileChecker.checkStatus(atPath: pngURL.path, wantFile: true, wantReadable: true)
                if (status != .allOK) {
                    print("Bad tile \(self.dsfName): missing/unreadable \(relPath)")
                    return false
                }
            } else {
                print("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        if (self.ddsList == nil) {
            return false
        }
        for relPath in self.ddsList! {
            if let ddsURL = URL(string: relPath, relativeTo: self.packURL) {
                var status = BasicFileChecker.checkStatus(atPath: ddsURL.path, wantFile: true, wantReadable: true)
                if (status == .notExist) {
                    let jpgURL = ddsURL.deletingPathExtension().appendingPathExtension("jpg")
                    status = BasicFileChecker.checkStatus(atPath: jpgURL.path, wantFile: true, wantReadable: true)
                    if (status == .allOK) {
                        self.jpFound = true
                    }
                }
                if (status != .allOK) {
                    print("Bad tile \(self.dsfName): missing/unreadable \(relPath)")
                    return false
                }
            } else {
                print("ERROR: unable to resolve path to \(relPath) in \(self.packURL.path)")
                return false
            }
        }
        if (self.jpFound == true) {
            print("Good tile \(self.dsfName): dependency check OK (warning: unconverted JPEG files present)")
        } else {
            print("Good tile \(self.dsfName): dependency check OK")
        }
        self.ddsList!.removeAll(); self.ddsList = nil // TODO: we'll need these list's contents outside of here in the future
        self.pngList!.removeAll(); self.pngList = nil // TODO: we'll need these list's contents outside of here in the future
        self.terList!.removeAll(); self.terList = nil // TODO: we'll need these list's contents outside of here in the future
        self.resDone = true
        return true
    }
}

 class OrthoToolCLI {
    private var dsfTiles: [DSFTile]

    fileprivate static var staticDSFTool : DSFTool = DSFTool()
    fileprivate class var defaultDSFTool : DSFTool {
        get {
            return OrthoToolCLI.staticDSFTool
        }
    }

    class func getExecutableDirectory() -> URL {
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    @discardableResult func checkTileDependencies() -> Bool {
        for dsfTile in dsfTiles {
            if (dsfTile.resolveDependencies() == false) {
                return false
            }
        }
        return true
    }

    init() {
        self.dsfTiles = [DSFTile]()
        var tempTiles = [DSFTile]()
        for index in 1..<CommandLine.argc {
            tempTiles.append(DSFTile(withURL: URL(fileURLWithPath: CommandLine.arguments[Int(index)])))
        }
        if (tempTiles.isEmpty == false) {
            tempTiles.sort() // sort and resolve duplicates
            var lastTile : DSFTile? = nil
            for currTile in tempTiles {
                if (lastTile == nil || lastTile != currTile) {
                    self.dsfTiles.append(currTile)
                    lastTile = currTile
                }
            }
            tempTiles.removeAll() // all done: each tile copied to self.dsfTiles
        }
    }
 }

