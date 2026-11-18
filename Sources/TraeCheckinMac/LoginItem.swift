import Foundation
import ServiceManagement

/// 开机自启（macOS 13+ 的 SMAppService；需要 app bundle 与稳定的 bundle id）
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 返回 nil 表示成功，否则是错误描述
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
