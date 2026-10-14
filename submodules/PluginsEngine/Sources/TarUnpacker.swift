import Foundation

/// Минимальный TAR-распаковщик (ustar, без сжатия) — Foundation на iOS
/// не умеет zip/tar, а тащить стороннюю зависимость ради одного архива
/// незачем. Поддерживает файлы и директории (типы '0'/'5'), long-name
/// расширения ('L') не нужны — наши пути короче 100 символов... на всякий
/// случай поддерживаем и их.
public enum TarUnpacker {
    public static func unpack(tarAt tarURL: URL, to destDir: URL) throws {
        let data = try Data(contentsOf: tarURL)
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        var offset = 0
        var pendingLongName: String?
        while offset + 512 <= data.count {
            let header = data.subdata(in: offset..<(offset + 512))
            offset += 512

            // Имя (байты 0..100)
            let name = readCString(header, at: 0, max: 100)
            if name.isEmpty && pendingLongName == nil { break } // нулевой блок = конец

            let sizeOctal = readCString(header, at: 124, max: 12)
            let size = Int(sizeOctal.trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
            let typeFlag = header[156]

            let entryName = pendingLongName ?? name
            pendingLongName = nil

            // Данные (выровнены по 512)
            let dataStart = offset
            let dataEnd = offset + size
            offset += ((size + 511) / 512) * 512
            guard dataEnd <= data.count else { break }

            if typeFlag == UInt8(ascii: "L") { // GNU long name
                pendingLongName = String(decoding: data.subdata(in: dataStart..<dataEnd).prefix(while: { $0 != 0 }), as: UTF8.self)
                continue
            }

            // Защита от path traversal
            let safeName = entryName.replacingOccurrences(of: "..", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if safeName.isEmpty { continue }
            let outURL = destDir.appendingPathComponent(safeName)

            if typeFlag == UInt8(ascii: "5") { // директория
                try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)
            } else if typeFlag == UInt8(ascii: "0") || typeFlag == 0 { // файл
                try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.subdata(in: dataStart..<dataEnd).write(to: outURL)
            }
            // симлинки/прочее пропускаем — в нашем SDK их нет
        }
    }

    private static func readCString(_ data: Data, at start: Int, max: Int) -> String {
        let slice = data.subdata(in: start..<(start + max)).prefix(while: { $0 != 0 })
        return String(decoding: slice, as: UTF8.self)
    }
}
