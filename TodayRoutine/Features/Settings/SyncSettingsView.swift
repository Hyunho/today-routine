import SwiftUI
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import AppKit
#endif
struct SyncSettingsView: View {
    @Bindable var sync: SyncCoordinator
    @State private var chooseFolder = false
    @State private var preview: URL?
    @State private var disconnect = false
    @State private var pickerError: String?
    var body: some View {
        Form {
            Section("연결") {
                Text(sync.status).accessibilityIdentifier("동기화 상태")
                if let folder = sync.folderName { LabeledContent("선택한 폴더",value:folder) }
                if let date = sync.lastChecked { LabeledContent("마지막 확인",value:date.formatted(date:.abbreviated,time:.standard)) }
                LabeledContent("전송 대기",value:"\(sync.pendingCount)개")
                Button(sync.folderName == nil ? "동기화 폴더 선택":"폴더 다시 선택") { chooseFolder = true }
                if sync.folderName != nil { Button("지금 확인") { Task { await sync.refresh() } }; Button("연결 해제",role:.destructive) { disconnect = true } }
                if let pickerError { Text(pickerError).foregroundStyle(.red) }
            }
            Section { Text("파일 앱·Finder의 iCloud Drive에 빈 전용 폴더를 만들고, 두 기기에서 같은 폴더를 선택하세요. 앱을 사용하는 동안 자동으로 확인합니다. iCloud 전달에는 시간이 걸릴 수 있습니다.").font(.footnote) }
            if !sync.conflicts.isEmpty { Section("충돌 확인") {
                ForEach(sync.conflicts) { conflict in
                    VStack(alignment:.leading,spacing:8) {
                        Text("\(conflict.date) · \(conflict.column)").font(.headline)
                        Text("앱: \(conflict.appValue ? "완료":"미완료") / CSV: \(conflict.csvValue ? "완료":"미완료")")
                        HStack { Button("앱 값 유지") { Task { await sync.resolve(conflict,useCSV:false) } }; Button("CSV 값 적용") { Task { await sync.resolve(conflict,useCSV:true) } } }.buttonStyle(.bordered)
                    }
                }
            } }
            Section("최신 루틴 CSV") {
                if sync.latestCSV.isEmpty { Text("루틴을 만들고 폴더를 연결하면 표시됩니다.").foregroundStyle(.secondary) }
                ForEach(sync.latestCSV) { item in
                    VStack(alignment:.leading,spacing:6) {
                        Button(item.name) {
                            #if os(macOS)
                            NSWorkspace.shared.open(item.url)
                            #else
                            preview = item.url
                            #endif
                        }
                        Text(item.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section("CSV 편집 방법") {
                Text("날짜는 YYYY-MM-DD, 세부작업 완료는 TRUE, 미완료는 FALSE입니다. 빈 셀과 빠진 행·열은 기존 값을 지우지 않습니다.")
                Text("아이폰에서는 파일 앱에서 같은 CSV를 편집하세요. Numbers·Excel에서는 반드시 CSV로 저장해야 합니다. 단계 이름 변경과 추가는 앱에서 해주세요.")
                Text("앱은 새 상태를 새 버전 폴더에 저장합니다. 다시 편집할 때는 위의 최신 CSV를 여세요. 과거 파일에서 이미 반영한 내용은 반복 적용하지 않습니다.")
            }.font(.footnote)
        }.navigationTitle("자동 동기화").platformInlineTitle()
        .fileImporter(isPresented:$chooseFolder,allowedContentTypes:[.folder]) { result in
            switch result { case .success(let url): pickerError = nil; Task { await sync.connect(url:url) }
            case .failure(let error): pickerError = error.localizedDescription }
        }
        .quickLookPreview($preview)
        .confirmationDialog("연결만 해제할까요? 기기와 폴더의 기록은 보존됩니다.",isPresented:$disconnect) { Button("연결 해제",role:.destructive) { sync.disconnect() } }
    }
}
