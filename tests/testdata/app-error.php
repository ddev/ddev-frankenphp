<?php

http_response_code((int) ($_GET['status'] ?? 404));
echo "App error page";
