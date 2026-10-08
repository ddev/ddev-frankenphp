<?php

// Minimal FrankenPHP worker, its state persists between requests
$startTime = time();
$requestCount = 0;

$handler = static function () use (&$requestCount, $startTime) {
    $requestCount++;
    header('X-Request-Count: ' . $requestCount);
    header('X-Worker-Uptime: ' . (time() - $startTime) . 's');
    echo 'FrankenPHP page with worker';
};

while (frankenphp_handle_request($handler)) {
    gc_collect_cycles();
}
