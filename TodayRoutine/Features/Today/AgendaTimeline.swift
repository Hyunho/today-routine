import SwiftUI

struct AgendaTimeline<Content: View>: View {
    let segments: [AgendaSegment]
    let currentMinute: Int?
    let cylinderEffect: Bool
    let layout: ListLayoutConfig
    @ViewBuilder let content: (AgendaSegment) -> Content
    private var activeID: String? {
        currentMinute.flatMap { AgendaLayout.currentSegment(in: segments, minute: $0)?.id }
    }
    var body: some View {
        VStack(spacing: 0) {
            ForEach(segments) { segment in
                let hourMarks = stride(from: 0, to: 1440, by: 60).filter {
                    minute in
                    segment.isGap
                        && AgendaLayout.currentSegment(in: segments, minute: minute)?.id == segment.id
                        // An event ending on the hour already has its own bottom rule.
                        && !segments.contains { !$0.isGap && $0.end == minute }
                }
                Group {
                    if segment.isGap {
                        HStack(spacing: 29) {
                            Rectangle().fill(.secondary.opacity(0.2)).frame(width: 2)
                            Spacer()
                        }
                        .padding(.leading, 21)
                        // Leave space between hourly rules in compressed empty periods.
                        .frame(height: segment.height(using: layout))
                    } else {
                        content(segment)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                                    .allowsHitTesting(false)
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                                    .allowsHitTesting(false)
                            }
                            .modifier(TodayCylinderEffect(enabled: cylinderEffect))
                            .padding(.leading, 44 + layout.lineInset)
                            .padding(.trailing, layout.lineInset)
                            .overlay(alignment: .leading) {
                                VStack(spacing: 0) {
                                    Text(RoutineRules.timeLabel(segment.start))
                                        .font(.caption.weight(.medium)).foregroundStyle(.primary)
                                        .accessibilityLabel("시작 \(RoutineRules.timeLabel(segment.start))")
                                    Spacer(minLength: 6)
                                    if segment.end > segment.start {
                                        Text(segment.end == 1440 ? "24:00" : RoutineRules.timeLabel(segment.end))
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .accessibilityLabel("종료 \(segment.end == 1440 ? "24:00" : RoutineRules.timeLabel(segment.end))")
                                    }
                                }
                                .monospacedDigit().frame(width: 44).padding(.vertical, 8)
                            }
                    }
                }
                .background {
                    GeometryReader { geometry in
                        ForEach(hourMarks, id: \.self) { minute in
                            let fraction = Double(minute - segment.start) / Double(segment.end - segment.start)
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                                .padding(.leading, 44)
                                .offset(y: geometry.size.height * fraction)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    if segment.isGap, hourMarks.count > 1 {
                        GeometryReader { geometry in
                            ForEach(hourMarks.filter { $0 == hourMarks.first || $0 == hourMarks.last }, id: \.self) { minute in
                                let fraction = Double(minute - segment.start) / Double(segment.end - segment.start)
                                Text(RoutineRules.timeLabel(minute))
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 44, height: 16)
                                    .background(.background)
                                    .position(x: 22, y: geometry.size.height * fraction)
                            }
                        }.allowsHitTesting(false)
                    }
                }
                .overlay {
                    if segment.id == activeID, let currentMinute {
                        GeometryReader { geometry in
                            let fraction = Double(currentMinute - segment.start) / Double(segment.end - segment.start)
                            VStack(spacing: 0) {
                                Color.clear.frame(height: max(0, geometry.size.height * fraction - 8))
                                HStack(spacing: 0) {
                                    Text(RoutineRules.timeLabel(currentMinute)).font(.caption2.bold())
                                        .foregroundStyle(.red).padding(.horizontal, 4).background(.background, in: Capsule())
                                    Circle().fill(.red).frame(width: 6, height: 6)
                                    Rectangle().fill(.red).frame(height: 2)
                                }
                                .frame(height: 16)
                                .id("today-current-time")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("현재 시간 \(RoutineRules.timeLabel(currentMinute))")
                                .accessibilityIdentifier("today-current-time")
                                Spacer(minLength: 0)
                            }
                        }.allowsHitTesting(false)
                    }
                }
                // A gap already contributes its own height; add row spacing only once.
                .padding(.bottom, segment.isGap || segment.id == segments.last?.id ? 0 : layout.itemSpacing)
            }
        }
    }
}
