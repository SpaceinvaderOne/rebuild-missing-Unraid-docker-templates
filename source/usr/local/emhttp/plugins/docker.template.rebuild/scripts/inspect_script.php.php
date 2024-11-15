<?php
header('Content-Type: text/plain');
echo shell_exec("/usr/local/emhttp/plugins/docker.template.rebuild/scripts/inspect_script.sh 2>&1");
?>
