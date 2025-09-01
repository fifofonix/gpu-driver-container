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

# Release Docker image to external registry
# Usage: release_image.sh <driver_version> <overwrite_remote_tag> <tag_prefix> <fedora_version> <fedora_uname> <image_base_name> <release_registry_project>

set -e

DRIVER_VERSION="$1"
OVERWRITE_REMOTE_TAG="$2"
TAG_PREFIX="$3"
FEDORA_VERSION="$4"
FEDORA_UNAME="$5"
IMAGE_BASE_NAME="$6"
RELEASE_REGISTRY_PROJECT="$7"

DOCKER_TAG="${TAG_PREFIX}${DRIVER_VERSION}-${FEDORA_UNAME}-fedora${FEDORA_VERSION}"
SOURCE_IMAGE="${IMAGE_BASE_NAME}:${DOCKER_TAG}"
TARGET_IMAGE="${RELEASE_REGISTRY_PROJECT}:${DOCKER_TAG}"

# Try kernel-specific tag first, fall back to non-kernel-specific
if ! docker manifest inspect "${SOURCE_IMAGE}" > /dev/null 2>&1; then
    DOCKER_TAG="${TAG_PREFIX}${DRIVER_VERSION}-fedora${FEDORA_VERSION}"
    SOURCE_IMAGE="${IMAGE_BASE_NAME}:${DOCKER_TAG}"
    TARGET_IMAGE="${RELEASE_REGISTRY_PROJECT}:${DOCKER_TAG}"
fi

echo "Pulling source image: ${SOURCE_IMAGE}"
docker pull -q "${SOURCE_IMAGE}"

echo "Tagging as: ${TARGET_IMAGE}"
docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"

if ! docker manifest inspect "${TARGET_IMAGE}" > /dev/null 2>&1 || [[ "${OVERWRITE_REMOTE_TAG}" == "1" ]]; then
    echo "Pushing ${TARGET_IMAGE} to remote repository."
    docker push -q "${TARGET_IMAGE}"
else
    echo "Skipping push of ${TARGET_IMAGE} to remote repository (already exists)."
fi
