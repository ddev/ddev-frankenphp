<?php

$id = 'frankenphpsessiontest';
session_id($id);
if (!session_start()) {
    fwrite(STDERR, "session_start() failed\n");
    exit(1);
}
$_SESSION['probe'] = 'frankenphp-session-ok';
session_write_close();
$path = session_save_path();
$file = $path . '/sess_' . $id;
if (!is_file($file)) {
    fwrite(STDERR, "session file not created at $file\n");
    exit(1);
}
if (strpos((string)file_get_contents($file), 'frankenphp-session-ok') === false) {
    fwrite(STDERR, "session payload missing from $file\n");
    exit(1);
}
@unlink($file);
echo "SESSION_OK save_path=$path\n";
