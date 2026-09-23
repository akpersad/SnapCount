#!/usr/bin/env bash
# Fetch the AdaFace IR-18 Core ML model.
#
# The model is gitignored (see .gitignore: *.mlpackage), so a fresh clone needs this script.
# Keeping a 45 MB binary out of git is worth one script.
#
# Downloads a public model file. Nothing is uploaded. Safe to run offline-prep before the trip;
# the app itself never touches the network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/../Models"
URL="https://github.com/john-rocky/CoreML-Models/releases/download/adaface-v1/AdaFace_IR18.mlpackage.zip"
ARCHIVE="${MODELS_DIR}/AdaFace_IR18.mlpackage.zip"
MODEL="${MODELS_DIR}/AdaFace_IR18.mlpackage"

# Pin this once the first successful download is verified, then enforce it below.
EXPECTED_SHA256="c639ffc02233c72c10daf90f484e14bf570b7f70f55f0c0ee1ce3d284a04430b"

mkdir -p "${MODELS_DIR}"

if [ -d "${MODEL}" ]; then
    echo "Model already present: ${MODEL}"
    exit 0
fi

echo "Downloading AdaFace IR-18 (~45 MB)..."
curl -fL --progress-bar "${URL}" -o "${ARCHIVE}"

ACTUAL_SHA256="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
echo "sha256: ${ACTUAL_SHA256}"

if [ -n "${EXPECTED_SHA256}" ]; then
    if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
        echo "ERROR: checksum mismatch. Expected ${EXPECTED_SHA256}" >&2
        rm -f "${ARCHIVE}"
        exit 1
    fi
    echo "Checksum verified."
else
    echo "NOTE: EXPECTED_SHA256 is unset. Paste the value above into this script to pin it."
fi

echo "Unpacking..."
unzip -q "${ARCHIVE}" -d "${MODELS_DIR}"
rm -f "${ARCHIVE}"

echo "Done: ${MODEL}"
echo
echo "Model contract (verified, encoded in AdaFaceIR18): face_image (112x112 BGR) -> embedding"
echo "(Float16 [1, 512]). Normalization is inside the graph; do not pre-normalize."
