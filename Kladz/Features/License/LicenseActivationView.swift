import SwiftUI
import UIKit

struct LicenseActivationView: View {
    @ObservedObject var license: LicenseStore
    @State private var key = ""
    @State private var copied = false

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.97, blue: 0.95).ignoresSafeArea()
            Circle()
                .fill(KladzTheme.accent.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 2)
                .offset(x: 180, y: -330)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(KladzTheme.accent)
                        Text("Kladz")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Spacer()
                        Text("PLUS")
                            .font(.caption.weight(.heavy))
                            .tracking(1.5)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(KladzTheme.accentSecondary.opacity(0.35), in: Capsule())
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Din plats. Dina regler.")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-1)
                        Text("Aktivera Kladz med nyckeln du fått efter köp.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Label("En licensnyckel per enhet", systemImage: "key.fill")
                        Label("Nyckeln verifieras kryptografiskt", systemImage: "checkmark.shield.fill")
                        Label("Ingen inloggning behövs", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.black.opacity(0.06), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("DIN ENHETS-KOD")
                            .font(.caption.weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)
                        Text(license.deviceID)
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        Button {
                            UIPasteboard.general.string = license.deviceID
                            copied = true
                        } label: {
                            Label(copied ? "Kopierad" : "Kopiera enhetskod", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(KladzTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("AKTIVERINGSNYCKEL")
                            .font(.caption.weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $key)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 92)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.10), lineWidth: 1))
                        if let message = license.errorMessage {
                            Text(message)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }

                    Button {
                        license.activate(key)
                    } label: {
                        HStack {
                            Text("Aktivera Kladz")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(KladzTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text("Har du inte en nyckel än? Köp via den officiella Kladz-kanalen och använd enhetskoden ovan när du begär nyckeln.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Licensnyckeln låser upp den officiella appen. Eftersom projektkoden är öppen källkod kan en modifierad egenbyggd version ta bort kontrollen.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
