#!/bin/sh
set -eu

mkdir -p /tmp/run
chmod 0755 /tmp/run

exec /init
