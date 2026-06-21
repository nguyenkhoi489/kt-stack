import Foundation

enum LaravelRouteReflectionScript {
    static let php = #"""
<?php

error_reporting(0);
@ini_set('display_errors', '0');
@ini_set('display_startup_errors', '0');

function ktstack_emit($payload) {
    $json = json_encode($payload);
    if ($json === false) {
        $json = json_encode(['error' => 'Failed to encode routes as JSON.', 'routes' => []]);
    }
    echo "\n__KTSTACK_ROUTES_BEGIN__" . $json . "__KTSTACK_ROUTES_END__\n";
}

function ktstack_normalize_rules($rules) {
    $out = [];
    foreach ($rules as $field => $rule) {
        $parts = [];
        if (is_array($rule)) {
            foreach ($rule as $item) {
                if (is_string($item)) {
                    $parts[] = $item;
                } elseif (is_object($item)) {
                    $parts[] = get_class($item);
                }
            }
        } else {
            $parts = explode('|', (string) $rule);
        }
        $required = false;
        foreach ($parts as $p) {
            if (strcasecmp(trim($p), 'required') === 0) { $required = true; break; }
        }
        $out[] = [
            'name' => (string) $field,
            'rules' => array_values($parts),
            'required' => $required,
        ];
    }
    return $out;
}

function ktstack_resolve_fields($route) {
    $action = $route->getActionName();
    if ($action === 'Closure' || strpos($action, '@') === false) {
        return [[], false];
    }
    list($class, $method) = explode('@', $action, 2);
    if (!class_exists($class) || !method_exists($class, $method)) {
        return [[], false];
    }
    $ref = new ReflectionMethod($class, $method);
    foreach ($ref->getParameters() as $param) {
        $type = $param->getType();
        if (!$type || !method_exists($type, 'getName') || $type->isBuiltin()) {
            continue;
        }
        $typeName = $type->getName();
        if (!class_exists($typeName)) {
            continue;
        }
        if (!is_subclass_of($typeName, 'Illuminate\Foundation\Http\FormRequest')) {
            continue;
        }
        $instance = new $typeName();
        if (!method_exists($instance, 'rules')) {
            continue;
        }
        $rules = $instance->rules();
        if (!is_array($rules)) {
            return [[], true];
        }
        return [ktstack_normalize_rules($rules), true];
    }
    return [[], false];
}

function ktstack_introspect($route) {
    $middleware = [];
    try {
        $middleware = array_values(Illuminate\Support\Arr::flatten($route->gatherMiddleware()));
    } catch (\Throwable $e) {
        $middleware = [];
    }
    $fields = [];
    $rulesResolved = false;
    try {
        list($fields, $rulesResolved) = ktstack_resolve_fields($route);
    } catch (\Throwable $e) {
        $fields = [];
        $rulesResolved = false;
    }
    return [
        'uri' => $route->uri(),
        'name' => $route->getName(),
        'middleware' => $middleware,
        'action' => $route->getActionName(),
        'fields' => $fields,
        'rulesResolved' => $rulesResolved,
    ];
}

$base = getcwd();

if (!file_exists($base . '/vendor/autoload.php')) {
    ktstack_emit(['error' => 'vendor/autoload.php not found — run composer install', 'routes' => []]);
    exit(0);
}
if (!file_exists($base . '/bootstrap/app.php')) {
    ktstack_emit(['error' => 'bootstrap/app.php not found — not a Laravel project root', 'routes' => []]);
    exit(0);
}

$result = ['error' => null, 'routes' => []];

try {
    require $base . '/vendor/autoload.php';
    $app = require $base . '/bootstrap/app.php';
    $kernel = $app->make('Illuminate\Contracts\Console\Kernel');
    $kernel->bootstrap();
    $routes = $app['router']->getRoutes();
    foreach ($routes as $route) {
        $entry = ktstack_introspect($route);
        foreach ($route->methods() as $method) {
            if ($method === 'HEAD') {
                continue;
            }
            $row = $entry;
            $row['method'] = $method;
            $result['routes'][] = $row;
        }
    }
} catch (\Throwable $e) {
    $result['error'] = $e->getMessage();
    $result['routes'] = [];
}

ktstack_emit($result);
exit(0);
"""#
}
