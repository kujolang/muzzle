# Build Check Example

This example packages a safe Bash workflow with a manifest. Copy both directories into an initialized project's `.muzzle/` directory:

```bash
cp -R /path/to/muzzle/examples/build-check/workflows/. .muzzle/workflows/
cp -R /path/to/muzzle/examples/build-check/manifests/. .muzzle/manifests/
muzzle info build-check
muzzle run build-check
```

The workflow detects common local build entrypoints and runs one build check. Review it before use, especially in repositories where build scripts execute third-party hooks.
