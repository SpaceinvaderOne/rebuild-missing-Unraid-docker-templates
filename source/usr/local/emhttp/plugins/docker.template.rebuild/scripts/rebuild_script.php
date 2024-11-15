<?php
header('Content-Type: text/plain');

// Get values from POST data
$templateDir = escapeshellarg($_POST['templateDir'] ?? '/tmp/docker-template-restore');
$checkOrphaned = escapeshellarg($_POST['checkOrphaned'] ?? 'yes');

// Pass values to shell script
echo shell_exec("/usr/local/emhttp/plugins/docker.template.rebuild/scripts/rebuild_script.sh $templateDir $checkOrphaned 2>&1");
?>