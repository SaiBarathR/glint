import AppKit
import GlintCore

// Helper mode: parse untrusted YAML for the main app and exit (see YAMLHelper).
if CommandLine.arguments.contains(YAMLHelper.flag) { YAMLHelper.runChild() }
ExtensionLoader.isolatedYAMLParser = YAMLHelper.parse

// Scripts that exit without reading their input must not kill Glint with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
