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

# Build and push Docker image for FCOS
# Usage: build_push_image.sh <driver_version> <overwrite_tag> <tag_prefix> <fedora_version> <fedora_uname> <image_base_name> <compile_kernel_modules>
# Compatible with both GitLab CI and GitHub Actions

set -e

# Detect CI environment for logging and registry authentication
if [[ -n "${GITLAB_CI}" ]]; then
    echo "GitLab CI detected"
    CI_PLATFORM="gitlab"
elif [[ -n "${GITHUB_ACTIONS}" ]]; then
    echo "GitHub Actions detected"
    CI_PLATFORM="github"
else
    echo "Unknown CI platform - assuming local/generic environment"
    CI_PLATFORM="generic"
fi

DRIVER_VERSION="$1"
OVERWRITE_TAG="$2"
TAG_PREFIX="$3"
FEDORA_VERSION="$4"
FEDORA_UNAME="$5"
IMAGE_BASE_NAME="$6"
COMPILE_KERNEL_MODULES="$7"

DOCKER_IMAGE_WITH_PRECOMPILED_KERNEL_MODULES="${IMAGE_BASE_NAME}:${TAG_PREFIX}${DRIVER_VERSION}-${FEDORA_UNAME}-fedora${FEDORA_VERSION}"
DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES="${IMAGE_BASE_NAME}:${TAG_PREFIX}${DRIVER_VERSION}-fedora${FEDORA_VERSION}"

echo -e "\033[33mBuilding driver ${DRIVER_VERSION} for Fedora ${FEDORA_VERSION} (${FEDORA_UNAME}).\033[0m"

# Build base image
docker build \
  --build-arg FEDORA_VERSION="${FEDORA_VERSION}" \
  --build-arg DRIVER_VERSION="${DRIVER_VERSION}" \
  --build-arg TARGETARCH="$(uname -m)" \
  --build-arg GOLANG_VERSION="${GOLANG_VERSION}" \
  --build-arg DRIVER_BRANCH="$(echo $DRIVER_VERSION | cut -d. -f1)" \
  --build-arg CUDA_VERSION="${CUDA_VERSION}" \
  --build-arg HTTP_PROXY="${HTTP_PROXY:-}" \
  --build-arg HTTPS_PROXY="${HTTPS_PROXY:-}" \
  -t "${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES}" \
  fedora

if [[ "${COMPILE_KERNEL_MODULES}" == "1" ]]; then
  if ! $(docker manifest inspect "${DOCKER_IMAGE_WITH_PRECOMPILED_KERNEL_MODULES}" > /dev/null 2>&1) || [[ "${OVERWRITE_TAG}" == "1" ]]; then
    if docker run --privileged --pid=host --name "build-kernel-modules-${DRIVER_VERSION}" \
      --env HTTP_PROXY="${HTTP_PROXY:-}" --env HTTPS_PROXY="${HTTPS_PROXY:-}" \
      --entrypoint nvidia-driver "${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES}" update -t builtin 2>&1 > "/tmp/kernel-module-build-${DRIVER_VERSION}.log"; then

      echo "***********************************************************************"
      echo "Kernel module compilation succeeded. Below are first 100 build log lines."
      echo "***********************************************************************"
      cat "/tmp/kernel-module-build-${DRIVER_VERSION}.log" | \
        grep -Ev "'naked' return found in RETHUNK build|missing int3 after ret" | \
        grep -v "'naked' return found in MITIGATION_RETHUNK build" | head -n 100 && true
      echo "...suppressed log lines..."
      cat "/tmp/kernel-module-build-${DRIVER_VERSION}.log" | \
        grep -Ev "'naked' return found in RETHUNK build|missing int3 after ret" | \
        grep -v "'naked' return found in MITIGATION_RETHUNK build" | tail -n 500 && true
      echo "***********************************************************************"
      echo "Kernel module compilation succeeded. Above are last 500 build log lines."
      echo "***********************************************************************"

      docker commit \
        -m "Compile Linux kernel modules version ${FEDORA_UNAME} for NVIDIA driver version ${DRIVER_VERSION}" \
        --change='ENTRYPOINT ["nvidia-driver", "init"]' \
        -c 'ENV HTTP_PROXY=' \
        -c 'ENV HTTPS_PROXY=' \
        "build-kernel-modules-${DRIVER_VERSION}" \
        "${DOCKER_IMAGE_WITH_PRECOMPILED_KERNEL_MODULES}"

      DOCKER_IMAGE="${DOCKER_IMAGE_WITH_PRECOMPILED_KERNEL_MODULES}"
      echo "Pushing ${DOCKER_IMAGE} with compiled kernel interface modules."
    else
      echo "***********************************************************************"
      echo "Kernel module compilation failed. Below are first 100 lines of log only."
      echo "***********************************************************************"
      cat "/tmp/kernel-module-build-${DRIVER_VERSION}.log" | \
        grep -Ev "'naked' return found in RETHUNK build|missing int3 after ret" | \
        grep -v "'naked' return found in MITIGATION_RETHUNK build" | head -n 100 && true
      echo "...suppressed log lines..."
      cat "/tmp/kernel-module-build-${DRIVER_VERSION}.log" | \
        grep -Ev "'naked' return found in RETHUNK build|missing int3 after ret" | \
        grep -v "'naked' return found in MITIGATION_RETHUNK build" | tail -n 500 && true
      echo "***********************************************************************"
      echo "Kernel module compilation failed. Above are last 500 lines of log only."
      echo "***********************************************************************"

      DOCKER_IMAGE="${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES}"
      echo "Pushing ${DOCKER_IMAGE} without compiled kernel interface modules."
    fi

    # Cleanup container
    docker rm -f "build-kernel-modules-${DRIVER_VERSION}" || true
  else
    DOCKER_IMAGE="${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES}"
    echo "Pushing ${DOCKER_IMAGE} to registry."
  fi

  # Authenticate to registry based on CI platform (if not already done)
  case "${CI_PLATFORM}" in
    "gitlab")
      if [[ -n "${CI_REGISTRY}" && -n "${CI_REGISTRY_USER}" && -n "${CI_REGISTRY_PASSWORD}" ]]; then
        docker login -u "${CI_REGISTRY_USER}" -p "${CI_REGISTRY_PASSWORD}" "${CI_REGISTRY}" 2>/dev/null || true
      fi
      ;;
    "github")
      # GitHub Actions authentication should be handled in workflow, but fallback if needed
      if [[ -n "${GITHUB_TOKEN}" && -n "${GITHUB_ACTOR}" ]]; then
        echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin 2>/dev/null || true
      fi
      ;;
  esac

  docker push -q "${DOCKER_IMAGE}"
else
  if ! $(docker manifest inspect "${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES}" > /dev/null 2>&1) || [[ "${OVERWRITE_TAG}" == "1" ]]; then
    # Authenticate to registry based on CI platform (if not already done)
    case "${CI_PLATFORM}" in
      "gitlab")
        if [[ -n "${CI_REGISTRY}" && -n "${CI_REGISTRY_USER}" && -n "${CI_REGISTRY_PASSWORD}" ]]; then
          docker login -u "${CI_REGISTRY_USER}" -p "${CI_REGISTRY_PASSWORD}" "${CI_REGISTRY}" 2>/dev/null || true
        fi
        ;;
      "github")
        # GitHub Actions authentication should be handled in workflow, but fallback if needed
        if [[ -n "${GITHUB_TOKEN}" && -n "${GITHUB_ACTOR}" ]]; then
          echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin 2>/dev/null || true
        fi
        ;;
    esac

    echo "Pushing ${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES} to registry."
    docker push -q "${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES}"
  else
    echo "Skipping push of ${DOCKER_IMAGE_NO_PRECOMPILED_KERNEL_MODULES} to registry."
  fi
fi
