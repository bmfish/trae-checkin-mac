import SwiftUI

// MARK: - 主窗口（深绿描边卡片 + 大号积分 + 余额进度条）

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private enum Palette {
    static let bg = Color(hex: 0x0A0E0B)
    static let cardTop = Color(hex: 0x0F1B14)
    static let cardBottom = Color(hex: 0x0A120D)
    static let cardStroke = Color(hex: 0x1C4A33)
    static let track = Color(hex: 0x1A211C)
    static let fg = Color(hex: 0xE8F2EC)
    static let muted = Color(hex: 0x7C8A80)
    static let dim = Color(hex: 0x5C6A60)
    static let accent = Color(hex: 0x3DF08C)
    static let danger = Color(hex: 0xFF7B72)
    static let onAccent = Color(hex: 0x06130C)
    static let field = Color(hex: 0x0E1511)
    static let buttonBg = Color(hex: 0x14181A)
    static let buttonStroke = Color(hex: 0x2A3136)
    static let divider = Color(hex: 0x1B221D)
}

struct ContentView: View {

    @ObservedObject var model: UsageModel
    @State private var hourText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.accent.opacity(0.55)).frame(height: 1)
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if model.loaded && model.accounts.isEmpty {
                        emptyState
                    }
                    ForEach(model.accounts, id: \.uid) { account in
                        card(account)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            infoRows
            footer
        }
        .background(Palette.bg)
        .frame(width: 520)
        .onAppear { hourText = String(format: "%02d", model.startHour) }
        .onChange(of: model.startHour) { hour in
            hourText = String(format: "%02d", hour)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Trae 今日用量")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Palette.fg)
            Spacer()
            Text(UsageModel.dateText())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Palette.dim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("未发现 Trae 客户端凭据")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.fg.opacity(0.75))
            Text("请先登录 Trae 客户端")
                .font(.system(size: 11))
                .foregroundColor(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Palette.cardTop, Palette.cardBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.cardStroke, lineWidth: 1))
    }

    // MARK: 账号卡片

    private func card(_ account: ClientTraeAccount) -> some View {
        let item = model.usage.first(where: { $0.uid == account.uid })
        let signed = model.signedUIDs.contains(account.uid)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(groupedUID(account.uid))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundColor(Palette.fg)
                    .tracking(0.5)
                Spacer(minLength: 8)
                Text(account.sourceApp)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.muted)
                badge(signed: signed)
            }

            if let item, item.ok {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(UsageModel.money(item.credits))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Palette.accent)
                    Text("积分")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.muted)
                    Rectangle().fill(Palette.cardStroke).frame(width: 1, height: 22)
                        .padding(.horizontal, 6)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                    Text("\(item.sessions)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Palette.fg)
                    Text("会话")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.muted)
                }
                .padding(.top, 6)

                if let balance = item.balance {
                    HStack(spacing: 6) {
                        Text("余额")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.muted)
                        Text(UsageModel.money(balance))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(Palette.fg)
                        if let total = item.total {
                            Text("/").font(.system(size: 12)).foregroundColor(Palette.dim)
                            Text("总额")
                                .font(.system(size: 12))
                                .foregroundColor(Palette.muted)
                            Text(UsageModel.money(total))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(Palette.fg)
                        }
                    }
                    .padding(.top, 8)

                    if let total = item.total, total > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.track)
                                Capsule()
                                    .fill(Palette.accent)
                                    .frame(width: max(0, min(1, balance / total)) * geo.size.width)
                            }
                        }
                        .frame(height: 6)
                        .padding(.top, 10)
                    }
                }
            } else if let item, !item.message.isEmpty {
                Text(item.message)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.danger)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Palette.cardTop, Palette.cardBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.cardStroke, lineWidth: 1))
    }

    private func badge(signed: Bool) -> some View {
        Text(signed ? "已签" : "待签")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(signed ? Palette.accent : Palette.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(signed ? Palette.accent.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                Capsule().stroke(signed ? Palette.accent.opacity(0.55) : Palette.buttonStroke,
                                 lineWidth: 1)
            )
    }

    // MARK: 信息行

    private var infoRows: some View {
        VStack(spacing: 0) {
            infoRow("签到") {
                HStack(spacing: 6) {
                    Text(signedRatio)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Palette.fg)
                    if let summary = signBadge {
                        Text(summary.0)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(summary.1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(summary.1.opacity(0.12)))
                            .overlay(Capsule().stroke(summary.1.opacity(0.5), lineWidth: 1))
                    }
                    if !model.note.isEmpty {
                        Text(noteTail)
                            .font(.system(size: 12))
                            .foregroundColor(Palette.muted)
                            .lineLimit(1)
                    }
                }
            }
            infoRow("签到时间") {
                HStack(spacing: 8) {
                    hourControl
                    Text(String(format: "点后  %02d:00–%02d:59 随机一分钟",
                                model.startHour, model.startHour))
                        .font(.system(size: 12))
                        .foregroundColor(Palette.muted)
                }
            }
            infoRow("开机自启") {
                HStack(spacing: 6) {
                    Button(model.autostart ? "已开启" : "未开启") {
                        model.toggleAutostart()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(model.autostart ? Palette.accent : Palette.fg)

                    if !model.tip.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundColor(Palette.dim)
                        Text(model.tip)
                            .font(.system(size: 12))
                            .foregroundColor(Palette.dim)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func infoRow<Content: View>(_ label: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Palette.muted)
                .frame(width: 60, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(height: 38)
    }

    // MARK: 签到时间控件

    private var hourControl: some View {
        HStack(spacing: 0) {
            TextField("", text: $hourText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(Palette.accent)
                .multilineTextAlignment(.center)
                .frame(width: 38, height: 26)
                .onSubmit(commitHour)
            Rectangle().fill(Palette.cardStroke).frame(width: 1, height: 26)
            VStack(spacing: 0) {
                stepButton("chevron.up") { model.setStartHour(model.startHour + 1) }
                stepButton("chevron.down") { model.setStartHour(model.startHour - 1) }
            }
            .frame(width: 20)
        }
        .background(Palette.field)
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.cardStroke, lineWidth: 1))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Palette.muted)
                .frame(width: 20, height: 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 底栏

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.divider).frame(height: 1)
            HStack(spacing: 10) {
                Text("by bmfish · github.com/bmfish/trae-checkin-win")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    model.refresh()
                } label: {
                    Text("刷新")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(model.busy ? Palette.dim : Palette.fg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.buttonBg))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(Palette.buttonStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)

                Button {
                    model.checkin()
                } label: {
                    Text(signTitle())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.accent.opacity(model.allSigned ? 0.62 : 1))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Palette.accent.opacity(model.allSigned ? 0.05 : 0.10))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(Palette.accent.opacity(model.allSigned ? 0.35 : 0.7),
                                    lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(model.signing || model.allSigned)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: 文案

    private var signedRatio: String {
        let signed = model.signedUIDs.count
        let total = model.accounts.count
        return total == 0 ? "0/0" : "\(signed)/\(total)"
    }

    /// 徽章文案与颜色：全部已签 → 已签（绿），否则 待签（灰）
    private var signBadge: (String, Color)? {
        guard !model.accounts.isEmpty else { return nil }
        return model.allSigned ? ("已签", Palette.accent) : ("待签", Palette.muted)
    }

    /// note 去掉「签到：x/y 已签」前缀，只留获得与计划时间
    private var noteTail: String {
        var text = model.note
        if let range = text.range(of: " · ") {
            text = String(text[range.upperBound...])
        }
        return text
    }

    private func signTitle() -> String {
        if model.signing { return "签到中…" }
        if !model.loaded { return "立即签到" }
        if model.accounts.isEmpty { return "无账号" }
        if model.allSigned { return "今日已签 ✓" }
        return "立即签到"
    }

    private func groupedUID(_ uid: String) -> String {
        var chunks: [String] = []
        var rest = Array(uid)
        while !rest.isEmpty {
            let take = min(4, rest.count)
            chunks.insert(String(rest.suffix(take)), at: 0)
            rest.removeLast(take)
        }
        return chunks.joined(separator: " ")
    }

    private func commitHour() {
        if let value = Int(hourText) {
            model.setStartHour(min(23, max(0, value)))
        } else {
            hourText = String(format: "%02d", model.startHour)
        }
    }
}
