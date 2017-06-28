#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR=$SCRIPT_DIR
SOURCE_DIR=${PROJECT_DIR}/source/nanomsg
echo generating documents for "${PROJECT_DIR}"
mkdir -p docs
[ -e tmp ] && rm -r tmp
mkdir tmp
cd tmp
git clone https://github.com/adamdruppe/adrdox
cp "${PROJECT_DIR}"/.skeleton.html adrdox/skeleton.html
mkdir -p "${PROJECT_DIR}"/docs/examples
cd adrdox
make
./doc2 -i "${SOURCE_DIR}"
mv generated-docs/* "${PROJECT_DIR}"/docs
./doc2 -i "${PROJECT_DIR}"/examples
mv generated-docs/* "${PROJECT_DIR}"/docs/examples
cp "${PROJECT_DIR}"/docs/nanomsg.html "${PROJECT_DIR}"/docs/index.html
cd "${PROJECT_DIR}"
rm -r tmp
echo succeeded - docs generated
