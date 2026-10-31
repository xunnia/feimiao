import SwiftUI
import UIKit
import ImageIO
import QuickLook
import MarkdownUI

/// Markdown parsing stays in CommonMark; model-provided images never auto-load.
struct AssistantMarkdownBody: View {
    let text: String
    var secondary = false
    @AppThemeContext private var theme
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 16

    var body: some View {
        Markdown(text)
            .markdownTheme(.basic)
            .markdownTextStyle { FontSize(secondary ? bodyFontSize * 0.875 : bodyFontSize); ForegroundColor(secondary ? .secondary : .primary) }
            .markdownTextStyle(\.link) { ForegroundColor(Color.accentColor) }
            .markdownImageProvider(AssistantNoRemoteImageProvider())
            .markdownInlineImageProvider(AssistantNoRemoteInlineImageProvider())
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: 0, bottom: 12)
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal) {
                    configuration.label.fixedSize(horizontal: true, vertical: false)
                }
                .markdownTableBorderStyle(.init(color: theme.hairline))
                .markdownMargin(top: 0, bottom: 12)
            }
            .markdownBlockStyle(\.tableCell) { configuration in
                configuration.label
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(configuration.language ?? "代码").font(.caption)
                        Spacer(minLength: 8)
                        Button {
                            UIPasteboard.general.string = configuration.content
                        } label: {
                            Image(systemName: "doc.on.doc").padding(10)
                        }
                        .buttonStyle(.plain).accessibilityLabel("复制代码")
                    }
                    .foregroundStyle(.secondary).padding(.leading, 12)
                    ScrollView(.horizontal) {
                        configuration.label
                            .fixedSize(horizontal: true, vertical: false)
                            .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.85)) }
                            .padding(.horizontal, 12).padding(.bottom, 12)
                    }
                }
                .appThemeInput()
                .markdownMargin(top: 0, bottom: 12)
            }
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                AssistantReadingPolicy.isWebURL(url) ? .systemAction : .discarded
            })
    }
}

struct AssistantNoRemoteImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Image(systemName: "photo").foregroundStyle(.secondary)
            .accessibilityLabel("回答中的图片未自动加载")
    }
}

struct AssistantNoRemoteInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        Image(systemName: "photo")
    }
}

enum AssistantReadingPolicy {
    static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") &&
            !(url.host ?? "").isEmpty
    }
}

struct AssistantThinkingSummary: View {
    let summary: String
    let seconds: Int?
    var isThinking = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    TimelineView(.animation(minimumInterval: 0.1, paused: !isThinking || reduceMotion)) { timeline in
                        Text(isThinking ? "正在思考" : (seconds.map { "处理了 \($0)s" } ?? "思考摘要"))
                            .opacity(isThinking && !reduceMotion
                                ? 0.78 + 0.22 * sin(timeline.date.timeIntervalSinceReferenceDate * 2) : 1)
                    }
                    if !summary.isEmpty { Image(systemName: "chevron.right")
                        .font(.caption).rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(summary.isEmpty)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                ScrollView {
                    AssistantMarkdownBody(text: summary, secondary: true)
                }.frame(maxHeight: 280)
                Divider()
            }
        }
        .onChange(of: isThinking) { old, current in
            if old && !current { expanded = false }
        }
    }
}

struct AssistantSourcesButton: View {
    let sources: [AIChatSource]
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 5) {
                HStack(spacing: -6) {
                    ForEach(Array(sources.prefix(3))) { source in
                        Text(String((URL(string: source.url)?.host ?? "源").prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .medium))
                            .frame(width: 20, height: 20)
                            .background(.background, in: .circle)
                            .overlay(Circle().stroke(.secondary.opacity(0.25), lineWidth: 0.5))
                    }
                }
                Text("\(sources.count) 个来源").font(.caption)
            }.foregroundStyle(.secondary).fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sources.count) 个来源")
        .sheet(isPresented: $presented) {
            AssistantSourcesSheet(sources: sources)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct AssistantSourcesSheet: View {
    let sources: [AIChatSource]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        if let url = URL(string: source.url), AssistantReadingPolicy.isWebURL(url) {
                            Link(destination: url) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "doc.text").frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.title.isEmpty ? (url.host ?? "网页") : source.title)
                                            .font(.body.weight(.medium)).foregroundStyle(.primary)
                                        Text(url.host ?? "").font(.caption).foregroundStyle(.secondary)
                                        if !source.snippet.isEmpty {
                                            Text(source.snippet).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.up.right").font(.caption)
                                }.padding(.vertical, 12)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }.padding(.horizontal, 20)
            }
            .liquidGlassCanvas().navigationTitle("来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }}
            .liquidGlassChrome()
        }
    }
}

struct AssistantAttachmentStrip: View {
    let attachments: [AIChatAttachment]
    var onRemove: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let side = max(1, (geometry.size.width - 16) / 3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AssistantAttachmentTile(attachment: attachment)
                            .frame(width: side, height: side)
                            .overlay(alignment: .topTrailing) {
                                if let onRemove {
                                    Button { onRemove(attachment.id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.7))
                                            .padding(5)
                                    }.buttonStyle(.plain)
                                    .accessibilityLabel("移除 \(attachment.name)")
                                }
                            }
                    }
                }
            }
        }
        .aspectRatio(3, contentMode: .fit)
    }
}

private struct AssistantAttachmentTile: View {
    let attachment: AIChatAttachment
    @State private var thumbnail: UIImage?
    @State private var previewURL: URL?
    @State private var missing = false

    var body: some View {
        Button {
            if let url = AttachmentStore.url(for: attachment.metadata.relativePath),
               FileManager.default.fileExists(atPath: url.path) {
                previewURL = url
            } else { missing = true }
        } label: {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: attachment.isImage ? "photo" : "doc.text")
                        Text(attachment.name).font(.caption).lineLimit(2)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).appThemeInput()
                }
            }
            .clipped().clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityLabel("查看 \(attachment.name)")
        .quickLookPreview($previewURL)
        .alert("附件已缺失或无法读取", isPresented: $missing) { Button("好", role: .cancel) {} }
        .task(id: attachment.id) {
            guard attachment.isImage,
                  let url = AttachmentStore.url(for: attachment.metadata.relativePath) else { return }
            let image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 384,
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: image)
            }.value
            if !Task.isCancelled { thumbnail = image }
        }
    }
}
