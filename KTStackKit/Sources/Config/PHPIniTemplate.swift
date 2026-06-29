import Foundation

public enum PHPIniTemplate {
    public static let `default` = """
    ; KTStack managed php.ini — edit freely. "Reset to default" restores this template.
    ; A .bak of the previous content is kept next to this file on every save.

    memory_limit = 512M
    upload_max_filesize = 256M
    post_max_size = 256M
    max_execution_time = 120
    max_input_time = 120
    max_input_vars = 5000

    ; Dev-friendly: surface errors in the browser. Turn display_errors Off for prod-like testing.
    display_errors = On
    display_startup_errors = On
    error_reporting = E_ALL

    date.timezone = UTC

    ; opcache speeds up repeated requests; left off for the CLI so scripts always see fresh code.
    opcache.enable = 1
    opcache.enable_cli = 0

    ; The signed runtime cannot allocate JIT executable memory under the hardened runtime; disable PCRE JIT.
    pcre.jit = 0

    """
}
