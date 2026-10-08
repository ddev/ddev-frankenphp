<?php

// Prints the request and PHP settings as FrankenPHP sees them, one "key=value" per line
header('Content-Type: text/plain');
echo 'sapi=' . PHP_SAPI . "\n";
echo 'https=' . ($_SERVER['HTTPS'] ?? '') . "\n";
echo 'server_port=' . $_SERVER['SERVER_PORT'] . "\n";
echo 'request_scheme=' . $_SERVER['REQUEST_SCHEME'] . "\n";
echo 'timezone=' . date_default_timezone_get() . "\n";
echo 'highlight.comment=' . ini_get('highlight.comment') . "\n";
echo 'memory_limit=' . ini_get('memory_limit') . "\n";
foreach (get_loaded_extensions() as $extension) {
    echo 'extension=' . $extension . "\n";
}
