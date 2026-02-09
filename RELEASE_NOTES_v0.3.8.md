## What's Changed

### 🔒 Security Update: Alpine Linux Upgrade

This release upgrades the base Docker image from **Alpine 3.21.3** to **Alpine 3.23.3** (latest stable) to address security vulnerabilities (CVEs) present in the older version.

### 🛡️ Security Improvements

**Alpine Linux:** 3.21.3 → **3.23.3** (released January 27, 2026)
- ✅ Addresses multiple CVEs in Alpine 3.21.3
- ✅ Latest stable Alpine release with security patches
- ✅ End-of-support: November 1, 2027

**Key Dependency Updates:**
- 🔐 **curl:** 8.12.1 → **8.17.0** (significant security updates)
- 🐚 **bash:** 5.2.37 → **5.3.3**
- ✅ **transmission-remote:** 4.0.6 (maintained)
- ✅ **jq:** 1.8.1 (maintained)

### 📦 Changes

* Upgrade Alpine Linux from 3.21.3 to 3.23.3 for security patches by @miklosbagi in 6b656e8

### 🔍 Testing

All tests pass with Alpine 3.23.3:
- ✅ Linting (shellcheck + hadolint)
- ✅ Security tests (credential removal verification)
- ✅ DEBUG mode tests
- ✅ Functional smoke tests
- ✅ Country jump tests
- ✅ Port forwarding functionality

### 📊 Image Details

**Size:** 24.1 MB (up from 22.8 MB in v0.3.7)
- +1.3 MB increase (~5%) due to security patches and updated dependencies
- Acceptable trade-off for enhanced security

**Platforms:**
- ✅ linux/amd64
- ✅ linux/arm64

### 🐳 Docker Images

Available on:
- **Docker Hub**: `miklosbagi/gluetrans:latest` or `miklosbagi/gluetrans:v0.3.8`
- **GHCR**: `ghcr.io/miklosbagi/gluetranspia:latest` or `ghcr.io/miklosbagi/gluetranspia:v0.3.8`

### ⚡ Impact

**For Users:**
- ✅ No configuration changes required
- ✅ Automatic upgrade when pulling `:latest`
- ✅ Pin to `v0.3.8` for reproducible builds
- ✅ Enhanced security posture

**Compatibility:**
- ✅ All v0.3.7 features maintained
- ✅ Security credential removal (v0.3.7)
- ✅ Gluetun v3.41.0 API support (v0.3.6)
- ✅ Automatic backward compatibility (v0.3.6)

### 📖 Recommendation

**Upgrade immediately** if you're using:
- `miklosbagi/gluetrans:latest` - pull the new image
- `miklosbagi/gluetrans:v0.3.7` or older - update to `v0.3.8`

This is a **security patch release** addressing base image vulnerabilities.

**Full Changelog**: https://github.com/miklosbagi/gluetrans/compare/v0.3.7...v0.3.8
