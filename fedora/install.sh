#!/bin/bash
# Copyright (c) 2021-2023, NVIDIA CORPORATION. All rights reserved.

set -eu

DRIVER_ARCH=${TARGETARCH/amd64/x86_64} && DRIVER_ARCH=${DRIVER_ARCH/arm64/aarch64}
echo "DRIVER_ARCH is $DRIVER_ARCH"

dep_installer () {
  if [ "$DRIVER_ARCH" = "x86_64" ]; then
    dnf install -y \
        libglvnd-glx \
        ca-certificates \
        curl \
        gcc \
        glibc.i686 \
        make \
        cpio \
        kmod \
        jq
  elif [ "$DRIVER_ARCH" = "ppc64le" ]; then
    dnf install -y \
        libglvnd-glx \
        ca-certificates \
        curl \
        gcc \
        glibc \
        make \
        cpio \
        kmod \
        jq
  elif [ "$DRIVER_ARCH" = "aarch64" ]; then
    dnf install -y \
        libglvnd-glx \
        ca-certificates \
        curl \
        gcc \
        glibc \
        make \
        cpio \
        kmod \
        jq
  fi

  # Download unzboot as kernel images are compressed in the zboot format on RHEL 9 arm64
  # unzboot is only available on the EPEL RPM repo
  # rpm --import  https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
  # dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
  # dnf config-manager --enable epel
  # dnf install -y unzboot

  rm -rf /var/cache/yum/*
}

nvidia_installer () {
  if [ "$DRIVER_ARCH" = "x86_64" ]; then
    ./nvidia-installer --silent \
                       --no-kernel-module \
                       --install-compat32-libs \
                       --no-nouveau-check \
                       --no-nvidia-modprobe \
                       --no-rpms \
                       --no-backup \
                       --no-check-for-alternate-installs \
                       --no-libglx-indirect \
                       --no-install-libglvnd \
                       --x-prefix=/tmp/null \
                       --x-module-path=/tmp/null \
                       --x-library-path=/tmp/null \
                       --x-sysconfig-path=/tmp/null
  elif [ "$DRIVER_ARCH" = "ppc64le" ]; then
    ./nvidia-installer --silent \
                       --no-kernel-module \
                       --no-nouveau-check \
                       --no-nvidia-modprobe \
                       --no-rpms \
                       --no-backup \
                       --no-check-for-alternate-installs \
                       --no-libglx-indirect \
                       --no-install-libglvnd \
                       --x-prefix=/tmp/null \
                       --x-module-path=/tmp/null \
                       --x-library-path=/tmp/null \
                       --x-sysconfig-path=/tmp/null
  elif [ "$DRIVER_ARCH" = "aarch64" ]; then
    ./nvidia-installer --silent \
                       --no-kernel-module \
                       --no-nouveau-check \
                       --no-nvidia-modprobe \
                       --no-rpms \
                       --no-backup \
                       --no-check-for-alternate-installs \
                       --no-libglx-indirect \
                       --no-install-libglvnd \
                       --x-prefix=/tmp/null \
                       --x-module-path=/tmp/null \
                       --x-library-path=/tmp/null \
                       --x-sysconfig-path=/tmp/null
  else
    echo "DRIVER_ARCH doesn't match a known arch target"
  fi
}

fabricmanager_install() {
  if [ "$DRIVER_BRANCH" -ge "580" ]; then
    dnf install -y nvidia-fabricmanager-${DRIVER_VERSION}-1
  else
    dnf install -y nvidia-fabric-manager-${DRIVER_VERSION}-1
  fi
}

nscq_install() {
  if [ "$DRIVER_BRANCH" -ge "580" ]; then
    dnf install -y libnvidia-nscq-${DRIVER_VERSION}-1
  else
    dnf install -y libnvidia-nscq-${DRIVER_BRANCH}-${DRIVER_VERSION}-1
  fi
}

# libnvsdm packages are not available for arm64
nvsdm_install() {
  if [ "$TARGETARCH" = "amd64" ]; then
    if [ "$DRIVER_BRANCH" -ge "580" ]; then
      dnf install -y libnvsdm-${DRIVER_VERSION}-1
      return 0
    fi
    if [ "$DRIVER_BRANCH" -ge "570" ]; then
      dnf install -y libnvsdm-${DRIVER_BRANCH}-${DRIVER_VERSION}-1
      return 0
    fi
  fi
}

nvlink5_pkgs_install() {
  if [ "$DRIVER_BRANCH" -ge "550" ]; then
    dnf install -y infiniband-diags nvlsm
  fi
}

imex_install() {
  if [ "$DRIVER_BRANCH" -ge "580" ]; then
    dnf install -y nvidia-imex-${DRIVER_VERSION}-1
  elif [ "$DRIVER_BRANCH" -ge "550" ]; then
    dnf install -y nvidia-imex-${DRIVER_BRANCH}-${DRIVER_VERSION}-1
  fi
}

extra_pkgs_install() {
  if [ "$DRIVER_TYPE" != "vgpu" ]; then
      dnf module enable -y --skip-unavailable nvidia-driver:${DRIVER_BRANCH}-dkms | true
      if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Failed to enable nvidia-driver module ${DRIVER_BRANCH}-dkms"
        exit 1
      fi

      fabricmanager_install
      nscq_install
      nvsdm_install
      nvlink5_pkgs_install
      imex_install
  fi
}

setup_cuda_repo() {
    OS_ARCH=${TARGETARCH/amd64/x86_64} && OS_ARCH=${OS_ARCH/arm64/sbsa};
    FEDORA_VERSION_ID=$(cat /etc/os-release | grep VERSION_ID | cut -d = -f2)
    curl -s -L https://developer.download.nvidia.com/compute/cuda/repos/fedora${FEDORA_VERSION_ID}/${OS_ARCH}/cuda-fedora${FEDORA_VERSION_ID}.repo | \
      sudo tee /etc/yum.repos.d/cuda-fedora${FEDORA_VERSION_ID}.repo
}

if [ "$1" = "nvinstall" ]; then
  nvidia_installer
elif [ "$1" = "depinstall" ]; then
  dep_installer
elif [ "$1" = "extrapkgsinstall" ]; then
  echo "Skipping extra_pkgs_install (no Fedora43 artifacts exist presently)"
  # TODO: Re-enable when Fedora43 packages become available."
  # extra_pkgs_install
elif [ "$1" = "setup_cuda_repo" ]; then
  echo "Skipping setup_cuda_repo (no Fedora43 artifacts exist presently)"
  # TODO: Re-enable when Fedora43 packages become available."
  # setup_cuda_repo
else
  echo "Unknown function: $1"
fi
