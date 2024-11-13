<?php
header('Content-Type: text/plain');
echo shell_exec("/usr/local/emhttp/plugins/docker.template.rebuild/scripts/rebuild_script.sh 2>&1");
?>
