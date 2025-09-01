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
# Compatible with both GitLab CI and GitHub Actions

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

# Detect CI environment
if [[ -n "${GITLAB_CI}" ]]; then
    echo "GitLab CI detected - using gtcs scanner"
    CI_PLATFORM="gitlab"
elif [[ -n "${GITHUB_ACTIONS}" ]]; then
    echo "GitHub Actions detected - using Trivy scanner"
    CI_PLATFORM="github"
else
    echo "Unknown CI platform - defaulting to Trivy scanner"
    CI_PLATFORM="github"
fi

# Function to scan with GitLab's gtcs
scan_with_gtcs() {
    local image="$1"
    local driver_version="$2"

    export CS_IMAGE="${image}"

    # Try to scan the kernel-specific tag first
    if ! gtcs scan; then
        echo "Kernel-specific tag scan failed, trying non-kernel-specific tag..."
        DOCKER_TAG="${TAG_PREFIX}${driver_version}-fedora${FEDORA_VERSION}"
        CS_IMAGE="${IMAGE_BASE_NAME}:${DOCKER_TAG}"
        export CS_IMAGE
        gtcs scan
    fi

    # Check vulnerabilities and create summary
    cat gl-container-scanning-report.json | jq '.vulnerabilities[].severity' | sort | uniq -c
    if [[ $(cat gl-container-scanning-report.json | jq '.vulnerabilities | any') == 'true' ]]; then
        echo "Vulnerabilities found in ${CS_IMAGE}"
        mv gl-container-scanning-report.json "driver-artifacts/gl-container-scanning-report-${driver_version}.json"
        return 1
    else
        echo "No vulnerabilities found in ${CS_IMAGE}"
        mv gl-container-scanning-report.json "driver-artifacts/gl-container-scanning-report-${driver_version}.json"
        return 0
    fi
}

# Function to scan with Trivy
scan_with_trivy() {
    local image="$1"
    local driver_version="$2"

    # Install trivy if not available
    if ! command -v trivy &> /dev/null; then
        echo "Installing trivy..."
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
    fi

    # Try to scan the kernel-specific tag first, fall back to non-kernel-specific
    if ! trivy image --format json --output "driver-artifacts/trivy-report-${driver_version}.json" "${image}"; then
        echo "Kernel-specific tag scan failed, trying non-kernel-specific tag..."
        DOCKER_TAG="${TAG_PREFIX}${driver_version}-fedora${FEDORA_VERSION}"
        CS_IMAGE="${IMAGE_BASE_NAME}:${DOCKER_TAG}"
        trivy image --format json --output "driver-artifacts/trivy-report-${driver_version}.json" "${CS_IMAGE}"
    fi

    # Check for vulnerabilities
    VULNERABILITIES=$(jq '.Results[]?.Vulnerabilities // [] | length' "driver-artifacts/trivy-report-${driver_version}.json" | paste -sd+ - | bc 2>/dev/null || echo "0")

    if [[ "${VULNERABILITIES:-0}" -gt 0 ]]; then
        echo "Found ${VULNERABILITIES} vulnerabilities in ${CS_IMAGE}"
        jq '.Results[]?.Vulnerabilities[]?.Severity' "driver-artifacts/trivy-report-${driver_version}.json" | sort | uniq -c
        return 1
    else
        echo "No vulnerabilities found in ${CS_IMAGE}"
        return 0
    fi
}

# Run appropriate scanner based on CI platform
case "${CI_PLATFORM}" in
    "gitlab")
        scan_with_gtcs "${CS_IMAGE}" "${DRIVER_VERSION}"
        ;;
    "github")
        scan_with_trivy "${CS_IMAGE}" "${DRIVER_VERSION}"
        ;;
    *)
        echo "Error: Unknown CI platform"
        exit 1
        ;;
esac
