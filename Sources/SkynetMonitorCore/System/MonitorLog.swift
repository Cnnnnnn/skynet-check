import os

enum MonitorLog {
    private static let subsystem = "io.skynet.login-monitor"

    static let store = Logger(subsystem: subsystem, category: "store")
    static let runner = Logger(subsystem: subsystem, category: "runner")
    static let notifier = Logger(subsystem: subsystem, category: "notifier")
    static let cli = Logger(subsystem: subsystem, category: "cli")
}
