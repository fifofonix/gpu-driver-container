#!/bin/bash
# Copyright (c) 2025, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Scan Docker image for vulnerabilities
# Usage: scan_image.sh <driver_version> <tag_prefix> <fedora_version> <fedora_uname> <image_base_name>

set -e

DRIVER_VERSION="$1"
TAG_PREFIX="$2"
FEDORA_VERSION="$3"
FEDORA_UNAME="$4"
IMAGE_BASE_NAME="$5"

mkdir -p driver-artifacts

DOCKER_TAG="${TAG_PREFIX}${DRIVER_VERSION}-${FEDORA_UNAME}-fedora${FEDORA_VERSION}"
CS_IMAGE="${IMAGE_BASE_NAME}:${DOCKER_TAG}"

echo "Scanning image: ${CS_IMAGE}"

# Install trivy if not available
if ! command -v trivy &> /dev/null; then
    echo "Installing trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
fi

# Try to scan the kernel-specific tag first, fall back to non-kernel-specific
if ! trivy image --format json --output "driver-artifacts/trivy-report-${DRIVER_VERSION}.json" "${CS_IMAGE}"; then
    echo "Kernel-specific tag scan failed, trying non-kernel-specific tag..."
    DOCKER_TAG="${TAG_PREFIX}${DRIVER_VERSION}-fedora${FEDORA_VERSION}"
    CS_IMAGE="${IMAGE_BASE_NAME}:${DOCKER_TAG}"
    trivy image --format json --output "driver-artifacts/trivy-report-${DRIVER_VERSION}.json" "${CS_IMAGE}"
fi

# Check for vulnerabilities
VULNERABILITIES=$(jq '.Results[]?.Vulnerabilities // [] | length' "driver-artifacts/trivy-report-${DRIVER_VERSION}.json" | paste -sd+ - | bc)

if [[ "${VULNERABILITIES:-0}" -gt 0 ]]; then
    echo "Found ${VULNERABILITIES} vulnerabilities in ${CS_IMAGE}"
    jq '.Results[]?.Vulnerabilities[]?.Severity' "driver-artifacts/trivy-report-${DRIVER_VERSION}.json" | sort | uniq -c
    exit 1
else
    echo "No vulnerabilities found in ${CS_IMAGE}"
fi
