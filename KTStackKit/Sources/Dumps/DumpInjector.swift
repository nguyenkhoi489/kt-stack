import Foundation

public final class DumpInjector {
    private let paths: AppSupportPaths

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
    }

    public func enable(version: String, port: UInt16) throws {
        try writePrependFile(port: port)
        var ini = try PHPIniStore(paths: paths).read(version: version)
        ini = setIniKey("auto_prepend_file", value: paths.dumpsPrependFile.path, in: ini)
        try PHPIniStore(paths: paths).write(version: version, contents: ini)
    }

    public func disable(version: String) throws {
        var ini = try PHPIniStore(paths: paths).read(version: version)
        ini = removeKTStackPrepend(from: ini)
        try PHPIniStore(paths: paths).write(version: version, contents: ini)
    }

    public func isEnabled(version: String) -> Bool {
        guard let ini = try? PHPIniStore(paths: paths).read(version: version) else { return false }
        return ini.contains(paths.dumpsPrependFile.path)
    }

    public func cleanupPrependFile() {
        try? FileManager.default.removeItem(at: paths.dumpsPrependFile)
    }

    private func writePrependFile(port: UInt16) throws {
        let dir = paths.dumpsPrependFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let php = Self.prependTemplate.replacingOccurrences(of: "KTSTACK_PORT", with: String(port))
        try php.write(to: paths.dumpsPrependFile, atomically: true, encoding: .utf8)
    }

    private func setIniKey(_ key: String, value: String, in ini: String) -> String {
        let line = "\(key) = \(value)"
        if ini.contains(line) { return ini }
        return ini + "\n\(line)\n"
    }

    private func removeKTStackPrepend(from ini: String) -> String {
        let prependPath = paths.dumpsPrependFile.path
        let filtered = ini.components(separatedBy: "\n").filter { !$0.contains(prependPath) }
        return filtered.joined(separator: "\n")
    }

    private static let prependTemplate = #"""
    <?php
    if (!function_exists('__ktstack_serialize')) {
        function __ktstack_serialize($v, $d = 0) {
            if ($d > 6) return ['type' => 'truncated'];
            if (is_null($v))   return ['type' => 'null'];
            if (is_bool($v))   return ['type' => 'bool',  'value' => $v];
            if (is_int($v))    return ['type' => 'int',   'value' => $v];
            if (is_float($v))  return ['type' => 'float', 'value' => $v];
            if (is_string($v)) return ['type' => 'string','value' => $v,'length' => strlen($v)];
            if (is_array($v)) {
                $items = [];
                foreach (array_slice($v, 0, 50, true) as $k => $i)
                    $items[] = ['key' => (string)$k, 'value' => __ktstack_serialize($i, $d + 1)];
                return ['type' => 'array', 'count' => count($v), 'items' => $items];
            }
            if (is_object($v)) {
                $props = [];
                foreach ((array)$v as $k => $i) {
                    $clean = preg_replace('/^\x00[^\x00]*\x00/', '', $k);
                    $props[] = ['key' => $clean, 'value' => __ktstack_serialize($i, $d + 1)];
                }
                return ['type' => 'object', 'class' => get_class($v), 'properties' => $props];
            }
            return ['type' => 'resource'];
        }
    }
    if (!function_exists('__ktstack_send')) {
        function __ktstack_send($var) {
            $self = __FILE__;
            $bt = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 10);
            $caller = ['file' => '', 'line' => 0];
            foreach ($bt as $f) {
                if (isset($f['file']) && $f['file'] !== $self) {
                    $caller = $f; break;
                }
            }
            $payload = json_encode([
                'timestamp' => microtime(true),
                'file'      => $caller['file'] ?? '',
                'line'      => $caller['line'] ?? 0,
                'value'     => __ktstack_serialize($var),
            ], JSON_UNESCAPED_UNICODE);
            $fp = @fsockopen('127.0.0.1', KTSTACK_PORT, $errno, $errstr, 1);
            if ($fp) { fwrite($fp, $payload . "\n"); fclose($fp); }
        }
    }
    if (!function_exists('dump')) {
        function dump() {
            $vars = func_get_args();
            foreach ($vars as $var) { __ktstack_send($var); }
            return count($vars) === 1 ? reset($vars) : $vars;
        }
    }
    if (!function_exists('dd')) {
        function dd() {
            foreach (func_get_args() as $var) { __ktstack_send($var); }
            exit(1);
        }
    }
    """#
}
