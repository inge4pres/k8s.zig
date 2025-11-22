# Development Guide

This document describes the development workflow for k8s.zig, including build system, testing, code generation, and contribution guidelines.

## Prerequisites

### Required Tools

- **Zig 0.15.1 or later** - Download from [ziglang.org](https://ziglang.org/download/)
- **protoc** (Protocol Buffers compiler) - For generating code from proto files
- **openssl** - For PKCS#1 to PKCS#8 key conversion (temporary, will be replaced)

### Optional Tools

- **kubectl** - For working with Kubernetes clusters
- **minikube** or **kind** - For local Kubernetes testing

### Installing Zig

```bash
# Linux/macOS
wget https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz
tar -xf zig-linux-x86_64-0.15.1.tar.xz
export PATH=$PATH:$(pwd)/zig-linux-x86_64-0.15.1

# Or use zigup
zigup 0.15.1
```

### Installing protoc

```bash
# Ubuntu/Debian
sudo apt install protobuf-compiler

# macOS
brew install protobuf

# Or download from GitHub
wget https://github.com/protocolbuffers/protobuf/releases/download/v21.12/protoc-21.12-linux-x86_64.zip
unzip protoc-21.12-linux-x86_64.zip -d $HOME/.local
```

## Project Structure

```
k8s.zig/
├── build.zig              # Build configuration
├── build.zig.zon         # Dependency management
├── src/
│   ├── lib.zig           # Main library entry point
│   ├── client.zig        # Client implementation
│   ├── http_client.zig   # HTTP layer
│   ├── tls_http_client.zig # TLS layer
│   ├── api_paths.zig     # API path construction
│   ├── config.zig        # Configuration
│   ├── kubeconfig.zig    # Kubeconfig parsing
│   ├── client_from_config.zig # Client helpers
│   └── proto/            # Generated protobuf types
│       └── k8s/io/
├── proto/                # Kubernetes protobuf definitions
│   ├── k8s.io/          # Symlinks for import resolution
│   └── *.proto          # Proto source files
├── examples/             # Example programs
│   ├── list_pods.zig
│   ├── get_deployment.zig
│   └── from_kubeconfig.zig
├── docs/                 # Documentation
│   ├── README.md
│   ├── architecture.md
│   └── ...
└── tests/                # Test files
```

## Build System

k8s.zig uses Zig's build system (build.zig) with support for:
- Library compilation
- Example programs
- Protobuf code generation
- Testing

**File:** `build.zig`

### Dependencies

Declared in `build.zig.zon`:

```zig
.dependencies = .{
    .protobuf = .{
        .url = "https://github.com/Arwalk/zig-protobuf/archive/refs/tags/v0.2.0.tar.gz",
        .hash = "...",
    },
    .tls = .{
        .url = "https://github.com/ianic/tls.zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

### Build Commands

```bash
# Build the library
zig build

# Build and run tests
zig build test

# Build example programs
zig build examples

# Generate protobuf code
zig build gen-proto

# Build TLS test
zig build test-tls

# Run TLS test
zig build run-tls-test
```

### Build Artifacts

After building, artifacts are located in:

```
zig-out/
├── lib/
│   └── libk8s.a      # Static library
└── bin/
    ├── list_pods      # Example executables
    ├── get_deployment
    └── from_kubeconfig
```

## Module System

k8s.zig is organized as a Zig module that can be imported by other projects.

### Exposing the Module

**File:** `build.zig:20-31`

```zig
// Create module for external use
const k8s_module = b.addModule("k8s", .{
    .root_source_file = b.path("src/lib.zig"),
    .target = target,
    .optimize = optimize,
});

// Add dependencies
k8s_module.addImport("protobuf", protobuf_dep.module("protobuf"));
k8s_module.addImport("tls", tls_dep.module("tls"));
```

### Using k8s.zig in Other Projects

**build.zig.zon:**
```zig
.dependencies = .{
    .k8s = .{
        .url = "https://github.com/inge4pres/k8s.zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

**build.zig:**
```zig
const k8s_dep = b.dependency("k8s", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("k8s", k8s_dep.module("k8s"));
```

**main.zig:**
```zig
const k8s = @import("k8s");

pub fn main() !void {
    var client = try k8s.Client.init(...);
    defer client.deinit();
}
```

## Protobuf Code Generation

### Proto Files

Kubernetes API protobuf definitions are stored in `proto/`:

```
proto/
├── k8s.io/                          # Symlinks for import resolution
│   ├── api/                         # -> ../
│   ├── apimachinery/               # -> ../apimachinery/
│   └── ...
├── api/
│   ├── core/v1/generated.proto
│   ├── apps/v1/generated.proto
│   └── batch/v1/generated.proto
└── apimachinery/
    ├── pkg/apis/meta/v1/generated.proto
    ├── pkg/runtime/generated.proto
    └── ...
```

### Import Path Resolution

Proto files use imports like:
```protobuf
import "k8s.io/apimachinery/pkg/runtime/generated.proto";
```

These are resolved via symlinks in `proto/k8s.io/` that point to the actual files.

### Generating Code

```bash
zig build gen-proto
```

This generates Zig types in `src/proto/`:

```
src/proto/
└── k8s/io/
    ├── api/
    │   ├── core/v1.pb.zig
    │   ├── apps/v1.pb.zig
    │   └── batch/v1.pb.zig
    └── apimachinery/
        └── pkg/
            ├── apis/meta/v1.pb.zig
            ├── runtime.pb.zig
            └── ...
```

### Adding New API Groups

1. Download the proto file:
```bash
curl -sL https://raw.githubusercontent.com/kubernetes/api/master/networking/v1/generated.proto \
  -o proto/api/networking/v1/generated.proto
```

2. Add to `proto_files` array in `build.zig`:
```zig
const proto_files = [_][]const u8{
    // ... existing files ...
    "proto/k8s.io/api/networking/v1/generated.proto",
};
```

3. Regenerate:
```bash
zig build gen-proto
```

## Testing

### Unit Tests

Tests are embedded in source files using Zig's `test` keyword.

Example:
```zig
// In src/api_paths.zig
test "ApiPaths - core resource paths" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const paths = ApiPaths.init(allocator, "https://kubernetes.default.svc");

    const pod_path = try paths.pods("default", "my-pod");
    defer allocator.free(pod_path);

    try testing.expectEqualStrings(
        "https://kubernetes.default.svc/api/v1/namespaces/default/pods/my-pod",
        pod_path,
    );
}
```

### Running Tests

```bash
# Run all unit tests
zig build test

# Run tests with verbose output
zig build test --summary all

# Run specific test file
zig test src/api_paths.zig
```

### Integration Tests

Integration tests require a running Kubernetes cluster:

```bash
# Start minikube
minikube start

# Get kubeconfig in JSON format
kubectl config view --flatten -o json > config.json

# Run integration test
zig build run-integration-test
```

### TLS Testing

Special test for TLS functionality:

```bash
# Build TLS test
zig build test-tls

# Run TLS test with minikube
zig build run-tls-test
```

## Code Style

### Zig Formatting

Use `zig fmt` to format all code:

```bash
# Format all files
zig fmt src/
zig fmt examples/
zig fmt build.zig

# Format specific file
zig fmt src/client.zig
```

### Naming Conventions

- **Types:** PascalCase (`Client`, `HttpClient`, `ApiPaths`)
- **Functions:** camelCase (`init`, `deinit`, `listPods`)
- **Constants:** SCREAMING_SNAKE_CASE or camelCase for compile-time constants
- **Variables:** snake_case (`base_url`, `http_client`)

### Documentation Comments

Use `///` for documentation comments:

```zig
/// Kubernetes API Client
///
/// Provides methods to interact with Kubernetes resources through the API server.
pub const Client = struct {
    /// Initialize a new client
    ///
    /// Arguments:
    ///   - allocator: Memory allocator
    ///   - base_url: Kubernetes API server URL
    ///   - options: TLS and authentication options
    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, options: InitOptions) !Client {
        // ...
    }
};
```

## Error Handling

### Error Sets

Define clear error sets:

```zig
pub const ClientError = error{
    InvalidUrl,
    ConnectionFailed,
    AuthenticationFailed,
    ResourceNotFound,
};
```

### Error Propagation

Use `try` for error propagation:

```zig
pub fn getPod(self: *Client, namespace: []const u8, name: []const u8) !Response {
    const path = try self.api_paths.pods(namespace, name);
    defer self.allocator.free(path);

    return try self.get(path, .json);
}
```

### Error Context

Provide context in error returns:

```zig
const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
    std.debug.print("Failed to open {s}: {}\n", .{path, err});
    return err;
};
```

## Memory Management

### Allocator Usage

Always use the provided allocator, never use a global allocator:

```zig
pub fn init(allocator: std.mem.Allocator, ...) !Client {
    return Client{
        .allocator = allocator,
        // ...
    };
}
```

### RAII Pattern

Use `defer` for cleanup:

```zig
pub fn init(allocator: std.mem.Allocator, base_url: []const u8, options: InitOptions) !Client {
    var ca_bundle: std.crypto.Certificate.Bundle = .{};
    errdefer ca_bundle.deinit(allocator);  // Cleanup on error

    // ... initialization ...

    return Client{
        .allocator = allocator,
        // ...
    };
}

pub fn deinit(self: *Client) void {
    self.http_client.deinit();
    // Free other owned resources
}
```

### Ownership

Document ownership clearly:

```zig
pub const Response = struct {
    status: std.http.Status,
    body: []const u8,  // Owned - must be freed
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);  // Free owned memory
    }
};
```

## Contributing

### Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes
4. Format code: `zig fmt .`
5. Run tests: `zig build test`
6. Commit changes: `git commit -m "Add feature"`
7. Push to fork: `git push origin feature-name`
8. Create pull request

### Commit Messages

Use clear, descriptive commit messages:

```
Add support for ConfigMap resources

- Add configMaps() method to ApiPaths
- Add listConfigMaps() convenience method to Client
- Add tests for ConfigMap operations
```

### Pull Request Guidelines

- One feature per pull request
- Include tests for new functionality
- Update documentation
- Ensure all tests pass
- Follow existing code style

### What to Contribute

See `ROADMAP.md` for planned features. Good first contributions:

- Additional convenience methods for resources
- More API group support (networking, rbac, etc.)
- Improved error messages
- Documentation improvements
- Bug fixes

## Debugging

### Verbose Logging

Add debug prints during development:

```zig
std.debug.print("Connecting to: {s}\n", .{url});
std.debug.print("Status code: {}\n", .{response.status});
std.debug.print("Response body: {s}\n", .{response.body});
```

### TLS Debugging

Enable TLS debugging in tls.zig:

```zig
// Temporarily add to tls_http_client.zig
std.debug.print("TLS handshake with {s}\n", .{host});
std.debug.print("CA bundle has {} certs\n", .{self.ca_bundle.map.count()});
```

### HTTP Debugging

Print full HTTP request/response:

```zig
std.debug.print("Request:\n{s}\n", .{request_buf.items});
std.debug.print("Response:\n{s}\n", .{response_data});
```

## Common Issues

### TLS Handshake Failed

**Problem:** `error.TlsInitializationFailed` when connecting to Kubernetes

**Solution:**
- Ensure CA certificate is correctly loaded
- Verify server certificate includes correct SANs
- Check `TLS_ISSUE_REPORT.md` for details

### Out of Memory

**Problem:** `error.OutOfMemory` when reading responses

**Solution:**
- Increase allocator limits
- Use streaming for large responses (future feature)
- Check for memory leaks (missing `defer` statements)

### Protobuf Generation Fails

**Problem:** `zig build gen-proto` fails

**Solution:**
- Ensure protoc is installed: `protoc --version`
- Check proto file import paths
- Verify symlinks in `proto/k8s.io/`

## Performance Optimization

### Profiling

Use Zig's built-in profiler:

```bash
zig build -Drelease-fast
valgrind --tool=callgrind ./zig-out/bin/example
```

### Allocation Tracking

Track allocations during development:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{
    .safety = true,
    .verbose_log = true,
}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("Memory leak detected!\n", .{});
    }
}
```

### Optimization Tips

- Use `.ReleaseFast` for production builds
- Minimize allocations in hot paths
- Reuse buffers where possible
- Use stack allocation for small, fixed-size data

## Release Process

### Version Numbering

Follow Semantic Versioning:
- MAJOR: Breaking API changes
- MINOR: New features, backwards compatible
- PATCH: Bug fixes

### Creating a Release

1. Update version in build.zig.zon
2. Update CHANGELOG.md
3. Run full test suite
4. Tag release: `git tag v0.1.0`
5. Push tag: `git push origin v0.1.0`
6. Create GitHub release

## Resources

### External Links

- [Zig Language](https://ziglang.org/)
- [Zig Standard Library Docs](https://ziglang.org/documentation/master/std/)
- [zig-protobuf](https://github.com/Arwalk/zig-protobuf)
- [tls.zig](https://github.com/ianic/tls.zig)
- [Kubernetes API Docs](https://kubernetes.io/docs/reference/kubernetes-api/)

### Internal Documentation

- [Architecture](architecture.md)
- [HTTP Layer](http-layer.md)
- [Authentication](authentication.md)
- [API Client](api-client.md)
- [Kubeconfig](kubeconfig.md)
- [Protobuf Structure](protobuf-structure.md)
