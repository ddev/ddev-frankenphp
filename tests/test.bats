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
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --web-environment-add=BLACKFIRE_SERVER_ID=test_server_id,BLACKFIRE_SERVER_TOKEN=test_token
  assert_success
  run ddev start -y
  assert_success

  cp "${DIR}"/tests/testdata/.ddev/php/php.ini .ddev/php/php.ini
  assert_file_exist .ddev/php/php.ini

  export FRANKENPHP_PHP_VERSION=8.4
  export FRANKENPHP_WORKER=false
  export FRANKENPHP_CUSTOM_EXTENSION=false
  export FRANKENPHP_HOST_PORTS=false
}

health_checks() {
  run ddev php -v
  assert_success
  assert_output --partial "PHP ${FRANKENPHP_PHP_VERSION}"

  run ddev php --ini
  assert_success
  assert_output --partial "/etc/php-zts/php.ini"
  assert_output --partial "/etc/php-zts/conf.d/20-assert.ini"

  run ddev php -i
  assert_success
  assert_output --partial "date.timezone => Europe/London"

  run ddev php -r 'assert(false);'
  assert_failure

  run curl -sfI http://${PROJNAME}.ddev.site
  assert_success
  assert_output --partial "HTTP/1.1 200"
  assert_output --regexp "Server: (Caddy|FrankenPHP)"

  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    assert_output --partial "X-Request-Count"
    assert_output --partial "X-Worker-Uptime"
  else
    refute_output --partial "X-Request-Count"
    refute_output --partial "X-Worker-Uptime"
  fi

  run curl -sfI https://${PROJNAME}.ddev.site
  assert_success
  assert_output --partial "HTTP/2 200"
  assert_output --regexp "server: (Caddy|FrankenPHP)"

  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    assert_output --partial "x-request-count"
    assert_output --partial "x-worker-uptime"
  else
    refute_output --partial "x-request-count"
    refute_output --partial "x-worker-uptime"
  fi

  if [[ "${FRANKENPHP_HOST_PORTS}" == "true" ]]; then
    run curl -sfI http://127.0.0.1:8080
    assert_success
    assert_output --partial "HTTP/1.1 200"
    assert_output --regexp "Server: (Caddy|FrankenPHP)"

    if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
      assert_output --partial "X-Request-Count"
      assert_output --partial "X-Worker-Uptime"
    else
      refute_output --partial "X-Request-Count"
      refute_output --partial "X-Worker-Uptime"
    fi

    run curl -sfI https://127.0.0.1:8443
    assert_success
    assert_output --partial "HTTP/2 200"
    assert_output --regexp "server: (Caddy|FrankenPHP)"
    if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
      assert_output --partial "x-request-count"
      assert_output --partial "x-worker-uptime"
    else
      refute_output --partial "x-request-count"
      refute_output --partial "x-worker-uptime"
    fi
  fi

  run curl -sf http://${PROJNAME}.ddev.site
  assert_success
  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    assert_output --partial "FrankenPHP Worker Demo"
  else
    assert_output "FrankenPHP page without worker"
  fi

  run curl -sf https://${PROJNAME}.ddev.site
  assert_success
  if [[ "${FRANKENPHP_WORKER}" == "true" ]]; then
    assert_output --partial "FrankenPHP Worker Demo"
  else
    assert_output "FrankenPHP page without worker"
  fi

  run ddev php -m
  assert_success
  assert_output --partial "pdo_mysql"
  assert_output --partial "pdo_pgsql"
  assert_output --partial "zip"

  if [[ "${FRANKENPHP_CUSTOM_EXTENSION}" == "true" ]]; then
    assert_output --partial "example_pie_extension"
  else
    refute_output --partial "example_pie_extension"
  fi

  run ddev xdebug on
  assert_success

  run ddev php -m
  assert_success
  assert_output --partial "xdebug"

  run ddev xhprof on
  assert_success

  run ddev php -m
  assert_success
  assert_output --partial "xhprof"

  run ddev blackfire on
  assert_success

  run ddev php -m
  assert_success
  assert_output --partial "blackfire"
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

# bats test_tags=php82
@test "php82" {
  set -eu -o pipefail

  export FRANKENPHP_PHP_VERSION=8.2

  cp "${DIR}"/tests/testdata/index-no-worker.php index.php
  assert_file_exist index.php

  run ddev config --php-version=${FRANKENPHP_PHP_VERSION}
  assert_success

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=php83
@test "php83" {
  set -eu -o pipefail

  export FRANKENPHP_PHP_VERSION=8.3

  cp "${DIR}"/tests/testdata/index-no-worker.php index.php
  assert_file_exist index.php

  run ddev config --php-version=${FRANKENPHP_PHP_VERSION}
  assert_success

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=php84
@test "php84" {
  set -eu -o pipefail

  export FRANKENPHP_PHP_VERSION=8.4

  cp "${DIR}"/tests/testdata/index-no-worker.php index.php
  assert_file_exist index.php

  run ddev config --php-version=${FRANKENPHP_PHP_VERSION}
  assert_success

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=php85
@test "php85" {
  set -eu -o pipefail

  export FRANKENPHP_PHP_VERSION=8.5

  cp "${DIR}"/tests/testdata/index-no-worker.php index.php
  assert_file_exist index.php

  run ddev config --php-version=${FRANKENPHP_PHP_VERSION}
  assert_success

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=php84-worker
@test "php84-worker" {
  set -eu -o pipefail

  export FRANKENPHP_PHP_VERSION=8.4
  export FRANKENPHP_WORKER=true

  cp "${DIR}"/tests/testdata/index-worker.php index.php
  assert_file_exist index.php

  cp "${DIR}"/tests/testdata/.ddev/docker-compose.frankenphp_extra.yaml .ddev/docker-compose.frankenphp_extra.yaml
  assert_file_exist .ddev/docker-compose.frankenphp_extra.yaml

  run ddev config --php-version=${FRANKENPHP_PHP_VERSION}
  assert_success

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=php84-docroot-extension-port
@test "docroot=php84-docroot-extension-port" {
  set -eu -o pipefail

  export FRANKENPHP_PHP_VERSION=8.4
  export FRANKENPHP_CUSTOM_EXTENSION=true
  export FRANKENPHP_HOST_PORTS=true

  run ddev config --docroot=public
  assert_success

  run ddev config --host-webserver-port=8080 --host-https-port=8443
  assert_success

  cp "${DIR}"/tests/testdata/.ddev/web-build/Dockerfile.frankenphp_extra .ddev/web-build/Dockerfile.frankenphp_extra
  assert_file_exist .ddev/web-build/Dockerfile.frankenphp_extra

  run ddev config --php-version=${FRANKENPHP_PHP_VERSION}
  assert_success

  cp "${DIR}"/tests/testdata/index-no-worker.php public/index.php
  assert_file_exist public/index.php

  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
