# Kubeconfig

This document describes how k8s.zig handles Kubernetes configuration files (kubeconfig), including parsing, context management, and credential extraction.

## Overview

Kubeconfig files store information about Kubernetes clusters, users, and contexts. k8s.zig provides:

- JSON kubeconfig parsing
- Context resolution
- Credential extraction
- Client initialization from kubeconfig

**Files:**
- `src/kubeconfig.zig` - Kubeconfig parsing
- `src/config.zig` - Unified configuration structure
- `src/client_from_config.zig` - Client creation from config

## Kubeconfig Structure

A kubeconfig file contains three main sections:

1. **Clusters** - Connection information for Kubernetes API servers
2. **Users** - Authentication credentials
3. **Contexts** - Links clusters with users and optional namespace

### Kubeconfig Components

```
┌──────────────────────────────────────────────┐
│              Kubeconfig File                 │
├──────────────────────────────────────────────┤
│  Clusters:                                   │
│    - name: production                        │
│      server: https://k8s-prod.example.com   │
│      certificate-authority-data: LS0t...    │
│                                              │
│  Users:                                      │
│    - name: admin                             │
│      client-certificate-data: LS0t...       │
│      client-key-data: LS0t...               │
│                                              │
│  Contexts:                                   │
│    - name: prod-admin                        │
│      cluster: production                     │
│      user: admin                             │
│      namespace: default                      │
│                                              │
│  current-context: prod-admin                 │
└──────────────────────────────────────────────┘
```

## Data Structures

**File:** `src/kubeconfig.zig`

### Cluster

```zig
pub const Cluster = struct {
    name: []const u8,
    server: []const u8,
    certificate_authority_data: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,

    pub fn deinit(self: *Cluster, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.server);
        if (self.certificate_authority_data) |ca| allocator.free(ca);
    }
};
```

Fields:
- `name` - Cluster identifier
- `server` - API server URL (e.g., "https://kubernetes.default.svc")
- `certificate_authority_data` - Base64-encoded CA certificate for server verification
- `insecure_skip_tls_verify` - Skip TLS verification (insecure)

### User

```zig
pub const User = struct {
    name: []const u8,
    token: ?[]const u8 = null,
    client_certificate_data: ?[]const u8 = null,
    client_key_data: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.token) |t| allocator.free(t);
        if (self.client_certificate_data) |c| allocator.free(c);
        if (self.client_key_data) |k| allocator.free(k);
        if (self.username) |u| allocator.free(u);
        if (self.password) |p| allocator.free(p);
    }
};
```

Fields:
- `name` - User identifier
- `token` - Bearer token for authentication
- `client_certificate_data` - Base64-encoded client certificate
- `client_key_data` - Base64-encoded client private key
- `username` - Basic auth username (rarely used)
- `password` - Basic auth password (rarely used)

### Context

```zig
pub const Context = struct {
    name: []const u8,
    cluster: []const u8,
    user: []const u8,
    namespace: ?[]const u8 = null,

    pub fn deinit(self: *Context, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cluster);
        allocator.free(self.user);
        if (self.namespace) |ns| allocator.free(ns);
    }
};
```

Fields:
- `name` - Context identifier
- `cluster` - Reference to cluster name
- `user` - Reference to user name
- `namespace` - Default namespace for operations

### Kubeconfig

```zig
pub const Kubeconfig = struct {
    allocator: std.mem.Allocator,
    clusters: []Cluster,
    users: []User,
    contexts: []Context,
    current_context: ?[]const u8,

    pub fn deinit(self: *Kubeconfig) void {
        for (self.clusters) |*cluster| cluster.deinit(self.allocator);
        self.allocator.free(self.clusters);

        for (self.users) |*user| user.deinit(self.allocator);
        self.allocator.free(self.users);

        for (self.contexts) |*context| context.deinit(self.allocator);
        self.allocator.free(self.contexts);

        if (self.current_context) |ctx| self.allocator.free(ctx);
    }
};
```

## Loading Kubeconfig

### From File

```zig
pub fn fromJsonFile(allocator: std.mem.Allocator, path: []const u8) !Kubeconfig
```

Example:
```zig
const std = @import("std");
const k8s = @import("k8s");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Load from JSON file
var kubeconfig = try k8s.Kubeconfig.fromJsonFile(allocator, "/home/user/.kube/config.json");
defer kubeconfig.deinit();
```

### From JSON String

```zig
pub fn fromJson(allocator: std.mem.Allocator, json_content: []const u8) !Kubeconfig
```

Example:
```zig
const json_content =
    \\{
    \\  "clusters": [...],
    \\  "users": [...],
    \\  "contexts": [...],
    \\  "current-context": "my-context"
    \\}
;

var kubeconfig = try k8s.Kubeconfig.fromJson(allocator, json_content);
defer kubeconfig.deinit();
```

### Converting YAML to JSON

k8s.zig only supports JSON kubeconfig files. Convert YAML to JSON using kubectl:

```bash
# Convert kubeconfig to JSON
kubectl config view --flatten -o json > ~/.kube/config.json

# Or for specific context
kubectl config view --context=my-context --flatten -o json > config.json
```

## Context Resolution

### Get Current Context

```zig
pub fn getCurrentContext(self: *const Kubeconfig) ?*const Context
```

Example:
```zig
var kubeconfig = try k8s.Kubeconfig.fromJsonFile(allocator, kubeconfig_path);
defer kubeconfig.deinit();

if (kubeconfig.getCurrentContext()) |context| {
    std.debug.print("Current context: {s}\n", .{context.name});
    std.debug.print("Cluster: {s}\n", .{context.cluster});
    std.debug.print("User: {s}\n", .{context.user});
    if (context.namespace) |ns| {
        std.debug.print("Namespace: {s}\n", .{ns});
    }
}
```

### Get Cluster by Name

```zig
pub fn getCluster(self: *const Kubeconfig, name: []const u8) ?*const Cluster
```

Example:
```zig
if (kubeconfig.getCluster("production")) |cluster| {
    std.debug.print("Server: {s}\n", .{cluster.server});
}
```

### Get User by Name

```zig
pub fn getUser(self: *const Kubeconfig, name: []const u8) ?*const User
```

Example:
```zig
if (kubeconfig.getUser("admin")) |user| {
    if (user.token) |token| {
        std.debug.print("Token: {s}\n", .{token});
    }
}
```

### Get Context by Name

```zig
pub fn getContext(self: *const Kubeconfig, name: []const u8) ?*const Context
```

Example:
```zig
if (kubeconfig.getContext("prod-admin")) |context| {
    std.debug.print("Namespace: {s}\n", .{context.namespace.?});
}
```

## Config Structure

**File:** `src/config.zig`

The `Config` struct provides a unified configuration for client initialization:

```zig
pub const Config = struct {
    allocator: std.mem.Allocator,
    server: []const u8,
    certificate_authority_data: ?[]const u8 = null,
    client_certificate_data: ?[]const u8 = null,
    client_key_data: ?[]const u8 = null,
    token: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,
    namespace: ?[]const u8 = null,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.server);
        if (self.certificate_authority_data) |ca| self.allocator.free(ca);
        if (self.client_certificate_data) |cert| self.allocator.free(cert);
        if (self.client_key_data) |key| self.allocator.free(key);
        if (self.token) |t| self.allocator.free(t);
        if (self.namespace) |ns| self.allocator.free(ns);
    }
};
```

### Loading Config from Kubeconfig File

```zig
pub fn fromKubeconfigJSONFile(allocator: std.mem.Allocator, path: []const u8) !Config
```

This function:
1. Loads kubeconfig from JSON file
2. Resolves current context
3. Finds cluster and user
4. Builds Config structure

Example:
```zig
var config = try k8s.Config.fromKubeconfigJSONFile(allocator, "~/.kube/config.json");
defer config.deinit();

std.debug.print("Server: {s}\n", .{config.server});
if (config.namespace) |ns| {
    std.debug.print("Namespace: {s}\n", .{ns});
}
```

### In-Cluster Configuration

```zig
pub fn inCluster(allocator: std.mem.Allocator) !Config
```

Loads configuration from service account files mounted in pods:

- Token: `/var/run/secrets/kubernetes.io/serviceaccount/token`
- CA: `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
- Namespace: `/var/run/secrets/kubernetes.io/serviceaccount/namespace`

Example:
```zig
var config = try k8s.Config.inCluster(allocator);
defer config.deinit();

// Automatically configured for in-cluster use
std.debug.print("Using in-cluster configuration\n", .{});
```

## Client Initialization

**File:** `src/client_from_config.zig`

### From Config

```zig
pub fn clientFromConfig(config: *const Config) !Client
```

Example:
```zig
var config = try k8s.Config.fromKubeconfigJSONFile(allocator, kubeconfig_path);
defer config.deinit();

var client = try k8s.clientFromConfig(&config);
defer client.deinit();

// Client is fully configured with credentials from kubeconfig
var response = try client.listPods(config.namespace.?);
defer response.deinit();
```

### From Kubeconfig File

```zig
pub fn clientFromKubeconfigFile(allocator: std.mem.Allocator, path: []const u8) !Client
```

Example:
```zig
var client = try k8s.clientFromKubeconfigFile(allocator, "~/.kube/config.json");
defer client.deinit();

var response = try client.listPods("default");
defer response.deinit();
```

### From In-Cluster Config

```zig
pub fn clientFromInCluster(allocator: std.mem.Allocator) !Client
```

Example:
```zig
var client = try k8s.clientFromInCluster(allocator);
defer client.deinit();

var response = try client.listPods("default");
defer response.deinit();
```

## Complete Example

```zig
const std = @import("std");
const k8s = @import("k8s");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load kubeconfig
    var config = try k8s.Config.fromKubeconfigJSONFile(
        allocator,
        "/home/user/.kube/config.json",
    );
    defer config.deinit();

    std.debug.print("Server: {s}\n", .{config.server});
    if (config.namespace) |ns| {
        std.debug.print("Namespace: {s}\n", .{ns});
    }

    // Create client from config
    var client = try k8s.clientFromConfig(&config);
    defer client.deinit();

    // Use client
    const namespace = config.namespace orelse "default";
    var response = try client.listPods(namespace);
    defer response.deinit();

    std.debug.print("Pods:\n{s}\n", .{response.body});
}
```

## Kubeconfig File Format

### JSON Structure

```json
{
  "apiVersion": "v1",
  "kind": "Config",
  "clusters": [
    {
      "name": "production",
      "cluster": {
        "server": "https://k8s-prod.example.com:6443",
        "certificate-authority-data": "LS0tLS1CRUdJTi..."
      }
    }
  ],
  "users": [
    {
      "name": "admin",
      "user": {
        "client-certificate-data": "LS0tLS1CRUdJTi...",
        "client-key-data": "LS0tLS1CRUdJTi..."
      }
    }
  ],
  "contexts": [
    {
      "name": "prod-admin",
      "context": {
        "cluster": "production",
        "user": "admin",
        "namespace": "default"
      }
    }
  ],
  "current-context": "prod-admin"
}
```

### Field Mapping

| Kubeconfig Field | Config Field | Description |
|-----------------|--------------|-------------|
| `cluster.server` | `server` | API server URL |
| `cluster.certificate-authority-data` | `certificate_authority_data` | CA cert (base64) |
| `cluster.insecure-skip-tls-verify` | `insecure_skip_tls_verify` | Skip TLS verify |
| `user.token` | `token` | Bearer token |
| `user.client-certificate-data` | `client_certificate_data` | Client cert (base64) |
| `user.client-key-data` | `client_key_data` | Client key (base64) |
| `context.namespace` | `namespace` | Default namespace |

## Error Handling

### File Not Found

```zig
const config = k8s.Config.fromKubeconfigJSONFile(allocator, path) catch |err| {
    switch (err) {
        error.FileNotFound => {
            std.debug.print("Kubeconfig file not found: {s}\n", .{path});
            return err;
        },
        else => return err,
    }
};
```

### Invalid JSON

```zig
const kubeconfig = k8s.Kubeconfig.fromJson(allocator, json_content) catch |err| {
    switch (err) {
        error.SyntaxError => {
            std.debug.print("Invalid JSON in kubeconfig\n", .{});
            return err;
        },
        else => return err,
    }
};
```

### Missing Context

```zig
var kubeconfig = try k8s.Kubeconfig.fromJsonFile(allocator, path);
defer kubeconfig.deinit();

const context = kubeconfig.getCurrentContext() orelse {
    std.debug.print("No current context set in kubeconfig\n", .{});
    return error.NoCurrentContext;
};
```

## Best Practices

### 1. Convert YAML to JSON

Always convert YAML kubeconfig to JSON before use:

```bash
kubectl config view --flatten -o json > config.json
```

### 2. Use defer for Cleanup

```zig
var config = try k8s.Config.fromKubeconfigJSONFile(allocator, path);
defer config.deinit();

var client = try k8s.clientFromConfig(&config);
defer client.deinit();
```

### 3. Check for Current Context

```zig
const context = kubeconfig.getCurrentContext() orelse {
    std.debug.print("No current context\n", .{});
    return error.NoCurrentContext;
};
```

### 4. Handle Missing Credentials

```zig
const user = kubeconfig.getUser(context.user) orelse {
    return error.UserNotFound;
};

if (user.token == null and user.client_certificate_data == null) {
    std.debug.print("No credentials configured for user\n", .{});
    return error.NoCredentials;
}
```

### 5. Validate Server URL

```zig
if (!std.mem.startsWith(u8, config.server, "https://")) {
    std.debug.print("Warning: Server URL is not HTTPS\n", .{});
}
```

## Limitations

### 1. YAML Not Supported

k8s.zig only supports JSON kubeconfig. Use kubectl to convert:

```bash
kubectl config view --flatten -o json > config.json
```

### 2. Limited Auth Methods

Currently supported:
- Bearer tokens
- Client certificates

Not yet supported:
- OIDC authentication
- External auth providers
- Exec-based authentication
- Auth provider plugins

### 3. No Context Switching

The library uses the `current-context` from the kubeconfig file. To switch contexts, either:
- Update the kubeconfig file externally
- Load a different kubeconfig file

## Future Enhancements

1. **YAML Support** - Direct YAML kubeconfig parsing
2. **Context Switching** - Programmatic context switching
3. **OIDC Support** - Token refresh and OIDC flows
4. **Exec Auth** - Support for exec-based auth providers
5. **Kubeconfig Merging** - Merge multiple kubeconfig files
6. **Credential Caching** - Cache and refresh credentials
7. **Config Validation** - Validate kubeconfig structure
8. **Config Updates** - Modify and save kubeconfig
