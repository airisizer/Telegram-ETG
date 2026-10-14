import Foundation

/// Минимальный TAR-распаковщик (ustar + GNU longname 'L' + PAX 'x').
/// Foundation на iOS не умеет zip/tar, стороннюю зависимость не тащим.
public enum TarUnpacker {
    public static func unpack(tarAt tarURL: URL, to destDir: URL) throws {
        let data = try Data(contentsOf: tarURL)
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        var offset = 0
        var pendingName: String?
        while offset + 512 <= data.count {
            let header = data.subdata(in: offset..<(offset + 512))
            offset += 512

            let rawName = readCString(header, at: 0, max: 100)
            let size = Int(readCString(header, at: 124, max: 12).trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
            let typeFlag = header[156]

            if rawName.isEmpty && pendingName == nil { break } // нулевой блок = конец

            let dataStart = offset
            let dataEnd = offset + size
            offset += ((size + 511) / 512) * 512
            guard dataEnd <= data.count else { break }

            switch typeFlag {
            case UInt8(ascii: "L"): // GNU long name
                pendingName = String(decoding: data.subdata(in: dataStart..<dataEnd).prefix(while: { $0 != 0 }), as: UTF8.self)
                continue
            case UInt8(ascii: "x"): // PAX extended header
                let content = String(decoding: data.subdata(in: dataStart..<dataEnd), as: UTF8.self)
                // записи: "<len> path=some/path\n"
                for rec in content.split(separator: "\n") {
                    guard let eq = rec.firstIndex(of: "=") else { continue }
                    let key = rec[rec.startIndex..<eq]
                    if key.hasSuffix("path") {
                        pendingName = String(rec[rec.index(after: eq)...])
                    }
                }
                continue
            default:
                break
            }

            // Итоговое имя: PAX/GNU override > ustar prefix+name > name
            let hadOverride = pendingName != nil
            var name = pendingName ?? rawName
            pendingName = nil
            if !hadOverride {
                let prefix = readCString(header, at: 345, max: 155)
                if !prefix.isEmpty { name = prefix + "/" + rawName }
            }

            // Защита от path traversal
            let safeName = name.replacingOccurrences(of: "..", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if safeName.isEmpty { continue }
            let outURL = destDir.appendingPathComponent(safeName)

            if typeFlag == UInt8(ascii: "5") { // директория
                try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)
            } else if typeFlag == UInt8(ascii: "0") || typeFlag == 0 { // обычный файл
                try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.subdata(in: dataStart..<dataEnd).write(to: outURL)
            }
            // симлинки/прочее пропускаем — в SDK их нет
        }
    }

    private static func readCString(_ data: Data, at start: Int, max: Int) -> String {
        guard start + max <= data.count else { return "" }
        let slice = data.subdata(in: start..<(start + max)).prefix(while: { $0 != 0 })
        return String(decoding: slice, as: UTF8.self)
    }
}
