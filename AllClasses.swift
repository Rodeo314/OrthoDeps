import Foundation

class DSFTile {
    private var dsfTool: URL // TODO: own class?
    private var fileURL: URL
    private var resDone: Bool
    private var ddsList: [URL]
    private var pngList: [URL]
    private var terList: [URL]
    
    init (withURL inURL: URL) {
        self.resDone = false
        self.ddsList = [URL]()
        self.pngList = [URL]()
        self.terList = [URL]()
        self.fileURL = inURL.resolvingSymlinksInPath()
        self.dsfTool = URL(fileURLWithPath: "/Volumes/Z4PLEX/TTT_ORTHO4XP2/Utils/DSFTool.app") // TODO: don't hardcode…
    }

    private func dsfToolOK() -> Bool {
        if (FileManager.default.fileExists      (atPath: self.dsfTool.path) == false ||
            FileManager.default.isExecutableFile(atPath: self.dsfTool.path) == false) {
            print("ERROR: invalid or missing DSFTool executable at \"\(dsfTool.path)\"")
            return false
        }
        return true
    }

    func resolveDependencies() {
        if (self.resDone == true) {
            return
        }
        if (self.dsfToolOK() == false) {
            return
        }
        let textPath = self.fileURL.appendingPathExtension("txt").path
        if (FileManager.default.createFile(atPath: textPath, contents: nil, attributes: nil) == false) {
            print("ERROR: can't write to \"\(textPath)\"")
            return
        }
        let textFile = FileHandle(forUpdatingAtPath: textPath)
        if (textFile == nil) {
            print("ERROR: invalid output file handle")
            return
        }
        let dsfToolProcess            = Process()
        dsfToolProcess.standardOutput = textFile
        dsfToolProcess.standardError  = FileHandle.nullDevice
        dsfToolProcess.arguments      = ["--dsf2text", "\"\(fileURL.path)\"", "-"/*stdout*/]
        dsfToolProcess.launchPath     = dsfTool.path
        dsfToolProcess.launch()
        dsfToolProcess.waitUntilExit()
        if (dsfToolProcess.terminationStatus != 0) {
            print("ERROR: DSFTool exited eith error \(dsfToolProcess.terminationStatus)")
        }
        self.resDone = true //fixme
    }
}

 class OrthoDeps {
    private var dsfTiles: [DSFTile]

    init() {
        self.dsfTiles = [DSFTile]() //fixme dictionary to avoid running the same tile twice
        for index in 1..<CommandLine.argc {
            dsfTiles.append(DSFTile(withURL: URL(fileURLWithPath: CommandLine.arguments[Int(index)])))
        }
    }

    func resolveTileDependencies() {
        for dsfTile in dsfTiles {
            dsfTile.resolveDependencies()
        }
    }
 }

