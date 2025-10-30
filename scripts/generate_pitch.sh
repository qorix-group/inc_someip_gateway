#!/usr/bin/env bash

set -e

marp doc/pitch.md -o pitch.pptx --allow-local-files
# --pptx-editable