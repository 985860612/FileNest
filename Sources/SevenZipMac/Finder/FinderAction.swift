import Foundation

enum FinderAction: Sendable, Equatable {
    case compress(ArchiveFormat)
    case extract
    case browse

    var title: String {
        switch self {
        case .compress: "创建归档"
        case .extract: "解压归档"
        case .browse: "查看归档"
        }
    }

    var subtitle: String {
        switch self {
        case .compress: "设置参数后开始压缩"
        case .extract: "确认内容与目标位置后开始解压"
        case .browse: "浏览归档内容，需要时可选择位置解压"
        }
    }

    var systemImage: String {
        switch self {
        case .compress: "archivebox.fill"
        case .extract: "archivebox"
        case .browse: "doc.text.magnifyingglass"
        }
    }
}

struct FinderActionRequest: Sendable {
    let action: FinderAction
    let urls: [URL]
}
