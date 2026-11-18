import Foundation
import JavaScriptCore

/// Runs JavaScript actions in a fresh JavaScriptCore context with a `glint` API object
/// (also exposed as `popclip` so scripts written for that API keep working).
public enum JavaScriptRunner {
    public struct ModuleInfo {
        public var config: [String: Any] = [:]
        public var actions: [[String: Any]] = []
        public var dynamic = false
        public var error: String?
    }

    public struct Environment {
        public var input: ActionInput
        public var context: SelectionContext
        public var modifiers: ModifierState
        public var options: [String: String]
        public var optionSpecs: [OptionSpec]
        public var extensionID: String
        public var bundleURL: URL?

        public init(input: ActionInput, context: SelectionContext, modifiers: ModifierState, options: [String: String],
                    optionSpecs: [OptionSpec] = [], extensionID: String, bundleURL: URL?) {
            self.input = input; self.context = context; self.modifiers = modifiers; self.options = options
            self.optionSpecs = optionSpecs; self.extensionID = extensionID; self.bundleURL = bundleURL
        }
    }

    static let prelude = #"""
    var module = { exports: {} };
    var exports = module.exports;
    var console = { log: function() { __native.log(Array.prototype.map.call(arguments, function(a) {
        return (typeof a === 'object') ? JSON.stringify(a) : String(a); }).join(' ')); } };
    console.error = console.log; console.warn = console.log; console.info = console.log;
    var print = console.log;
    var glint = {
      input: __env.input, context: __env.context, modifiers: __env.modifiers, options: __env.options,
      pasteText: function(t, o) { __native.pasteText(String(t), !!(o && o.restore)); },
      copyText: function(t) { __native.copyText(String(t)); },
      openUrl: function(u, o) { __native.openUrl(String(u), !!(o && o.activate === false), (o && o.app) ? String(o.app) : ""); },
      showText: function(t, o) { __native.showText(String(t), !!(o && o.preview)); },
      showSuccess: function() { __native.showStatus(true); },
      showFailure: function() { __native.showStatus(false); },
      showSettings: function() { __native.showSettings(); },
      pressKey: function(k, m) {
        if (typeof m === 'number' && typeof k === 'number') { k = { keyCode: k, modifiers: m }; }
        __native.pressKey(k);
      },
      performCommand: function(c) { __native.performCommand(String(c)); },
      appear: function() {},
      share: function(service, items) {},
    };
    var popclip = glint;
    var pasteboard = { get text() { return __native.clipboardText(); }, set text(v) { __native.copyText(String(v)); } };
    var util = {
      base64Encode: function(s, o) { var r = __native.base64Encode(String(s)); if (o && o.urlSafe) { r = r.replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''); } return r; },
      base64Decode: function(s) { return __native.base64Decode(String(s).replace(/-/g,'+').replace(/_/g,'/')); },
      sleep: function(ms) { __native.sleep(ms); return Promise.resolve(); },
      localize: function(s) { return s; },
      htmlToMarkdown: function(h) { return __native.htmlToText(String(h)); },
      htmlToRtf: function(h) { return h; },
      buildQuery: function(o) { return Object.keys(o).map(function(k) { return encodeURIComponent(k) + '=' + encodeURIComponent(o[k]); }).join('&'); },
      timeoutPromise: function(ms) { return new Promise(function(r) { setTimeout(r, ms); }); },
    };
    function setTimeout(fn, ms) { __native.setTimeout(fn, ms || 0); return 0; }
    function sleep(ms) { return util.sleep(ms); }
    function require(path) {
      if (path === 'axios') { return __axios; }
      var src = __native.readModule(String(path));
      if (src === null || src === undefined) { throw new Error('Cannot find module ' + path); }
      var m = { exports: {} };
      (new Function('module', 'exports', 'require', src))(m, m.exports, require);
      return m.exports;
    }
    function fetch(url, init) {
      init = init || {};
      return __native.fetch(String(url), String(init.method || 'GET'), init.headers || {},
                            init.body === undefined ? null : String(init.body)).then(function(r) {
        return { status: r.status, ok: r.status >= 200 && r.status < 300, headers: r.headers,
                 text: function() { return Promise.resolve(r.body); },
                 json: function() { return Promise.resolve(JSON.parse(r.body)); } };
      });
    }
    var __axios = {
      request: function(cfg) {
        var url = cfg.url;
        if (cfg.params) { url += (url.indexOf('?') < 0 ? '?' : '&') + util.buildQuery(cfg.params); }
        var body = cfg.data === undefined ? undefined : (typeof cfg.data === 'string' ? cfg.data : JSON.stringify(cfg.data));
        var headers = cfg.headers || {};
        if (cfg.data !== undefined && typeof cfg.data !== 'string' && !headers['Content-Type']) { headers['Content-Type'] = 'application/json'; }
        return fetch(url, { method: cfg.method || 'GET', headers: headers, body: body }).then(function(r) {
          return r.text().then(function(t) {
            var data = t; try { data = JSON.parse(t); } catch (e) {}
            if (!r.ok) { var err = new Error('Request failed with status ' + r.status); err.response = { status: r.status, data: data }; throw err; }
            return { status: r.status, data: data, headers: r.headers };
          });
        });
      },
      get: function(url, cfg) { cfg = cfg || {}; cfg.url = url; cfg.method = 'GET'; return __axios.request(cfg); },
      post: function(url, data, cfg) { cfg = cfg || {}; cfg.url = url; cfg.data = data; cfg.method = 'POST'; return __axios.request(cfg); },
      put: function(url, data, cfg) { cfg = cfg || {}; cfg.url = url; cfg.data = data; cfg.method = 'PUT'; return __axios.request(cfg); },
      delete: function(url, cfg) { cfg = cfg || {}; cfg.url = url; cfg.method = 'DELETE'; return __axios.request(cfg); },
      create: function(defaults) {
        var inst = Object.create(__axios);
        inst.request = function(cfg) {
          var merged = Object.assign({}, defaults, cfg);
          if (defaults.baseURL && cfg.url && cfg.url.indexOf('http') !== 0) { merged.url = defaults.baseURL.replace(/\/$/, '') + '/' + cfg.url.replace(/^\//, ''); }
          merged.headers = Object.assign({}, defaults.headers || {}, cfg.headers || {});
          return __axios.request(merged);
        };
        inst.get = function(url, cfg) { cfg = cfg || {}; cfg.url = url; cfg.method = 'GET'; return inst.request(cfg); };
        inst.post = function(url, data, cfg) { cfg = cfg || {}; cfg.url = url; cfg.data = data; cfg.method = 'POST'; return inst.request(cfg); };
        return inst;
      }
    };
    """#

    // MARK: - Context

    final class Bridge {
        let env: Environment?
        weak var host: ActionHost?
        init(env: Environment?, host: ActionHost?) { self.env = env; self.host = host }
    }

    /// Limits how long JavaScript may run in `ctx` (uses JavaScriptCore's execution time limit when available).
    static func applyTimeLimit(_ ctx: JSContext, seconds: Double) {
        typealias SetLimit = @convention(c) (JSContextGroupRef?, Double, OpaquePointer?, UnsafeMutableRawPointer?) -> Void
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else { return }
        let fn = unsafeBitCast(sym, to: SetLimit.self)
        fn(JSContextGetGroup(ctx.jsGlobalContextRef), seconds, nil, nil)
    }

    /// True when `source` parses as a script (no top-level `return`).
    static func parses(_ source: String, in ctx: JSContext) -> Bool {
        let str = JSStringCreateWithCFString(source as CFString)
        defer { JSStringRelease(str) }
        return JSCheckScriptSyntax(ctx.jsGlobalContextRef, str, nil, 1, nil)
    }

    /// - Parameter sandboxed: no network, timers or sleeping. Used whenever code runs without the user
    ///   having asked for an action (describing a module before install, building the bar).
    static func makeContext(env: Environment?, host liveHost: ActionHost?, errors: Box<String?>, timeLimit: Double = 30,
                            sandboxed: Bool = false, expired: Box<Bool> = Box(false)) -> JSContext {
        // Once the action has timed out, late continuations (e.g. a fetch resolving) must not reach the host.
        var host: ActionHost? { expired.value ? nil : liveHost }
        let allowSleep = !sandboxed
        let ctx = JSContext()!
        applyTimeLimit(ctx, seconds: timeLimit)
        ctx.exceptionHandler = { _, exc in
            let msg = exc?.toString() ?? "error"
            let line = exc?.forProperty("line")?.toString() ?? ""
            errors.value = line.isEmpty || line == "undefined" ? msg : "\(msg) (line \(line))"
        }
        let native = JSValue(newObjectIn: ctx)!
        let extID = env?.extensionID ?? ""

        let pasteText: @convention(block) (String, Bool) -> Void = { t, restore in host?.pasteText(t, restoreClipboard: restore) }
        let copyText: @convention(block) (String) -> Void = { t in host?.copyText(t) }
        let openUrl: @convention(block) (String, Bool, String) -> Void = { u, bg, app in
            if let url = URL(string: u) ?? URL(string: u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
                host?.openURL(url, background: bg, appBundleID: app.isEmpty ? nil : app)
            }
        }
        let showText: @convention(block) (String, Bool) -> Void = { t, p in host?.showText(t, preview: p) }
        let showStatus: @convention(block) (Bool) -> Void = { ok in host?.showStatus(success: ok) }
        let showSettings: @convention(block) () -> Void = { host?.showSettings(extensionID: extID) }
        let pressKey: @convention(block) (JSValue) -> Void = { v in
            var any: Any?
            if v.isString { any = v.toString() }
            else if v.isNumber { any = v.toNumber() }
            else { any = v.toDictionary() }
            if let any, let combo = KeyCombo(config: any) { host?.pressKey(combo) }
        }
        let performCommand: @convention(block) (String) -> Void = { c in
            let map: [String: StandardCommand] = ["cut": .cut, "copy": .copy, "paste": .paste, "pasteplain": .pasteMatchStyle,
                                                  "pastematchstyle": .pasteMatchStyle, "selectall": .selectAll,
                                                  "undo": .undo, "redo": .redo]
            if let cmd = map[normalizeKey(c)] { host?.performCommand(cmd) }
        }
        let log: @convention(block) (String) -> Void = { m in host?.log(m, extensionID: extID) }
        let b64e: @convention(block) (String) -> String = { Data($0.utf8).base64EncodedString() }
        let b64d: @convention(block) (String) -> String = { s in
            var str = s
            while str.count % 4 != 0 { str += "=" }
            return Data(base64Encoded: str).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        // Wall-clock deadline: the execution time limit only counts CPU time, so sleeping must stop here.
        let deadline = Date().addingTimeInterval(timeLimit)
        let sleep: @convention(block) (Double) -> Void = { ms in
            guard allowSleep else { return }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                if let c = JSContext.current() { c.exception = JSValue(newErrorFromMessage: "Timed out", in: c) }
                return
            }
            Thread.sleep(forTimeInterval: min(min(ms, 10_000) / 1000, remaining))
        }
        let setTimeoutFn: @convention(block) (JSValue, Double) -> Void = { fn, ms in
            // Timers obey the same wall-clock deadline as the action: nothing keeps running afterwards.
            guard !sandboxed, Date().addingTimeInterval(ms / 1000) < deadline else { return }
            // Keep the host alive until the callback has run: it may call glint.* after the action returned.
            DispatchQueue.global().asyncAfter(deadline: .now() + ms / 1000) {
                guard Date() < deadline else { return }
                withExtendedLifetime(liveHost) { _ = fn.call(withArguments: []) }
            }
        }
        let htmlToText: @convention(block) (String) -> String = { html in
            html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        let clipboardText: @convention(block) () -> String = {
            host?.currentClipboardText() ?? env?.context.clipboardText ?? ""
        }
        let bundleURL = env?.bundleURL
        let readModule: @convention(block) (String) -> JSValue? = { path in
            guard let bundleURL else { return JSValue(nullIn: JSContext.current()) }
            var p = path
            if p.hasPrefix("./") { p.removeFirst(2) }
            var url = bundleURL.appendingPathComponent(p)
            if url.pathExtension.isEmpty { url.appendPathExtension("js") }
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { return JSValue(nullIn: JSContext.current()) }
            return JSValue(object: src, in: JSContext.current())
        }
        let fetch: @convention(block) (String, String, JSValue, JSValue) -> JSValue = { urlString, method, headers, body in
            let ctx = JSContext.current()!
            return JSValue(newPromiseIn: ctx) { resolve, reject in
                if sandboxed {
                    reject?.call(withArguments: ["Network access isn't available here"]); return
                }
                guard let url = URL(string: urlString) else {
                    reject?.call(withArguments: ["Invalid URL: \(urlString)"]); return
                }
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.timeoutInterval = 30
                if let h = headers.toDictionary() as? [String: Any] {
                    for (k, v) in h { request.setValue("\(v)", forHTTPHeaderField: k) }
                }
                if !body.isNull, !body.isUndefined, let s = body.toString() { request.httpBody = Data(s.utf8) }
                URLSession.shared.dataTask(with: request) { data, response, error in
                    // Promise continuations may call glint.* after the action returned; keep the host alive.
                    defer { withExtendedLifetime(liveHost) {} }
                    if let error { reject?.call(withArguments: [error.localizedDescription]); return }
                    let http = response as? HTTPURLResponse
                    var hdrs: [String: String] = [:]
                    for (k, v) in http?.allHeaderFields ?? [:] { hdrs["\(k)".lowercased()] = "\(v)" }
                    let result: [String: Any] = ["status": http?.statusCode ?? 0,
                                                 "body": data.map { String(decoding: $0, as: UTF8.self) } ?? "",
                                                 "headers": hdrs]
                    resolve?.call(withArguments: [result])
                }.resume()
            }
        }

        let natives: [(String, Any)] = [("pasteText", pasteText), ("copyText", copyText), ("openUrl", openUrl),
                                        ("showText", showText), ("showStatus", showStatus), ("showSettings", showSettings),
                                        ("pressKey", pressKey), ("performCommand", performCommand), ("log", log),
                                        ("base64Encode", b64e), ("base64Decode", b64d), ("sleep", sleep),
                                        ("setTimeout", setTimeoutFn), ("htmlToText", htmlToText),
                                        ("clipboardText", clipboardText), ("readModule", readModule), ("fetch", fetch)]
        for (name, block) in natives { native.setObject(block, forKeyedSubscript: name as NSString) }
        ctx.setObject(native, forKeyedSubscript: "__native" as NSString)
        ctx.setObject(envObject(env), forKeyedSubscript: "__env" as NSString)
        ctx.evaluateScript(prelude)
        return ctx
    }

    static func envObject(_ env: Environment?) -> [String: Any] {
        guard let env else {
            return ["input": ["text": "", "matchedText": "", "regexResult": [], "data": ["urls": [], "emails": [], "paths": []]],
                    "context": [:], "modifiers": ModifierState().asDictionary, "options": [:]]
        }
        let i = env.input
        var options: [String: Any] = [:]
        for (k, v) in env.options {
            if env.optionSpecs.first(where: { $0.id == k })?.kind == .boolean { options[k] = (v == "1" || v == "true") }
            else { options[k] = v }
        }
        return [
            "input": ["text": i.matchedText, "fullText": i.text, "matchedText": i.matchedText, "regexResult": i.regexGroups,
                      "html": i.html ?? "", "isRichText": i.html != nil, "markdown": i.text,
                      "data": ["urls": i.urls, "emails": i.emails, "paths": i.paths, "nonHttpUrls": [String](),
                               "webUrls": i.urls]],
            "context": ["appIdentifier": env.context.appBundleID ?? "", "appName": env.context.appName ?? "",
                        "hasFormatting": env.context.canFormat, "canPaste": env.context.canPaste,
                        "canCut": env.context.canCut, "canCopy": env.context.canCopy,
                        "browserUrl": env.context.sourceURL ?? "", "browserTitle": ""],
            "modifiers": env.modifiers.asDictionary,
            "options": options,
        ]
    }

    final class Box<T> { var value: T; init(_ v: T) { value = v } }

    // MARK: - Module description

    public static func describeModule(source: String) -> ModuleInfo {
        let errors = Box<String?>(nil)
        let ctx = makeContext(env: nil, host: nil, errors: errors, timeLimit: 1, sandboxed: true)
        ctx.evaluateScript(source)
        var info = ModuleInfo()
        let exports = moduleExports(ctx)
        for key in ["name", "identifier", "icon", "description", "requirements", "regex", "after", "apps", "app",
                    "excludedApps", "stayVisible", "captureHtml"] {
            if let v = exports.forProperty(key), !v.isUndefined, !v.isNull, let obj = v.toObject() { info.config[key] = obj }
        }
        if let opts = exports.forProperty("options"), opts.isArray, let arr = opts.toArray() { info.config["options"] = arr }
        let actions = exports.forProperty("actions")
        let single = exports.forProperty("action")
        if let actions, actions.isArray {
            let count = Int(actions.forProperty("length").toInt32())
            for i in 0..<count {
                info.actions.append(describeAction(actions.atIndex(i), fallbackTitle: info.config["name"] as? String))
            }
        } else if let actions, isFunction(actions) {
            info.dynamic = true
            info.actions.append(["title": info.config["name"] as? String ?? "Action", "dynamic": true])
        } else if let single, !single.isUndefined, !single.isNull {
            info.actions.append(describeAction(single, fallbackTitle: info.config["name"] as? String))
        }
        info.error = errors.value
        return info
    }

    static func isFunction(_ v: JSValue) -> Bool {
        v.context.objectForKeyedSubscript("Function")?.isNull == false && v.isInstance(of: v.context.objectForKeyedSubscript("Function"))
    }

    static func moduleExports(_ ctx: JSContext) -> JSValue {
        let m = ctx.objectForKeyedSubscript("module")!
        let e = m.forProperty("exports")!
        // Fall back to the global `exports` object if module.exports was left empty.
        if let keys = ctx.evaluateScript("Object.keys(module.exports).length")?.toInt32(), keys == 0 {
            return ctx.objectForKeyedSubscript("exports")
        }
        return e
    }

    static func describeAction(_ v: JSValue, fallbackTitle: String?) -> [String: Any] {
        var d: [String: Any] = [:]
        if isFunction(v) {
            d["title"] = fallbackTitle ?? "Action"
            return d
        }
        for key in ["title", "icon", "identifier", "requirements", "regex", "after", "apps", "excludedApps",
                    "stayVisible", "captureHtml", "description"] {
            if let p = v.forProperty(key), !p.isUndefined, !p.isNull, let obj = p.toObject() { d[key] = obj }
        }
        if d["title"] == nil { d["title"] = fallbackTitle ?? "Action" }
        return d
    }

    // MARK: - Running

    public enum Code {
        case inline(String)
        case module(source: String, actionIndex: Int)
    }

    /// Dynamic actions: calls `exports.actions(input, options, context)` and describes the returned actions.
    public static func populate(moduleSource: String, env: Environment) -> [[String: Any]] {
        let errors = Box<String?>(nil)
        // Runs while the bar is being built, so keep it short and never sleep.
        let ctx = makeContext(env: env, host: nil, errors: errors, timeLimit: 0.5, sandboxed: true)
        ctx.evaluateScript(moduleSource)
        let exports = moduleExports(ctx)
        guard let fn = exports.forProperty("actions"), isFunction(fn) else { return [] }
        let glint = ctx.objectForKeyedSubscript("glint")!
        guard let result = fn.call(withArguments: [glint.forProperty("input")!, glint.forProperty("options")!,
                                                   glint.forProperty("context")!]) else { return [] }
        var list: [JSValue] = []
        if result.isArray {
            for i in 0..<Int(result.forProperty("length").toInt32()) { list.append(result.atIndex(i)) }
        } else if result.isObject { list = [result] }
        return list.map { describeAction($0, fallbackTitle: nil) }
    }

    public static func run(_ code: Code, env: Environment, host: ActionHost?, dynamicIndex: Int? = nil,
                           dynamicTitle: String? = nil, timeout: TimeInterval = 30) async -> ActionOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<ActionOutcome, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let once = ResumeOnce(cont)
                let errors = Box<String?>(nil)
                let expired = Box(false)
                let ctx = makeContext(env: env, host: host, errors: errors, timeLimit: timeout, expired: expired)
                var value: JSValue?
                switch code {
                case .inline(let src):
                    if parses(src, in: ctx) {
                        value = ctx.evaluateScript(src)
                    } else {
                        // Scripts may use top-level `return` / `await`: run them as a function body.
                        let isAsync = src.contains("await")
                        value = ctx.evaluateScript("(\(isAsync ? "async " : "")function() {\n\(src)\n})()")
                    }
                case .module(let src, let index):
                    ctx.evaluateScript(src)
                    if errors.value == nil {
                        let exports = moduleExports(ctx)
                        var target: JSValue?
                        let glint = ctx.objectForKeyedSubscript("glint")!
                        let args: [Any] = [glint.forProperty("input")!, glint.forProperty("options")!, glint.forProperty("context")!]
                        if let actions = exports.forProperty("actions"), actions.isArray {
                            target = actions.atIndex(index)
                        } else if let actions = exports.forProperty("actions"), isFunction(actions) {
                            if let list = actions.call(withArguments: args) {
                                if list.isArray {
                                    // Input may differ from when the bar was built: find the clicked action by title.
                                    let count = Int(list.forProperty("length").toInt32())
                                    let byTitle = dynamicTitle.flatMap { title in
                                        (0..<count).map { list.atIndex($0)! }.first { $0.forProperty("title")?.toString() == title }
                                    }
                                    target = byTitle ?? list.atIndex(dynamicIndex ?? index)
                                } else {
                                    target = list
                                }
                            }
                        } else {
                            target = exports.forProperty("action")
                        }
                        if let t = target, !isFunction(t), let codeFn = t.forProperty("code"), isFunction(codeFn) { target = codeFn }
                        if let t = target, isFunction(t) {
                            value = t.call(withArguments: args)
                        } else if errors.value == nil {
                            errors.value = "Action \(index) has no code function"
                        }
                    }
                }
                if let err = errors.value { once.resume(.failure(err)); return }
                guard let value else { once.resume(.done); return }
                if value.isObject, let then = value.forProperty("then"), isFunction(then) {
                    let onResolve: @convention(block) (JSValue) -> Void = { v in once.resume(outcome(from: v)) }
                    let onReject: @convention(block) (JSValue) -> Void = { e in
                        let msg = e.forProperty("message").flatMap { $0.isUndefined ? nil : $0.toString() } ?? e.toString() ?? "error"
                        once.resume(.failure(msg))
                    }
                    value.invokeMethod("then", withArguments: [JSValue(object: onResolve, in: ctx)!, JSValue(object: onReject, in: ctx)!])
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if once.resume(.failure("Timed out after \(Int(timeout))s")) { expired.value = true }
                    }
                } else {
                    once.resume(outcome(from: value))
                }
            }
        }
    }

    static func outcome(from v: JSValue) -> ActionOutcome {
        if v.isUndefined || v.isNull { return .done }
        if v.isString { return .result(v.toString()) }
        if v.isNumber || v.isBoolean { return .result(v.toString()) }
        if v.isObject, let json = v.context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [v]),
           json.isString { return .result(json.toString()) }
        return .done
    }

    final class ResumeOnce {
        private var cont: CheckedContinuation<ActionOutcome, Never>?
        private let lock = NSLock()
        init(_ c: CheckedContinuation<ActionOutcome, Never>) { cont = c }
        /// Returns true when this call was the one that resumed.
        @discardableResult
        func resume(_ outcome: ActionOutcome) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let c = cont else { return false }
            c.resume(returning: outcome)
            cont = nil
            return true
        }
    }
}
