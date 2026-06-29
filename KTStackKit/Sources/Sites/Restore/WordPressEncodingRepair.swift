import Foundation

public struct WordPressEncodingRepair: Sendable {
    private let runner: InstallCommandRunner

    public init(php: URL, phpIni: URL?) {
        runner = InstallCommandRunner(php: php, phpIni: phpIni)
    }

    public func repair(
        database: String,
        tablePrefix: String,
        workDir: URL,
        emit: @Sendable (String) -> Void
    ) throws {
        let scriptURL = workDir.appendingPathComponent("kt-fix-encoding.php")
        try Data(Self.script.utf8).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        emit("Repairing text encoding…")
        let output = try runner.runPHP([scriptURL.path, database, tablePrefix], cwd: workDir)
        emit(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let script = #"""
    <?php
    error_reporting(E_ERROR);
    $db = $argv[1];
    $prefix = $argv[2];

    $pdo = new PDO("mysql:host=127.0.0.1;port=3306;dbname={$db};charset=utf8mb4", 'root', '',
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

    function utf8ToLatin1Bytes($s) {
        static $cp1252 = [
            0x20AC => 0x80, 0x201A => 0x82, 0x0192 => 0x83, 0x201E => 0x84, 0x2026 => 0x85,
            0x2020 => 0x86, 0x2021 => 0x87, 0x02C6 => 0x88, 0x2030 => 0x89, 0x0160 => 0x8A,
            0x2039 => 0x8B, 0x0152 => 0x8C, 0x017D => 0x8E, 0x2018 => 0x91, 0x2019 => 0x92,
            0x201C => 0x93, 0x201D => 0x94, 0x2022 => 0x95, 0x2013 => 0x96, 0x2014 => 0x97,
            0x02DC => 0x98, 0x2122 => 0x99, 0x0161 => 0x9A, 0x203A => 0x9B, 0x0153 => 0x9C,
            0x017E => 0x9E, 0x0178 => 0x9F,
        ];
        $out = '';
        $len = strlen($s);
        $i = 0;
        while ($i < $len) {
            $c = ord($s[$i]);
            if ($c < 0x80) { $out .= $s[$i]; $i++; continue; }
            if ($c >= 0xC0 && $c < 0xE0 && $i + 1 < $len) {
                $cp = (($c & 0x1F) << 6) | (ord($s[$i + 1]) & 0x3F);
                $i += 2;
            } elseif ($c >= 0xE0 && $c < 0xF0 && $i + 2 < $len) {
                $cp = (($c & 0x0F) << 12) | ((ord($s[$i + 1]) & 0x3F) << 6) | (ord($s[$i + 2]) & 0x3F);
                $i += 3;
            } elseif ($c >= 0xF0 && $i + 3 < $len) {
                $cp = (($c & 0x07) << 18) | ((ord($s[$i + 1]) & 0x3F) << 12)
                    | ((ord($s[$i + 2]) & 0x3F) << 6) | (ord($s[$i + 3]) & 0x3F);
                $i += 4;
            } else {
                return false;
            }
            if ($cp <= 0xFF) { $out .= chr($cp); }
            elseif (isset($cp1252[$cp])) { $out .= chr($cp1252[$cp]); }
            else { return false; }
        }
        return $out;
    }

    function fixStr($s) {
        if (!is_string($s) || $s === '') return $s;
        if (!mb_check_encoding($s, 'UTF-8')) return $s;
        $r = utf8ToLatin1Bytes($s);
        if ($r === false || $r === $s) return $s;
        if (!mb_check_encoding($r, 'UTF-8')) return $s;
        return $r;
    }

    function fixDeep($d) {
        if (is_string($d)) return fixStr($d);
        if (is_array($d)) {
            $o = [];
            foreach ($d as $k => $v) { $o[is_string($k) ? fixStr($k) : $k] = fixDeep($v); }
            return $o;
        }
        return $d;
    }

    function fixValue($v) {
        if (!is_string($v) || $v === '') return $v;
        $un = @unserialize($v, ['allowed_classes' => false]);
        if ($un !== false || $v === 'b:0;') {
            if (serialize($un) === $v) { return serialize(fixDeep($un)); }
            return $v;
        }
        return fixStr($v);
    }

    $cols = [
        ["{$prefix}posts", "ID", ["post_title", "post_content", "post_excerpt"]],
        ["{$prefix}postmeta", "meta_id", ["meta_value"]],
        ["{$prefix}options", "option_id", ["option_value"]],
        ["{$prefix}comments", "comment_ID", ["comment_content", "comment_author"]],
        ["{$prefix}commentmeta", "meta_id", ["meta_value"]],
        ["{$prefix}terms", "term_id", ["name"]],
        ["{$prefix}termmeta", "meta_id", ["meta_value"]],
        ["{$prefix}term_taxonomy", "term_taxonomy_id", ["description"]],
        ["{$prefix}users", "ID", ["display_name"]],
        ["{$prefix}usermeta", "umeta_id", ["meta_value"]],
    ];

    $changed = 0;
    foreach ($cols as [$tbl, $pk, $fields]) {
        try { $pdo->query("SELECT 1 FROM `{$tbl}` LIMIT 1"); } catch (Exception $e) { continue; }
        foreach ($fields as $f) {
            $rows = $pdo->query("SELECT `{$pk}` k, `{$f}` v FROM `{$tbl}` WHERE `{$f}` IS NOT NULL");
            $upd = $pdo->prepare("UPDATE `{$tbl}` SET `{$f}` = :v WHERE `{$pk}` = :k");
            foreach ($rows as $row) {
                $nv = fixValue($row['v']);
                if ($nv !== $row['v']) {
                    $changed++;
                    $upd->execute([':v' => $nv, ':k' => $row['k']]);
                }
            }
        }
    }
    echo "Repaired {$changed} text fields";
    """#
}
