# k8s.zig Internals Documentation

This directory contains comprehensive documentation about the internals of k8s.zig, a native Zig client library for Kubernetes.

## Table of Contents

### Core Architecture
- [Architecture Overview](architecture.md) - High-level system design, component relationships, and data flow
- [API Client](api-client.md) - Client API design, CRUD operations, and resource management

### Network Layer
- [HTTP Layer](http-layer.md) - HTTP client implementation, TLS handling with tls.zig, and connection management
- [Authentication](authentication.md) - Authentication mechanisms (bearer tokens, client certificates, in-cluster auth)

### Configuration
- [Kubeconfig](kubeconfig.md) - Kubeconfig parsing, context management, and credential handling

### Data Layer
- [Protobuf Structure](protobuf-structure.md) - Kubernetes protobuf definitions and generated Zig types

### Development
- [Development Guide](development.md) - Build system, testing, code generation, and contribution guidelines

## Overview

k8s.zig is a native Zig implementation of a Kubernetes client library that provides:

1. **Type-safe API access** through generated protobuf bindings
2. **Flexible authentication** supporting multiple credential types
3. **Custom TLS implementation** using tls.zig to handle self-signed certificates
4. **Kubeconfig support** for standard Kubernetes configuration files
5. **Memory-safe operations** with explicit allocator control
6. **Zero-cost abstractions** leveraging Zig's compile-time features

## Key Components

### Client Layer (src/client.zig)
The main entry point for interacting with Kubernetes. Provides high-level methods for CRUD operations on resources.

**Key Files:**
- `src/client.zig` - Main client implementation
- `src/client_from_config.zig` - Helper functions for creating clients from configuration

### HTTP Layer (src/http_client.zig, src/tls_http_client.zig)
Handles HTTP/HTTPS communication with the Kubernetes API server. Uses a custom TLS implementation to work around limitations in Zig's standard library.

**Key Files:**
- `src/http_client.zig` - HTTP client wrapper
- `src/tls_http_client.zig` - Custom TLS client using tls.zig

### API Paths (src/api_paths.zig)
Constructs valid Kubernetes API paths for both core and grouped resources.

**Key Files:**
- `src/api_paths.zig` - Path builder for Kubernetes resources

### Configuration (src/config.zig, src/kubeconfig.zig)
Parses and manages Kubernetes configuration from kubeconfig files or in-cluster settings.

**Key Files:**
- `src/config.zig` - Configuration structure and loading
- `src/kubeconfig.zig` - Kubeconfig file parsing

### Generated Types (src/proto/)
Type-safe Zig structures generated from Kubernetes protobuf definitions.

**Key Files:**
- `src/proto/k8s/io/api/core/v1.pb.zig` - Core resources (Pod, Service, etc.)
- `src/proto/k8s/io/api/apps/v1.pb.zig` - Apps resources (Deployment, StatefulSet, etc.)
- `src/proto/k8s/io/api/batch/v1.pb.zig` - Batch resources (Job, CronJob)
- `src/proto/k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig` - Metadata types

## Design Principles

### 1. Memory Safety
- Explicit allocator control throughout the codebase
- No hidden allocations
- Clear ownership semantics with defer for cleanup
- RAII-style resource management

### 2. Type Safety
- Generated types from protobuf definitions
- Compile-time validation of API paths
- Zig's error unions for robust error handling
- No runtime type reflection

### 3. Performance
- Optional protobuf serialization for efficiency
- Minimal allocations in hot paths
- Zero-copy operations where possible
- Connection reuse (TODO)

### 4. Compatibility
- Works with self-signed certificates (minikube, kind, k3s)
- Supports standard kubeconfig files (JSON format)
- Compatible with in-cluster authentication
- Works with Zig 0.15.1+

## Common Patterns

### Client Initialization
```zig
// From explicit configuration
var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc", .{
    .certificate_authority_data = ca_cert_base64,
    .client_certificate_data = client_cert_base64,
    .client_key_data = client_key_base64,
});
defer client.deinit();

// From kubeconfig file
var config = try k8s.Config.fromKubeconfigJSONFile(allocator, kubeconfig_path);
defer config.deinit();
var client = try k8s.clientFromConfig(&config);
defer client.deinit();
```

### Resource Operations
```zig
// List resources
var response = try client.listPods("default");
defer response.deinit();

// Get a specific resource
var pod = try client.getPod("default", "my-pod");
defer pod.deinit();

// Generic operations
const path = try client.api_paths.deployments("default", "my-app");
defer allocator.free(path);
var deployment = try client.get(path, .json);
defer deployment.deinit();
```

### Error Handling
```zig
const response = client.getPod("default", "my-pod") catch |err| {
    switch (err) {
        error.ConnectionRefused => std.debug.print("Cannot connect to API server\n", .{}),
        error.TlsInitializationFailed => std.debug.print("TLS handshake failed\n", .{}),
        error.InvalidResponse => std.debug.print("Invalid response from server\n", .{}),
        else => return err,
    }
};
```

## Known Limitations

### TLS with std.http.Client
The standard library's `std.http.Client` has issues with TLS handshake on certain Kubernetes setups (see TLS_ISSUE_REPORT.md). We use a custom implementation based on [tls.zig](https://github.com/ianic/tls.zig) to work around this.

### PKCS#1 to PKCS#8 Conversion
Client certificate private keys in PKCS#1 format (RSA PRIVATE KEY) must be converted to PKCS#8 format (PRIVATE KEY). Currently, this uses an external `openssl` command. A pure Zig implementation is planned.

### YAML Kubeconfig
Only JSON kubeconfig files are supported. Use `kubectl config view --flatten -o json` to convert YAML to JSON.

## Next Steps

For detailed information on specific components, see the individual documentation files listed in the table of contents above.
