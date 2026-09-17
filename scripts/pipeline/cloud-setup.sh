#!/bin/bash
# Paste this into the cloud environment's "Setup script" (claude.ai/code → environment → Setup script).
# Runs as root on Ubuntu 24.04 before Claude starts; result is cached. Must exit 0.
# Adds document-intake tools; common toolchains, gh, jq, Docker and PostgreSQL are pre-installed.
apt-get update -qq || true
apt-get install -y -qq pandoc poppler-utils >/dev/null 2>&1 || true
pip install --quiet python-docx >/dev/null 2>&1 || pip install --quiet --break-system-packages python-docx >/dev/null 2>&1 || true
exit 0
