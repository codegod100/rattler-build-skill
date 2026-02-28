---
name: rattler-build
description: Build and upload conda packages from existing git repositories using rattler-build. Use this for creating recipes, building artifacts, and publishing to channels (including prefix.dev private channels).
---

# Rattler-build Skill

Use this skill to package existing repositories into conda artifacts and publish them.

## Prerequisites

- `rattler-build` installed.
- Network access for source download and channel upload.
- Auth configured for your target channel provider (prefix.dev, quetz, anaconda, s3, etc.).

## Workflow

1. Create a starter recipe.
2. Refine build/test/dependencies.
3. Build locally and validate.
4. Upload artifact to target channel.

**Always build locally before pushing to avoid CI failures.**

---

## 1) Bootstrap a recipe

```bash
# In this skill directory
./generate-git-recipe.sh https://github.com/org/repo.git --name my-package --version 0.1.0 --rev v0.1.0 --output recipe.yaml
```

Then edit `recipe.yaml`.

---

## 2) Important recipe fixes (common pitfalls)

### Use `tests`, not `test`
Top-level key must be `tests`:

```yaml
tests:
  - script:
      - my-binary --version
```

### If `source.git` checkout is empty, switch to tarball source
Some repos/tags can fail in git source mode depending on environment/cache state.
Use tarball URL + sha256 instead:

```yaml
source:
  url: https://github.com/<org>/<repo>/archive/refs/tags/<tag>.tar.gz
  sha256: <sha256>
```

### Meson feature values
Meson `feature` options use `enabled|disabled|auto` (not `true/false`).
String plugin toggles may use `'false'`.

### Python/numpy version constraints
`numpy <2` doesn't support Python 3.14+. Pin Python in both host and run requirements:

```yaml
requirements:
  host:
    - python >=3.9,<3.13
  run:
    - python >=3.9,<3.13
    - numpy <2
```

### Python scripts need shebang
Single-file Python scripts copied to `bin/` need a shebang to be executable:

```yaml
build:
  script:
    - mkdir -p $PREFIX/bin
    - |
      cat > $PREFIX/bin/myapp << 'EOF'
      #!/usr/bin/env python
      EOF
    - cat myapp.py >> $PREFIX/bin/myapp
    - chmod +x $PREFIX/bin/myapp
```

Without the shebang, you'll get: `Exec format error`

### Conda-forge package naming
Use exact package names from conda-forge:
- `pyqt6` (not `pyqt >=6`)
- `opencv` (not `opencv-python`)
- Use `pixi search <package>` to find correct names

Example:

```yaml
build:
  script:
    - meson setup build -Ddbus=disabled -Dlibcanberra=disabled -Dwith-lua='false' --prefix=$PREFIX
    - ninja -C build install
```

---

## 3) Build

```bash
rattler-build build --recipe recipe.yaml --output-dir ./output
```

Artifact is typically at:

```text
output/linux-64/<name>-<version>-<build>.conda
```

---

## 4) Pre-push Validation

**Always validate your build locally before pushing to avoid CI failures.**

### Test the built package

```bash
# Find the built artifact
ls -lh output/

# Test install locally (optional but recommended)
rattler-build test --package-path output/linux-64/<package>-<version>-<build>.conda
```

### Quick validation checklist

- [ ] Build completes without errors
- [ ] All tests pass (if defined in recipe)
- [ ] Package file is created in output directory
- [ ] Package size is reasonable (not suspiciously small/large)
- [ ] Dependencies are correct

### If multi-platform builds

For packages that build on multiple platforms (e.g., linux-64 and linux-aarch64), you may not be able to test all architectures locally. However, you should:

1. Build at least one platform locally to verify the recipe syntax
2. Review the recipe for platform-specific issues
3. Push and let CI validate all platforms

```bash
# Build for your native platform to catch syntax errors
rattler-build build --recipe recipe.yaml --output-dir ./output

# If that succeeds, the recipe should work in CI for other platforms too
```

### Only push after validation

```bash
# Review changes
git diff recipe.yaml

# Add and commit
git add recipe.yaml
git commit -m "Add/update conda recipe"

# Push to trigger CI
git push origin main
```

---

## 5) Upload

### prefix.dev (private/public channel)
If your channel URL is:

```text
https://prefix.dev/channels/nandi-testing
```

Use channel name `nandi-testing`:

```bash
rattler-build upload prefix \
  --channel nandi-testing \
  --skip-existing \
  output/linux-64/<artifact>.conda
```

**Tip**: Add `-vvv` for verbose output to confirm upload success:
```bash
rattler-build upload prefix -vvv --channel nandi-testing output/linux-64/<artifact>.conda
```

**Note**: A `502 Bad Gateway` error from prefix.dev can mean two things:
1. **Package already exists** - Increment `build.number` in your recipe and rebuild
2. **Upload succeeded but response failed** - The upload may have completed before the 502

To check if the upload actually succeeded, compare SHA256 hashes:

```bash
# Get your local hash
sha256sum output/linux-64/<package>-<version>-<build>.conda

# Check the channel's hash
pixi search <package-name> --channel https://prefix.dev/<channel>
```

If the SHA256 matches, the upload succeeded despite the 502. If not, increment `build.number` and rebuild.

If not logged in yet:

```bash
rattler-build auth login
```

Or pass API key via environment variable (`PREFIX_API_KEY`).

**Note for nandi-conda organization**: The `PREFIX_API_KEY` is already configured as an organization-level secret. When creating GitHub Actions workflows for nandi-conda repositories, you don't need to configure this secret manually - simply reference `${{ secrets.PREFIX_API_KEY }}` in your workflow and it will automatically use the org-level token.

---

## Example (minimal C/Meson package)

```yaml
package:
  name: example
  version: 1.0.0

source:
  url: https://github.com/org/example/archive/refs/tags/v1.0.0.tar.gz
  sha256: <sha256>

build:
  number: 0
  script:
    - meson setup build --prefix=$PREFIX
    - ninja -C build install

requirements:
  build:
    - meson
    - ninja
    - pkg-config
  host:
    - glib
  run:
    - glib

tests:
  - script:
      - example --version
```

---

## GitHub Actions

**Best Practice**: Always build and test your recipe locally before pushing. This catches syntax errors, missing dependencies, and other issues early, saving CI resources and time.

### Simple Workflow (no external actions required)

```yaml
name: Build and Publish Conda Package

on:
  push:
    branches:
      - main
      - master
    tags:
      - "v*"
  pull_request:

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install rattler-build
        run: |
          arch=$(uname -m)
          if [ "$arch" = "arm64" ]; then arch="aarch64"; fi
          curl -fsSL "https://github.com/prefix-dev/rattler-build/releases/latest/download/rattler-build-${arch}-unknown-linux-musl" \
            -o /usr/local/bin/rattler-build
          chmod +x /usr/local/bin/rattler-build
      - name: Build package
        run: rattler-build build --recipe recipe.yaml
      - name: Upload to prefix.dev
        if: github.event_name == 'push' && (startsWith(github.ref, 'refs/tags/') || github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master')
        env:
          PREFIX_API_KEY: ${{ secrets.PREFIX_API_KEY }}
        run: rattler-build upload prefix --channel nandi-testing --force output/**/*.conda
```

**Note**: The `PREFIX_API_KEY` is an org-level secret for nandi-conda. You don't need to configure it per-repository - just reference it in your workflow.

For non-nandi-conda organizations, you would need to:
1. Create a repository secret named `PREFIX_API_KEY` in your repo settings
2. Use the same workflow format above
3. Update the channel name to your own channel

### Multi-Platform Workflow (optional)

If you need to build for multiple architectures:

```yaml
jobs:
  build-and-publish:
    strategy:
      matrix:
        platform: [linux-64, linux-aarch64]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up QEMU (for aarch64)
        uses: docker/setup-qemu-action@v3
        with:
          platforms: linux/arm64
      - name: Install rattler-build
        run: |
          arch=$(uname -m)
          if [ "$arch" = "arm64" ]; then arch="aarch64"; fi
          curl -fsSL "https://github.com/prefix-dev/rattler-build/releases/latest/download/rattler-build-${arch}-unknown-linux-musl" \
            -o /usr/local/bin/rattler-build
          chmod +x /usr/local/bin/rattler-build
      - name: Build package
        run: rattler-build build --recipe recipe.yaml --target-platform ${{ matrix.platform }}
      - name: Upload to prefix.dev
        if: github.event_name == 'push'
        env:
          PREFIX_API_KEY: ${{ secrets.PREFIX_API_KEY }}
        run: rattler-build upload prefix --channel nandi-testing --force output/**/*.conda
```
