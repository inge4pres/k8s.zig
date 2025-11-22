# k8s.zig

A native Zig client library for Kubernetes using protobuf-based API communication.

## Features

### Implemented ✅
- Type-safe Kubernetes API client
- HTTP/HTTPS communication with TLS support
- Kubeconfig file parsing (JSON format)
- Certificate-based authentication (client cert + key)
- Bearer token authentication
- HTTP chunked transfer encoding support
- CRUD operations (Create, Read, Update, Delete)
- API path builder for core and grouped resources
- Generated Zig types from Kubernetes protobuf definitions
- Support for core/v1, apps/v1, and batch/v1 resources
- Generic ResourceClient(T) pattern for type-safe operations

### Partially Implemented ⚠️
- Protobuf type deserialization (works for simple responses; complex Kubernetes runtime fields need work)
- Hybrid approach recommended: raw JSON for API calls + std.json for parsing

### Planned 🚧
- In-cluster authentication (service account)
- Watch functionality for real-time updates
- Patch operations (strategic merge, JSON patch)
- Label and field selectors
- More API group support (networking, rbac, policy, etc.)
- Robust protobuf deserialization for all Kubernetes response types

## Status

**Active Development** - Core functionality is working. See [ROADMAP.md](ROADMAP.md) for detailed implementation plan.

## Requirements

- Zig 0.15.1 or later
- `protoc` (Protocol Buffers compiler) - for generating code from proto files

## Building

```bash
# Build the library
zig build

# Run tests
zig build test

# Build example programs
zig build examples

# Generate Zig code from protobuf definitions
zig build gen-proto
```

## Quick Start

### Using Kubeconfig (Recommended)

```zig
const std = @import("std");
const k8s = @import("k8s");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load client from kubeconfig
    var client = try k8s.Client.fromKubeconfigJSONFile(allocator, "/home/user/.kube/config.json");
    defer client.deinit();

    // List pods in a namespace
    const path = try std.fmt.allocPrint(allocator, "{s}/api/v1/namespaces/default/pods", .{client.base_url});
    defer allocator.free(path);

    var response = try client.get(path, .json);
    defer response.deinit();

    std.debug.print("Status: {}\n", .{response.status});
    std.debug.print("Pods: {s}\n", .{response.body});
}
```

### Manual Configuration

```zig
var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc");
defer client.deinit();

// Set bearer token authentication
client.setAuthToken("your-bearer-token");

// Or use certificate-based authentication
try client.setClientCert(cert_pem, key_pem);
```

See [examples/](examples/) for more usage examples:
- `examples/from_kubeconfig.zig` - Loading from kubeconfig
- `examples/typed_resources.zig` - Using ResourceClient and typed access
- `examples/list_pods.zig` - Listing pods
- `examples/get_deployment.zig` - Getting deployments

## Architecture

```
k8s.zig/
├── src/
│   ├── lib.zig              # Main library entry point
│   ├── client.zig           # Kubernetes API client
│   ├── tls_http_client.zig  # HTTP client with TLS support
│   ├── resource_client.zig  # Generic ResourceClient(T) pattern
│   ├── kubeconfig.zig       # Kubeconfig file parsing
│   └── proto/               # Generated protobuf types
│       └── k8s/io/
│           ├── api/         # API resource types (Pod, Deployment, etc.)
│           └── apimachinery/  # Common types (ObjectMeta, TypeMeta)
├── proto/                   # Kubernetes protobuf definitions
│   └── k8s.io/             # Symlinked structure matching imports
│       ├── api/
│       │   ├── core/v1/
│       │   ├── apps/v1/
│       │   └── batch/v1/
│       └── apimachinery/pkg/
│           ├── apis/meta/v1/
│           ├── runtime/
│           └── util/
├── examples/                # Usage examples
│   ├── from_kubeconfig.zig  # Load client from kubeconfig
│   ├── typed_resources.zig  # Type-safe resource access
│   ├── list_pods.zig        # List pods example
│   └── get_deployment.zig   # Get deployment example
└── docs/                    # Documentation
    └── IMPLEMENTATION_SUMMARY.md
```

## API Reference

### Client

```zig
// Create a client from kubeconfig
var client = try k8s.Client.fromKubeconfigJSONFile(allocator, kubeconfig_path);
defer client.deinit();

// Or create manually
var client = try k8s.Client.init(allocator, base_url);
defer client.deinit();
client.setAuthToken(token);
try client.setClientCert(cert_pem, key_pem);

// CRUD operations
var response = try client.get(path, .json);
var response = try client.create(path, body, .json);
var response = try client.update(path, body, .json);
var response = try client.delete(path, .json);
```

### ResourceClient (Generic Type-Safe Pattern)

```zig
const v1 = k8s.proto.k8s.io.api.core.v1;

// Create a type-specific client - resource name and API version are automatically inferred!
const pod_client = k8s.ResourceClient(v1.Pod).init(&client);

// Operations (note: currently limited to simple responses)
const pod = try pod_client.get("namespace", "pod-name");
const list = try pod_client.list("namespace");
const created = try pod_client.create("namespace", pod_object);
const updated = try pod_client.update("namespace", "pod-name", pod_object);
try pod_client.delete("namespace", "pod-name");

// Works with 30+ standard Kubernetes resource types
const svc_client = k8s.ResourceClient(v1.Service).init(&client);
const ns_client = k8s.ResourceClient(v1.Namespace).init(&client);
```

### CustomResourceClient (For CRDs)

```zig
// For custom resources (CRDs), use CustomResourceClient and specify the resource name and API version
const crd_client = k8s.CustomResourceClient(MyCRD).init(&client, "mycrds", "mygroup.io/v1");

// Same operations as ResourceClient
const resource = try crd_client.get("namespace", "resource-name");
```

### Content Types

```zig
// JSON (recommended - most compatible)
var response = try client.get(path, .json);

// Protobuf (experimental - for future use)
var response = try client.get(path, .protobuf);
```

## Development

### Adding More API Groups

1. Download the proto file:
```bash
curl -sL https://raw.githubusercontent.com/kubernetes/api/master/networking/v1/generated.proto \
  -o proto/networking_v1_generated.proto
```

2. Add it to `build.zig` in the `proto_files` array

3. Regenerate:
```bash
zig build gen-proto
```

## Contributing

Contributions are welcome! Please see [ROADMAP.md](ROADMAP.md) for planned features.

## License

TBD
