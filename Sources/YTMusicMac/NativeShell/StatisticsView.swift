import SwiftUI

/// The listening statistics YouTube Music never shows you, built from the
/// local play history. Colors come from `.primary`/`.accentColor` so every
/// theme — light ones included — works without overriding colorScheme.
struct StatisticsView: View {
    @ObservedObject var vm: NativeShellViewModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !prefs.historyEnabled {
                    disabledState
                } else if let stats = vm.stats {
                    if stats.isEmpty {
                        emptyState
                    } else {
                        summaryRow(stats)
                        if stats.range.showsDailyActivity, !stats.daily.isEmpty {
                            ActivityChart(days: stats.daily, accent: prefs.theme.accentColor)
                        }
                        chartsGrid(stats)
                        Spacer(minLength: 40)
                    }
                } else if vm.statsLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        // `goStatistics()` loads on navigation, but the section can also be
        // restored (back/forward, launch) without going through it.
        .onAppear { if vm.stats == nil { vm.loadStatistics() } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KİTAPLIK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.primary.opacity(0.55))
                Text("İstatistikler")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text("Bu Mac'te dinlediklerinden üretildi; hiçbir yere gönderilmez.")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.5))
            }
            Spacer()
            rangePicker
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases) { range in
                let active = vm.statsRange == range
                Button {
                    vm.statsRange = range
                } label: {
                    Text(range.label)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundColor(active ? prefs.theme.onAccentColor : .primary.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(active ? prefs.theme.accentColor : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Summary tiles

    private func summaryRow(_ stats: ListeningStats) -> some View {
        HStack(spacing: 12) {
            SummaryTile(icon: "clock.fill",
                        value: StatsFormat.duration(stats.totalMs),
                        label: "dinleme süresi")
            SummaryTile(icon: "play.circle.fill",
                        value: "\(stats.playCount)",
                        label: "parça çaldın")
            SummaryTile(icon: "person.2.fill",
                        value: "\(stats.distinctArtists)",
                        label: "farklı sanatçı")
        }
    }

    // MARK: - Top lists

    /// Two fixed columns, not `.adaptive`: adaptive sizes for as many columns
    /// as fit, so on a wide window it reserved a third slot and left the pair
    /// hugging the left edge.
    private func chartsGrid(_ stats: ListeningStats) -> some View {
        // `.top` alignment: the two cards rarely hold the same number of rows,
        // and the default centres the shorter one against the taller.
        LazyVGrid(columns: [GridItem(.flexible(minimum: 300), spacing: 20, alignment: .top),
                            GridItem(.flexible(minimum: 300), spacing: 20, alignment: .top)],
                  alignment: .leading, spacing: 20) {
            RankCard(title: "En çok dinlediğin sanatçılar",
                     emptyText: "Henüz sanatçı yok",
                     accent: prefs.theme.accentColor,
                     rows: stats.topArtists.map {
                         RankRow(id: $0.id, primary: $0.artist, secondary: nil,
                                 plays: $0.plays, artworkURL: $0.artworkURL, circular: true)
                     })
            RankCard(title: "En çok dinlediğin şarkılar",
                     emptyText: "Henüz şarkı yok",
                     accent: prefs.theme.accentColor,
                     rows: stats.topTracks.map {
                         RankRow(id: $0.id, primary: $0.title, secondary: $0.artist,
                                 plays: $0.plays, artworkURL: $0.artworkURL, circular: false)
                     })
        }
    }

    // MARK: - Zero states

    private var emptyState: some View {
        placeholder(icon: "chart.bar.xaxis",
                    title: "Henüz yeterli veri yok",
                    caption: "Bir parça, 30 saniye ya da süresinin yarısı çaldığında sayılır. Dinlemeye devam et — burası kendiliğinden dolacak.")
    }

    private var disabledState: some View {
        placeholder(icon: "eye.slash",
                    title: "Dinleme geçmişi kapalı",
                    caption: "İstatistikleri görmek için Ayarlar → Dinleme geçmişi bölümünden kaydı aç.")
    }

    private func placeholder(icon: String, title: String, caption: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.primary.opacity(0.35))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

// MARK: - Summary tile

private struct SummaryTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.4))
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Daily activity

private struct ActivityChart: View {
    let days: [DayStat]
    let accent: Color

    private var peak: Int64 { max(days.map(\.listenedMs).max() ?? 0, 1) }

    /// Labelling all 30 bars of a month would be mush; label roughly six.
    private var labelStride: Int { max(1, days.count / 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Günlük dinleme")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    VStack(spacing: 6) {
                        // A silent day still gets a visible stub, so a gap reads
                        // as "nothing played" instead of as a missing day.
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.listenedMs > 0 ? accent : Color.primary.opacity(0.13))
                            .frame(height: max(4, 84 * CGFloat(day.listenedMs) / CGFloat(peak)))
                        Text(index % labelStride == 0 ? StatsFormat.dayLabel(day.day) : "")
                            .font(.system(size: 9))
                            .foregroundColor(.primary.opacity(0.4))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    // Without a cap, a 7-day week stretches each bar into a
                    // slab a hundred points wide.
                    .frame(maxWidth: 56)
                    .help("\(StatsFormat.fullDayLabel(day.day)): \(StatsFormat.duration(day.listenedMs))")
                }
            }
            .frame(height: 104, alignment: .bottom)
            // Baseline hugs the bars, not the card: a 7-bar week centres as a
            // narrow group and a full-width rule under it would look unmoored.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 1)
                    .padding(.bottom, 17)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Ranked lists

private struct RankRow: Identifiable {
    let id: String
    let primary: String
    let secondary: String?
    let plays: Int
    let artworkURL: String?
    let circular: Bool
}

private struct RankCard: View {
    let title: String
    let emptyText: String
    let accent: Color
    let rows: [RankRow]

    private var peak: Int { max(rows.map(\.plays).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            if rows.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        RankRowView(rank: index + 1, row: row,
                                    fraction: CGFloat(row.plays) / CGFloat(peak),
                                    accent: accent)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct RankRowView: View {
    let rank: Int
    let row: RankRow
    let fraction: CGFloat
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.4))
                .frame(width: 16, alignment: .trailing)

            cover
                .frame(width: 32, height: 32)
                .clipShape(shape)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.primary)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let secondary = row.secondary {
                    Text(secondary)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text("\(row.plays)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.75))
                .frame(minWidth: 20, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // The proportional fill IS the bar chart: it sits behind the row
        // instead of stealing a column from the names.
        .background(
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(accent.opacity(0.16))
                    .frame(width: max(4, geo.size.width * fraction))
            }
        )
    }

    /// Artists read as circles, songs as rounded squares — matching how the
    /// rest of the shell distinguishes them.
    private var shape: AnyShape {
        row.circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder private var cover: some View {
        if let s = row.artworkURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: coverPlaceholder
                }
            }
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: row.circular ? "person.fill" : "music.note")
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.35))
        }
    }
}

// MARK: - Formatting

enum StatsFormat {
    /// "3 sa 12 dk" / "47 dk" / "2 dk". Seconds are noise at this scale.
    static func duration(_ ms: Int64) -> String {
        let minutes = Int(ms / 60_000)
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return mins > 0 ? "\(hours) sa \(mins) dk" : "\(hours) sa" }
        return "\(mins) dk"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f
    }()

    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f
    }()

    static func dayLabel(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func fullDayLabel(_ date: Date) -> String { fullDayFormatter.string(from: date) }
}
