import Foundation
enum CSVCodec {
    static func decode(_ data: Data) throws -> [[String]] {
        guard data.count <= 10_000_000, var text = String(data:data,encoding:.utf8) else { throw SyncError.invalid("CSV는 10MB 이하 UTF-8 파일이어야 합니다.") }
        if text.first == "\u{feff}" { text.removeFirst() }
        // Unicode Character treats CRLF as one character; normalize before parsing.
        text = text.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        let chars = Array(text); var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" { if i+1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 } else { quoted = false; closed = true } }
                else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = ""; closed = false }
            else if c == "\"" && field.isEmpty && !closed { quoted = true }
            else { guard !closed && c != "\"" else { throw SyncError.invalid("CSV 따옴표 형식이 올바르지 않습니다.") }; field.append(c) }
            i += 1
        }
        guard !quoted else { throw SyncError.invalid("CSV 따옴표가 닫히지 않았습니다.") }
        if !row.isEmpty || !field.isEmpty || closed { row.append(field); rows.append(row) }
        return rows
    }
    static func encode(_ rows: [[String]]) -> Data {
        Data((rows.map { $0.map { value in
            value.contains(where: { [",","\"","\n","\r"].contains(String($0)) }) ? "\""+value.replacingOccurrences(of:"\"",with:"\"\"")+"\"" : value
        }.joined(separator:",") }.joined(separator:"\r\n")+"\r\n").utf8)
    }
    static func safeTitle(_ value: String) -> String { value.first.map { "=+-@\t\r'".contains($0) } == true ? "'"+value : value }
}
