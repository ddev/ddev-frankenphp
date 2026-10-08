#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  # Override this variable for your add-on:
  export GITHUB_REPO=ddev/ddev-frankenphp

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p ~/tmp
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --timezone=Europe/London --web-environment-add=BLACKFIRE_SERVER_ID=test_server_id,BLACKFIRE_SERVER_TOKEN=test_token
  assert_success
  run ddev start -y
  assert_success

  cp "${DIR}"/tests/testdata/.ddev/php/php.ini .ddev/php/php.ini
  assert_file_exist .ddev/php/php.ini

  cp "${DIR}"/tests/testdata/{app-error,index,server-info,session}.php .
  assert_file_exist app-error.php
  assert_file_exist index.php
  assert_file_exist server-info.php
  assert_file_exist session.php

  export FRANKENPHP_WORKER=false
  export FRANKENPHP_CUSTOM_EXTENSION=false
  export FRANKENPHP_HOST_PORTS=false
}

# Fails on PHP startup warnings, e.g. from a duplicate or missing extension
refute_php_warnings() {
  refute_output --partial "Warning"
  refute_output --partial "is already loaded"
  refute_output --partial "cannot open shared object file"
  refute_output --partial "in Unknown on line"
}

# Checks the status line and FrankenPHP headers of the URL.
# Output is lowercased, so the same checks work for HTTP/1.1 and HTTP/2.
assert_frankenphp_headers() {
  local url="$1"
  # e.g. "http/2 200"
  local status_line="$2"

  run bash -o pipefail -c "curl -sfI '${url}' | tr '[:upper:]' '[:lower:]'"
  assert_success
  assert_output --partial "${status_line}"
  assert_output --regexp "server: (caddy|frankenphp)"

  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    assert_output --partial "x-request-count"
    assert_output --partial "x-worker-uptime"
  else
    refute_output --partial "x-request-count"
    refute_output --partial "x-worker-uptime"
  fi
}

# Checks the request and PHP settings as FrankenPHP sees them
assert_server_info() {
  local url="$1"
  local request_scheme="$2"
  local server_port="$3"

  run curl -sf "${url}/server-info.php"
  assert_success
  assert_line "sapi=frankenphp"
  assert_line "request_scheme=${request_scheme}"
  assert_line "server_port=${server_port}"
  if [[ "${request_scheme}" == "https" ]]; then
    assert_line "https=on"
  else
    assert_line "https="
  fi
  assert_line "timezone=Europe/London"
  assert_line "highlight.comment=#123456"

  # Set with php_ini in FRANKENPHP_CONFIG from docker-compose.frankenphp_extra.yaml
  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    assert_line "memory_limit=256M"
  fi
}

health_checks() {
  # Expected PHP version, e.g. "8.4"
  local php_version="$1"

  run ddev php -v
  assert_success
  assert_output --partial "PHP ${php_version}"
  assert_output --partial "ZTS"
  refute_php_warnings

  run ddev exec "readlink /usr/bin/php${php_version}"
  assert_success
  assert_output "/usr/bin/php"

  run ddev php --ini
  assert_success
  assert_output --partial "/etc/php-zts/php.ini"
  assert_output --partial "/etc/php-zts/conf.d/20-assert.ini"

  run ddev php -r 'echo date_default_timezone_get();'
  assert_success
  assert_output "Europe/London"

  run ddev php -r 'echo ini_get("highlight.comment");'
  assert_success
  assert_output "#123456"

  run ddev php -r 'assert(false);'
  assert_failure

  run ddev php /var/www/html/session.php
  assert_success
  assert_output --partial "SESSION_OK"
  assert_output --partial "/var/lib/php-zts/session"
  refute_output --partial "Permission denied"

  # FrankenPHP must start without Caddyfile warnings
  run ddev logs -s web
  assert_success
  refute_output --partial "is not formatted"

  assert_frankenphp_headers "http://${PROJNAME}.ddev.site" "http/1.1 200"
  assert_frankenphp_headers "https://${PROJNAME}.ddev.site" "http/2 200"

  assert_server_info "http://${PROJNAME}.ddev.site" http 80
  assert_server_info "https://${PROJNAME}.ddev.site" https 443

  if [[ "${FRANKENPHP_HOST_PORTS}" == "true" ]]; then
    assert_frankenphp_headers "http://127.0.0.1:8080" "http/1.1 200"
    assert_frankenphp_headers "https://127.0.0.1:8443" "http/2 200"

    # Without the router, the port comes from the Host header
    assert_server_info "http://127.0.0.1:8080" http 8080
    assert_server_info "https://127.0.0.1:8443" https 8443
  fi

  local index_output="FrankenPHP page without worker"
  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    index_output="FrankenPHP page with worker"
  fi

  run curl -sf http://${PROJNAME}.ddev.site
  assert_success
  assert_output "${index_output}"

  run curl -sf https://${PROJNAME}.ddev.site
  assert_success
  assert_output "${index_output}"

  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    # The worker keeps its state, so the request count grows
    local first_count second_count
    first_count=$(curl -sfI https://${PROJNAME}.ddev.site | sed -n 's/^x-request-count: \([0-9]*\).*/\1/p')
    second_count=$(curl -sfI https://${PROJNAME}.ddev.site | sed -n 's/^x-request-count: \([0-9]*\).*/\1/p')
    assert [ "${second_count}" -gt "${first_count}" ]
  fi

  # 403 and 404 returned by PHP pass through without the DDEV error pages
  run curl -s -D - "http://${PROJNAME}.ddev.site/app-error.php?status=404"
  assert_success
  assert_output --partial "HTTP/1.1 404"
  assert_output --partial "App error page"
  refute_output --partial "X-Ddev-404-Source"

  run curl -s -D - "https://${PROJNAME}.ddev.site/app-error.php?status=403"
  assert_success
  assert_output --partial "HTTP/2 403"
  assert_output --partial "App error page"
  refute_output --partial "x-ddev-403-source"

  # Without index.php, Caddy returns its own 403 and 404, which show the DDEV error pages
  run ddev exec 'cd "/var/www/html/${DDEV_DOCROOT}" && mv index.php index.php.bak && echo forbidden > forbidden.txt && chmod 000 forbidden.txt'
  assert_success

  run curl -s -D - http://${PROJNAME}.ddev.site/missing.html
  assert_success
  assert_output --partial "HTTP/1.1 404"
  assert_output --partial "X-Ddev-404-Source: ddev-webserver (frankenphp)"
  assert_output --partial "<title>404: Not Found</title>"

  run curl -s -D - https://${PROJNAME}.ddev.site/forbidden.txt
  assert_success
  assert_output --partial "HTTP/2 403"
  assert_output --partial "x-ddev-403-source: ddev-webserver (frankenphp)"
  assert_output --partial "<title>403: Forbidden</title>"

  run ddev exec 'cd "/var/www/html/${DDEV_DOCROOT}" && mv index.php.bak index.php && rm -f forbidden.txt'
  assert_success

  local extensions=(
    apcu
    bcmath
    bz2
    FFI
    fileinfo
    ftp
    gd
    gettext
    imagick
    intl
    ldap
    memcached
    mysqli
    pdo_mysql
    pdo_pgsql
    pgsql
    redis
    shmop
    soap
    sqlite3
    sysvmsg
    sysvsem
    sysvshm
    xsl
    yaml
    zip
  )
  if [[ "${FRANKENPHP_CUSTOM_EXTENSION}" == "true" ]]; then
    extensions+=(example_pie_extension)
  fi

  run ddev php -m
  assert_success
  refute_php_warnings
  for extension in "${extensions[@]}"; do
    assert_line "${extension}"
  done
  if [[ "${FRANKENPHP_CUSTOM_EXTENSION}" != "true" ]]; then
    refute_line "example_pie_extension"
  fi

  run curl -sf https://${PROJNAME}.ddev.site/server-info.php
  assert_success
  for extension in "${extensions[@]}"; do
    assert_line "extension=${extension}"
  done

  # The extensions must be enabled both in the CLI and in FrankenPHP
  for extension in xdebug xhprof blackfire; do
    run ddev "${extension}" on
    assert_success

    run ddev php -m
    assert_success
    assert_line "${extension}"
    refute_php_warnings

    run curl -sf https://${PROJNAME}.ddev.site/server-info.php
    assert_success
    assert_line "extension=${extension}"
  done
}

# Installs the add-on from the directory for the given PHP version and runs health checks.
install_from_directory() {
  local php_version="$1"

  run ddev config --php-version="${php_version}"
  assert_success

  echo "# ddev add-on get ${DIR} with PHP ${php_version} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks "${php_version}"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

# bats test_tags=php82-php83
@test "install from directory PHP 8.2" {
  set -eu -o pipefail
  install_from_directory 8.2
}

# bats test_tags=php82-php83
@test "install from directory PHP 8.3" {
  set -eu -o pipefail
  install_from_directory 8.3
}

# bats test_tags=php82-php83
@test "install fails with unsupported PHP version or outdated config" {
  set -eu -o pipefail

  run ddev config --php-version=8.1
  assert_success
  run ddev add-on get "${DIR}"
  assert_failure
  assert_output --partial "FrankenPHP is not supported for PHP version 8.1"

  run ddev config --php-version=8.4
  assert_success
  echo "FRANKENPHP_DEBIAN_CODENAME=bookworm" > .ddev/.env.web
  run ddev add-on get "${DIR}"
  assert_failure
  assert_output --partial "You have FRANKENPHP_DEBIAN_CODENAME set"
}

# bats test_tags=php84
@test "install from directory PHP 8.4" {
  set -eu -o pipefail
  install_from_directory 8.4
}

# bats test_tags=php84
@test "install from directory PHP 8.4 with worker" {
  set -eu -o pipefail

  export FRANKENPHP_WORKER=true

  cp "${DIR}"/tests/testdata/worker.php index.php
  assert_file_exist index.php

  cp "${DIR}"/tests/testdata/.ddev/docker-compose.frankenphp_extra.yaml .ddev/docker-compose.frankenphp_extra.yaml
  assert_file_exist .ddev/docker-compose.frankenphp_extra.yaml

  install_from_directory 8.4
}

# bats test_tags=php85
@test "install from directory PHP 8.5" {
  set -eu -o pipefail
  install_from_directory 8.5
}

# bats test_tags=php85
@test "install from directory PHP 8.5 with docroot, custom extension and host ports" {
  set -eu -o pipefail

  export FRANKENPHP_CUSTOM_EXTENSION=true
  export FRANKENPHP_HOST_PORTS=true

  run ddev config --docroot=public --host-webserver-port=8080 --host-https-port=8443
  assert_success

  cp "${DIR}"/tests/testdata/.ddev/web-build/Dockerfile.frankenphp_extra .ddev/web-build/Dockerfile.frankenphp_extra
  assert_file_exist .ddev/web-build/Dockerfile.frankenphp_extra

  mkdir -p public
  mv app-error.php index.php server-info.php public/
  assert_file_exist public/app-error.php
  assert_file_exist public/index.php
  assert_file_exist public/server-info.php

  install_from_directory 8.5
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail

  run ddev config --php-version=8.4
  assert_success

  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks 8.4
}
