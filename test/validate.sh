#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/validate-runner.sh
bash -n scripts/download.sh
bash -n scripts/run.sh

ruby -e "require 'yaml'; data = YAML.load_file('action.yml'); abort unless data['runs']['using'] == 'composite'"

grep -q 'Ternary-Bonsai-27B-Q2_0.gguf' scripts/download.sh
grep -q 'Ternary-Bonsai-27B-Q2_0.gguf' scripts/run.sh
grep -q '7165121600' scripts/download.sh
grep -q '868c11714cf8fe47f5ec9eeb2be0ab1a337112886f92ee0ede6b855c4fa31757' scripts/download.sh
grep -q 'abbae723028d71be674e71e1a71201a6f43fab22' scripts/download.sh
grep -q 'e361c09f128a407c659d07361b008155e1eab0cd0ed0a12ccdcf7147f7c22948' scripts/download.sh

if grep -R -n -E 'router\.huggingface|together|chat/completions.*https' \
  --exclude-dir=.git \
  --exclude=README.md \
  --exclude=validate.sh \
  .; then
  exit 1
fi
