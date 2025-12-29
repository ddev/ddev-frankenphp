[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/ddev/ddev-frankenphp/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/ddev/ddev-frankenphp/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/ddev/ddev-frankenphp)](https://github.com/ddev/ddev-frankenphp/commits)
[![release](https://img.shields.io/github/v/release/ddev/ddev-frankenphp)](https://github.com/ddev/ddev-frankenphp/releases/latest)

# DDEV FrankenPHP

See the blog [Using FrankenPHP with DDEV](https://ddev.com/blog/using-frankenphp-with-ddev/).

## Overview

[FrankenPHP](https://frankenphp.dev/) is a modern application server for PHP built on top of the [Caddy](https://caddyserver.com/) web server.

This add-on integrates FrankenPHP into your [DDEV](https://ddev.com/) project.

## Installation

```bash
ddev add-on get ddev/ddev-frankenphp
ddev restart
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command                | Description                                           |
|------------------------|-------------------------------------------------------|
| `ddev describe`        | View project status                                   |
| `ddev logs -f`         | View FrankenPHP logs                                  |
| `ddev utility rebuild` | Get fresh FrankenPHP build inside the `web` container |

## Advanced Customization

Install pre-packaged extensions using the `php-zts-` prefix (see supported extensions [here](https://pkg.henderkes.com/)):

```bash
# install sqlsrv and xsl extensions
ddev config --webimage-extra-packages="php-zts-sqlsrv,php-zts-xsl"
ddev restart
```

For extensions not available as pre-packaged use [PHP/PIE](https://github.com/php/pie), create a file [`.ddev/web-build/Dockerfile.frankenphp_extra`](./tests/testdata/.ddev/web-build/Dockerfile.frankenphp_extra) with the following content:

```bash
RUN (apt-get update || true) && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" autoconf bison gcc libtool make pie-zts pkg-config re2c && \
    pie-zts install asgrim/example-pie-extension
```

And run `ddev restart`.

Make sure to commit the `.ddev/web-build/Dockerfile.frankenphp_extra` file to version control.

---

To modify the default [Caddyfile](./web-build/Caddyfile.frankenphp) configuration, either remove `#ddev-generated` line and edit it directly, or create a file [`.ddev/docker-compose.frankenphp_extra.yaml`](./tests/testdata/.ddev/docker-compose.frankenphp_extra.yaml) with the following content:

```yaml
# See all configurable variables in
# https://github.com/php/frankenphp/blob/main/caddy/frankenphp/Caddyfile
services:
  web:
    environment:
      # enable worker script
      # change some php.ini settings
      FRANKENPHP_CONFIG: |
        worker ${DDEV_DOCROOT:-.}/index.php
        php_ini {
          memory_limit 256M
          max_execution_time 15
        }
      # add a stub for Mercure module
      CADDY_SERVER_EXTRA_DIRECTIVES: |
        # mercure {
        #   ...
        # }
```

And run `ddev restart`.

Make sure to commit the `.ddev/docker-compose.frankenphp_extra.yaml` file to version control.

## Resources:

- [FrankenPHP Documentation](https://frankenphp.dev/docs/)
- [FrankenPHP Static PHP Package Repository](https://debs.henderkes.com/)
- [Using FrankenPHP with DDEV](https://ddev.com/blog/using-frankenphp-with-ddev/)
- [DDEV FrankenPHP Benchmark](https://github.com/stasadev/ddev-frankenphp-benchmark)

## Credits

**Contributed by [@stasadev](https://github.com/stasadev)**

**Maintained by the [DDEV team](https://ddev.com/support-ddev/)**
