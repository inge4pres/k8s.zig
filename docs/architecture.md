# Architecture Overview

This document describes the high-level architecture of k8s.zig, including component relationships, data flow, and design decisions.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Application                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Client Layer (client.zig)                   │
│  ┌─────────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ CRUD Operations │  │ Convenience  │  │   API Paths      │  │
│  │  - create()     │  │  Methods     │  │   - pods()       │  │
│  │  - get()        │  │  - listPods()│  │   - deployments()│  │
│  │  - update()     │  │  - getPod()  │  │   - services()   │  │
│  │  - patch()      │  │  - etc.      │  │   - etc.         │  │
│  │  - delete()     │  │              │  │                  │  │
│  └─────────────────┘  └──────────────┘  └──────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                 HTTP Layer (http_client.zig)                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ HttpClient - Wraps TlsHttpClient                         │  │
│  │  - Request preparation (headers, body, auth)             │  │
│  │  - Response parsing                                      │  │
│  │  - Content type handling (JSON/Protobuf)                 │  │
│  └──────────────┬───────────────────────────────────────────┘  │
└─────────────────┼──────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│            TLS Layer (tls_http_client.zig)                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ TlsHttpClient - Custom TLS using tls.zig                 │  │
│  │  - TCP connection establishment                          │  │
│  │  - TLS handshake (via tls.zig)                          │  │
│  │  - Certificate validation                                │  │
│  │  - Client certificate authentication                     │  │
│  │  - HTTP request/response handling                        │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌────────────────┐
                    │ Kubernetes API │
                    │     Server     │
                    └────────────────┘

                    Supporting Components
                    ════════════════════

┌─────────────────────────────────────────────────────────────────┐
│           Configuration (config.zig, kubeconfig.zig)             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Config - Unified configuration structure                 │  │
│  │  - Server URL                                            │  │
│  │  - Certificates (CA, client cert, client key)           │  │
│  │  - Authentication token                                  │  │
│  │  - TLS verification settings                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Kubeconfig - Kubeconfig file parser                     │  │
│  │  - Cluster, User, Context structures                    │  │
│  │  - JSON parsing                                          │  │
│  │  - Context resolution                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│            API Paths (api_paths.zig)                             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ApiPaths - Kubernetes API path construction             │  │
│  │  - Core resources: /api/v1/...                          │  │
│  │  - Grouped resources: /apis/{group}/{version}/...       │  │
│  │  - Namespace-scoped and cluster-scoped paths            │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              Generated Types (src/proto/)                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Protobuf-generated Zig types                            │  │
│  │  - Core resources (Pod, Service, ConfigMap, etc.)       │  │
│  │  - Apps resources (Deployment, StatefulSet, etc.)       │  │
│  │  - Batch resources (Job, CronJob)                       │  │
│  │  - Metadata types (ObjectMeta, TypeMeta, etc.)          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### Client Layer
**File:** `src/client.zig`

**Responsibilities:**
- Provide high-level API for Kubernetes operations
- Manage authentication state (bearer tokens)
- Coordinate between HTTP client and API path builder
- Expose convenience methods for common resources

**Key Methods:**
- `init()` - Initialize client with server URL and TLS options
- `get()`, `create()`, `update()`, `patch()`, `delete()` - Generic CRUD operations
- `listPods()`, `getPod()`, `listDeployments()`, etc. - Resource-specific helpers

**Dependencies:**
- HttpClient for network communication
- ApiPaths for URL construction
- Config for initialization parameters

### HTTP Layer
**Files:** `src/http_client.zig`, `src/tls_http_client.zig`

**Responsibilities:**
- Abstract HTTP/HTTPS communication
- Handle TLS certificate validation
- Support client certificate authentication
- Parse HTTP responses
- Manage content types (JSON/Protobuf)

**Key Methods:**
- `request()` - Generic HTTP request
- `get()`, `post()`, `put()`, `patch()`, `delete()` - HTTP verb helpers
- Certificate parsing and bundle management

**Dependencies:**
- TlsHttpClient for TLS connections
- tls.zig library for TLS handshake
- std.crypto.Certificate for certificate handling

### TLS Layer
**File:** `src/tls_http_client.zig`

**Responsibilities:**
- Establish TCP connections
- Perform TLS handshake using tls.zig
- Validate server certificates
- Support client certificate authentication
- Handle PKCS#1 to PKCS#8 conversion for client keys
- Build and send HTTP requests over TLS
- Parse HTTP responses

**Key Methods:**
- `request()` - Make HTTP/HTTPS request
- `requestTls()` - TLS-specific request handling
- `createCertKeyPair()` - Create client certificate pair
- `convertRsaKeyToPkcs8IfNeeded()` - Convert key formats
- `parseResponse()` - Parse HTTP response

**Dependencies:**
- tls.zig for TLS implementation
- std.net for TCP connections
- std.crypto.Certificate for certificate handling

### API Paths
**File:** `src/api_paths.zig`

**Responsibilities:**
- Construct valid Kubernetes API paths
- Support both core and grouped API resources
- Handle namespace-scoped and cluster-scoped resources
- Provide type-safe path construction

**Key Methods:**
- `coreResource()` - Build core API paths (/api/v1/...)
- `groupedResource()` - Build grouped API paths (/apis/{group}/{version}/...)
- Resource-specific helpers: `pods()`, `deployments()`, `services()`, etc.

**Path Formats:**
- Core resource: `{base_url}/api/v1/namespaces/{namespace}/{resource}/{name}`
- Grouped resource: `{base_url}/apis/{group}/{version}/namespaces/{namespace}/{resource}/{name}`
- Cluster-scoped: `{base_url}/api/v1/{resource}/{name}`

### Configuration
**Files:** `src/config.zig`, `src/kubeconfig.zig`

**Responsibilities:**
- Parse kubeconfig files (JSON format)
- Manage cluster, user, and context information
- Provide unified configuration structure
- Support in-cluster configuration
- Load credentials from various sources

**Key Structures:**
- `Config` - Unified configuration for client initialization
- `Kubeconfig` - Parsed kubeconfig file structure
- `Cluster` - Cluster connection information
- `User` - User authentication credentials
- `Context` - Links cluster, user, and namespace

### Generated Types
**Directory:** `src/proto/`

**Responsibilities:**
- Provide type-safe Zig structures for Kubernetes resources
- Support protobuf serialization/deserialization
- Enable compile-time type checking
- Mirror Kubernetes API structure

**Generated From:**
- Kubernetes protobuf definitions from kubernetes/api repository
- Core API: core/v1
- Apps API: apps/v1
- Batch API: batch/v1
- Apimachinery: meta/v1, runtime, resource, etc.

## Data Flow

### Request Flow

```
1. User calls client method
   client.listPods("default")
   │
   ▼
2. Client builds API path
   api_paths.pods("default", null)
   → "https://k8s.example.com/api/v1/namespaces/default/pods"
   │
   ▼
3. Client prepares authentication
   getAuthHeader() → "Bearer <token>"
   │
   ▼
4. HttpClient prepares request
   - Add Accept header (application/json or protobuf)
   - Add Authorization header
   - Add Content-Type if body present
   │
   ▼
5. TlsHttpClient establishes connection
   - Parse URL
   - Connect TCP socket
   - Perform TLS handshake
   - Create client cert pair if needed
   │
   ▼
6. TlsHttpClient sends HTTP request
   - Build HTTP request (method, path, headers, body)
   - Send over TLS connection
   │
   ▼
7. TlsHttpClient receives response
   - Read response data
   - Parse status line
   - Parse headers
   - Extract body
   │
   ▼
8. HttpClient wraps response
   - Create Response struct
   - Manage response memory
   │
   ▼
9. Client returns to user
   Response{ .status, .body, .allocator }
```

### Configuration Loading Flow

```
1. Load kubeconfig file
   Config.fromKubeconfigJSONFile(allocator, path)
   │
   ▼
2. Parse JSON content
   Kubeconfig.fromJson(allocator, content)
   - Parse clusters, users, contexts
   - Parse current-context
   │
   ▼
3. Resolve current context
   kubeconfig.getCurrentContext()
   │
   ▼
4. Find cluster and user
   kubeconfig.getCluster(context.cluster)
   kubeconfig.getUser(context.user)
   │
   ▼
5. Build Config structure
   Config{
     .server = cluster.server
     .certificate_authority_data = cluster.ca_data
     .client_certificate_data = user.cert_data
     .client_key_data = user.key_data
     .token = user.token
   }
   │
   ▼
6. Create client from config
   clientFromConfig(&config)
   │
   ▼
7. Initialize client with TLS options
   Client.init(allocator, config.server, .{
     .certificate_authority_data = config.ca_data,
     .client_certificate_data = config.cert_data,
     .client_key_data = config.key_data,
   })
```

## Memory Management

### Allocator Control
All components take an explicit allocator parameter, giving users full control over memory allocation strategy.

### Ownership Model
```zig
// Client owns its HTTP client and API paths
pub const Client = struct {
    allocator: std.mem.Allocator,  // For creating dynamic data
    http_client: HttpClient,        // Owned, deinitialized in deinit()
    api_paths: ApiPaths,            // Owned, contains allocator reference
    auth_token: ?[]const u8,        // Reference only (not owned)
};

// Responses are owned by the caller
pub const Response = struct {
    status: std.http.Status,        // Value type
    body: []const u8,               // Owned, allocated by allocator
    allocator: std.mem.Allocator,   // Needed for deinit()

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);  // Free owned memory
    }
};
```

### RAII Pattern
```zig
var client = try Client.init(allocator, url, .{});
defer client.deinit();  // Cleanup guaranteed

var response = try client.get(path, .json);
defer response.deinit();  // Response body freed
```

## Error Handling

### Error Sets
```zig
// TLS errors
error.TlsInitializationFailed
error.TlsHandshakeFailed
error.InvalidCertificate

// HTTP errors
error.ConnectionRefused
error.InvalidResponse
error.InvalidUri

// Parsing errors
error.InvalidJson
error.MissingEndCertificateMarker
error.KeyConversionFailed

// IO errors
error.OutOfMemory
error.FileNotFound
```

### Error Propagation
Errors are propagated using Zig's error unions (`!T`), allowing callers to handle or propagate as appropriate.

```zig
// Function returns error union
pub fn get(self: *Client, path: []const u8, accept: ContentType) !Response {
    const auth = try self.getAuthHeader();  // Propagate error
    defer if (auth) |a| self.allocator.free(a);

    return self.http_client.get(path, auth, accept);  // Return or propagate
}
```

## Threading Model

### Single-threaded
Currently, the library is single-threaded. Each client instance should be used from a single thread.

### Future: Async Support
Potential for async/await support in future versions:
- Async HTTP requests
- Connection pooling
- Concurrent operations

## Extension Points

### Custom Resources
The generic `get()`, `create()`, `update()`, `patch()`, `delete()` methods can be used for any Kubernetes resource, including Custom Resource Definitions (CRDs).

### Custom Authentication
New authentication methods can be added by extending the Client or implementing custom header providers.

### Custom Serialization
The ContentType enum can be extended to support additional serialization formats beyond JSON and Protobuf.

## Performance Considerations

### Connection Reuse
Currently, each request creates a new TCP/TLS connection. Connection pooling is planned for better performance.

### Protobuf vs JSON
Protobuf serialization is more efficient than JSON but requires generated types. JSON is more flexible and human-readable.

### Memory Allocations
- Path construction allocates strings (caller must free)
- Response bodies are allocated (caller must free via deinit())
- TLS buffers are stack-allocated where possible

### Zero-Copy
- Response bodies are read into allocated memory
- Future optimization: streaming response parsing

## Design Decisions

### Why Custom TLS Client?
Zig's `std.http.Client` has issues with TLS handshake on minikube and other self-signed certificate setups. Using tls.zig provides better compatibility.

### Why JSON Kubeconfig?
JSON parsing is built into Zig's standard library. YAML parsing would require external dependencies. Users can convert YAML to JSON using `kubectl config view --flatten -o json`.

### Why Explicit Allocators?
Following Zig's philosophy of explicit resource management. This gives users full control over memory allocation strategy and enables custom allocators for specific use cases.

### Why Generated Protobuf Types?
Type-safe API access with compile-time validation. Protobuf definitions are the source of truth for Kubernetes API structure.

## Future Improvements

1. Connection pooling for better performance
2. Async/await support for concurrent operations
3. Watch API for streaming updates
4. Pure Zig PKCS#1 to PKCS#8 conversion
5. YAML kubeconfig parsing
6. Strategic merge patch support
7. Improved error messages with context
8. Request/response logging and debugging
