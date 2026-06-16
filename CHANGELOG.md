# Changelog

## 0.1.0-beta.1

First public beta of capp-build, the new Cappuccino Objective-J compiler and build tool.

### What this is

capp-build compiles Objective-J applications and produces browser-loadable build output in the same layout as the legacy jake toolchain. Existing server configurations, deployment scripts, and application code require no changes.

### What works

The full compilation pipeline is implemented and verified against the legacy toolchain:

- Project validation and Info.plist generation
- Source tree walking and Objective-J parsing
- Import resolution and topological sort
- Symbol table construction (classes, methods, protocols, ivars, accessors)
- Protocol conformance checking
- JavaScript code generation, byte-exact against the legacy compiler in both debug and release modes
- Application deliverable assembly under `Build/Debug/<Name>/` and `Build/Release/<Name>/`, including framework copying, resource copying, and index.html

Compiled applications load and run correctly in all modern browsers.

### Known limitations

**Grammar library must be installed manually.** capp-build requires the Objective-J tree-sitter grammar dynamic library to be present at `/usr/local/lib`. Download the appropriate library for your platform from the tree-sitter-objj releases page and install it there. Automatic installation will be handled by the Cappuccino omnibus CLI in a future release.

**XIB compilation is not yet implemented.** The `.xib` → `.cib` compilation step (`nib2cib`) is not yet part of capp-build. Before building, compile your XIB files using the legacy toolchain (`nib2cib`) and commit the resulting `.cib` files to your project's `Resources/` directory. capp-build will copy them into the build output as-is.

**Info.plist size reporting is approximate.** The `CPApplicationSize` entry in the generated Info.plist reports only the application bundle size, not the total of all loaded framework bundles. The loading progress bar will reach 100% slightly later than with a legacy build. This will be corrected in a future release.

**HTTP/2 delivery is not yet implemented.** capp-build currently targets HTTP/1.x delivery only. HTTP/2 support, which serves compiled records individually for multiplexed loading, will be added alongside the built-in development server in the Cappuccino omnibus CLI.

### Platforms

macOS (arm64, x86_64), Linux (arm64, x86_64), Windows (arm64, x86_64).
