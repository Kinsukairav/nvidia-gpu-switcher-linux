# Contributing to NVIDIA Optimus Wayland Fix

Thank you for considering a contribution! 🎉

---

## How Can I Contribute?

### 🧪 Report Your Hardware Compatibility

The most valuable contribution is **testing on your hardware**:

1. Open a [new issue](../../issues/new?template=compatibility-report.yml) using the **Compatibility Report** template
2. Include your laptop model, CPU, GPU, driver version
3. Report whether the GPU enters `suspended` state
4. Note your distro and desktop environment

### 🐛 Report a Bug

1. Open a [new issue](../../issues/new?template=bug-report.yml) using the **Bug Report** template
2. Include the exact steps you followed
3. Paste relevant error output or `journalctl` logs
4. Describe expected vs. actual behavior

### 📝 Submit a Pull Request

1. **Fork** this repository
2. **Create a branch**: `git checkout -b fix/description`
3. **Test your changes** on your hardware
4. **Commit**: `git commit -m "fix: description"`
5. **Push** and open a **PR** against `main`

---

## Style Guide

- Use **GitHub Flavored Markdown** for docs
- Follow [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
- Shell scripts should pass `shellcheck` without warnings
- Use `set -e` and proper error handling in all scripts

---

## Code of Conduct

Be respectful and constructive. We're all here to make Linux laptops work better.
