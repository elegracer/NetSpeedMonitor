import AppKit

@main
struct MenuBarIconGeneratorTests {
    static func main() {
        let font = NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        let samples = [
            "↑ 999.99 MB/s\n↓ 999.99 MB/s",
            "↑ 999.99 Mb/s\n↓ 999.99 Mb/s",
            "↓ 999.99 TB/s",
            "↑ 999.99 Tb/s",
            "↑ 1023.99 MB/s\n↓ 1023.99 MB/s",
        ]
        for text in samples {
            let size = MenuBarIconGenerator.imageSize(for: text, font: font)
            let widest = text.components(separatedBy: "\n").map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max()!
            precondition(size.width >= widest + MenuBarIconGenerator.horizontalPadding * 2, "status item width truncates text")
            precondition(MenuBarIconGenerator.generateIcon(text: text, font: font).size == size)
        }
        precondition(MenuBarIconGenerator.imageSize(for: samples[0], font: font).height == 22)
        precondition(MenuBarIconGenerator.imageSize(for: samples[2], font: font).height == 18)
        print("Menu bar icon layout tests passed")
    }
}
