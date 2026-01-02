[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/ddev/ddev-frankenphp/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/ddev/ddev-frankenphp/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/ddev/ddev-frankenphp)](https://github.com/ddev/ddev-frankenphp/commits)
[![release](https://img.shields.io/github/v/release/ddev/ddev-frankenphp)](https://github.com/ddev/ddev-frankenphp/releases/latest)

# DDEV FrankenPHP

See the blog [Using FrankenPHP with DDEV](https://ddev.com/blog/using-frankenphp-with-ddev/).

## Overview

[FrankenPHP](https://frankenphp.dev/) is a modern application server for PHP built on top of the [Caddy](https://caddyserver.com/) web server.

This add-on integrates FrankenPHP into your [DDEV](https://ddev.com/) project.

> [!NOTE]
> FrankenPHP support is available for PHP 8.2+ ZTS (Zend Thread Safety) versions only.

## Installation

```bash
ddev add-on get ddev/ddev-frankenphp
ddev restart
```

(Optional) To rebuild FrankenPHP without cache, use:

```bash
ddev utility rebuild
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command                   | Description                        |
|---------------------------|------------------------------------|
| `ddev describe`           | View project status                |
| `ddev php -v`             | Check installed PHP ZTS version    |
| `ddev exec frankenphp -v` | Check installed FrankenPHP version |
| `ddev php -m`             | View installed PHP extensions      |
| `ddev logs -f`            | View FrankenPHP logs               |

## Advanced Customization

Install pre-packaged extensions using the `php-zts-` prefix (see [supported extensions](https://pkg.henderkes.com/84/php-zts/packages?type=debian)):

```bash
# install mongodb and sqlsrv extensions
ddev config --webimage-extra-packages="php-zts-mongodb,php-zts-sqlsrv"
ddev restart
```

For extensions not available as pre-packaged, use [PHP/PIE](https://packagist.org/extensions), create a file [`.ddev/web-build/Dockerfile.frankenphp_extra`](./tests/testdata/.ddev/web-build/Dockerfile.frankenphp_extra) with the following content:

```dockerfile
# .ddev/web-build/Dockerfile.frankenphp_extra
# Replace asgrim/example-pie-extension with the desired extension https://packagist.org/extensions
RUN (apt-get update || true) && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confold" \
        autoconf bison gcc libtool make pie-zts pkg-config re2c && \
    rm -rf /var/lib/apt/lists/* && \
    pie-zts install asgrim/example-pie-extension

```

And run `ddev restart`.

Make sure to commit the `.ddev/web-build/Dockerfile.frankenphp_extra` file to version control.

---

To change the default `Caddyfile` configuration, remove the `#ddev-generated` line from [`.ddev/web-build/Caddyfile.frankenphp`](./web-build/Caddyfile.frankenphp) and edit it.

Alternatively, create a file [`.ddev/docker-compose.frankenphp_extra.yaml`](./tests/testdata/.ddev/docker-compose.frankenphp_extra.yaml) with the following content:

```yaml
# .ddev/docker-compose.frankenphp_extra.yaml
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
