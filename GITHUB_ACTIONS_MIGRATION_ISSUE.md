# Add GitHub Actions CI/CD for FedoraCoreOS Driver Builds

## Summary

This issue tracks the implementation of GitHub Actions workflows to replace our current GitLab CI/CD pipeline while maintaining support for self-hosted FedoraCoreOS runners. This is an experimental feature to evaluate the migration from GitLab CI to GitHub Actions.

## Background

We currently use a specialized GitLab CI configuration (`.gitlab-ci-fcos.yml`) that builds NVIDIA driver containers specifically for FedoraCoreOS with pre-compiled kernel modules. The pipeline uses self-hosted GitLab runners tagged with `fcos-next`, `fcos-testing`, and `fcos-stable` to match the FedoraCoreOS release streams.

With the upstream project moving from GitLab to GitHub, we want to:
1. Migrate our CI/CD to GitHub Actions
2. Maintain our FedoraCoreOS-specific build pipeline
3. Continue using self-hosted runners running FedoraCoreOS
4. Preserve the kernel module pre-compilation functionality

## Proposed Solution

### GitHub Actions Workflow
- **File**: `.github/workflows/fcos.yaml`
- **Triggers**:
  - Push to `fedora**` branches
  - Tags ending with `fedora`
  - Scheduled daily builds
  - Manual workflow dispatch
- **Self-hosted runners**: Tagged as `fcos-next`, `fcos-testing`, `fcos-stable`

### Job Structure
1. **Development Builds** (`build-dev`): Single build on `fcos-next` for non-fedora branches
2. **Production Builds** (`build-prod`): Matrix builds across all FCOS streams for fedora branches/tags
3. **Security Scanning** (`scan-dev`/`scan-prod`): Trivy vulnerability scanning
4. **Release** (`release`/`release-dev`): Push to external registries

### Supporting Scripts
Located in `ci/fedora/`:
- `build_push_image.sh`: Build and push container images with optional kernel module compilation
- `scan_image.sh`: Security vulnerability scanning using Trivy
- `release_image.sh`: Release images to external registries

## Implementation Details

### Environment Variables
```yaml
DRIVER_VERSIONS: "535.261.03 570.172.08 580.65.06"
CUDA_VERSION: "12.8.1"
GOLANG_VERSION: "1.24.5"
CVE_UPDATES: "curl libc6"
```

### Workflow Inputs
- `overwrite_remote_tags`: Force overwrite remote registry tags
- `compile_kernel_modules`: Enable/disable kernel module compilation

### Self-Hosted Runner Requirements
- Runners must be tagged with: `fcos-next`, `fcos-testing`, `fcos-stable`
- Docker-in-Docker support required
- Privileged container execution for kernel module compilation
- Minimum 16GB RAM for kernel module compilation

### Registry Configuration
- **Development**: Uses GitHub Container Registry (`ghcr.io`)
- **Production**: Configurable external registry via secrets:
  - `RELEASE_REGISTRY_PROJECT`
  - `RELEASE_REGISTRY_USER`
  - `RELEASE_REGISTRY_TOKEN`

## Behavioral Differences from GitLab CI

### Branch/Tag Matching
- **Non-fedora branches**: Single build on `fcos-next` with commit SHA prefix
- **Fedora branches**: Full matrix build across all FCOS streams
- **Fedora tags**: Full build + scan + release to external registry
- **Scheduled builds**: Daily builds on all streams

### Kernel Module Compilation
- Attempts compilation in privileged container
- Falls back to non-precompiled image on failure
- Logs compilation output for debugging
- Commits successful compilation to new image tag

### Security Scanning
- Uses Trivy instead of GitLab container scanning
- Fails pipeline on detected vulnerabilities
- Uploads scan artifacts for review

## Files Changed

### New Files
- `.github/workflows/fcos.yaml` - Main GitHub Actions workflow
- `ci/fedora/build_push_image.sh` - Build and push script
- `ci/fedora/scan_image.sh` - Vulnerability scanning script
- `ci/fedora/release_image.sh` - Image release script

### Modified Files
- None (preserves existing GitLab CI configuration)

## Testing Strategy

1. **Feature Branch Testing**: Create `add-github-actions-experiment` branch
2. **Development Builds**: Test on non-fedora branches first
3. **Production Builds**: Test fedora branch builds without releases
4. **Security Scanning**: Verify Trivy integration
5. **Release Process**: Test with internal registry first

## Success Criteria

- [ ] GitHub Actions workflow executes successfully on self-hosted FCOS runners
- [ ] Kernel module compilation works in privileged containers
- [ ] Security scanning integrates properly with Trivy
- [ ] Image tagging matches GitLab CI behavior
- [ ] Release process works with external registries
- [ ] Build artifacts and logs are properly collected
- [ ] Performance is comparable to GitLab CI

## Risks and Considerations

1. **Runner Compatibility**: Self-hosted FCOS runners may need GitHub Actions runner configuration
2. **Container Privileges**: GitHub Actions may handle privileged containers differently
3. **Matrix Job Dependencies**: GitHub Actions matrix job dependency handling differs from GitLab
4. **Secret Management**: Need to migrate GitLab CI variables to GitHub secrets
5. **Registry Authentication**: Docker login patterns may need adjustment

## Labels
`phase::Doing,priority::High,type::New Feature`

## Related Issues
- Link to any upstream GitHub migration issues
- Link to FedoraCoreOS runner setup issues

## Definition of Done
- [ ] GitHub Actions workflow implemented and tested
- [ ] Self-hosted runners configured and working
- [ ] Security scanning functional
- [ ] Release process tested
- [ ] Documentation updated
- [ ] Feature branch merged to main
