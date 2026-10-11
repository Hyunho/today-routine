import Foundation

struct CloudTransferReport {
    var isCloud = false
    var files = 0
    var uploaded = 0
    var uploadPending = 0
    var uploadUnknown = 0
    var downloadsRequested = 0
    var uploadsRequested = 0
    var directUploadSupported = false
    var failures = 0
    var lastError: String?

    var summary: String {
        guard isCloud else { return "로컬 폴더입니다. iCloud Drive 폴더를 선택해야 기기 간 전송됩니다." }
        var lines = ["파일 \(files)개 · iCloud 업로드 확인 \(uploaded)개 · 대기 \(uploadPending)개"]
        if uploadUnknown > 0 { lines.append("업로드 상태 확인 중 \(uploadUnknown)개") }
        if downloadsRequested > 0 { lines.append("다운로드 요청 \(downloadsRequested)개 · 완료 후 다시 확인합니다.") }
        if uploadsRequested > 0 { lines.append("직접 업로드 완료 \(uploadsRequested)개") }
        if !directUploadSupported { lines.append("직접 업로드 제어 미지원 · 업로드는 시스템이 처리합니다.") }
        if failures > 0 { lines.append("전송 요청 실패 \(failures)개: \(lastError ?? "다시 시도해 주세요.")") }
        lines.append("다른 기기의 적용 여부는 동기화 상태에서 별도로 확인합니다.")
        return lines.joined(separator: "\n")
    }
}
