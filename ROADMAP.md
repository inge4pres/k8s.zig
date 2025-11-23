# k8s.zig - Kubernetes Client Library Roadmap

A Zig library for interacting with Kubernetes clusters using protobuf-based API communication.

## Overview

This project aims to create a native Zig client library for Kubernetes that:
- Uses protobuf for efficient serialization (with JSON fallback)
- Provides type-safe access to Kubernetes resources
- Supports standard Kubernetes authentication mechanisms
- Implements core CRUD operations and watch functionality

## Implementation Steps

### Phase 1: Project Foundation ✅
- [x] Create basic project structure
- [x] Set up build.zig with proper dependencies
- [x] Configure zig-protobuf dependency (github.com/Arwalk/zig-protobuf)
- [x] Create initial directory structure (src/, proto/, examples/, tests/)

### Phase 2: Protobuf Integration ✅
- [x] Research Kubernetes protobuf structure
  - Kubernetes uses protobuf for internal communication
  - Proto files location: https://github.com/kubernetes/kubernetes/tree/*/staging/src/k8s.io/api
  - Key API groups: core/v1, apps/v1, batch/v1, etc.
- [x] Download relevant .proto files from kubernetes/kubernetes repo
  - Core API resources (Pod, Service, ConfigMap, Secret)
  - Apps API (Deployment, StatefulSet, DaemonSet)
  - Batch API (Job, CronJob)
  - Common types (ObjectMeta, TypeMeta, ListMeta)
- [x] Organize proto files in proto/ directory
- [x] Set up code generation pipeline in build.zig
- [x] Generate Zig types from proto files using zig-protobuf

### Phase 3: HTTP Client & Communication ✅
- [x] Implement HTTP/HTTPS client using std.http
- [x] Support TLS/SSL for secure connections
- [x] Handle request construction (method, path, headers, body)
- [x] Handle response parsing (status codes, headers, body)
- [x] Implement error handling
- [x] Support different content types (application/json, application/vnd.kubernetes.protobuf)
- [ ] Implement retry logic with exponential backoff

### Phase 4: Authentication ✅
- [x] Implement bearer token authentication
- [x] Implement client certificate authentication
- [x] Support in-cluster authentication (service account tokens)
- [x] Parse and load credentials from kubeconfig file
- [ ] Implement basic authentication (if needed)

### Phase 5: Kubeconfig Support ✅
- [x] Parse kubeconfig YAML format
- [x] Parse kubeconfig JSON format
- [x] Support multiple contexts
- [x] Handle cluster, user, and context configurations
- [x] Support certificate file paths (certificate-authority, client-certificate, client-key)
- [x] Support inline certificate data (certificate-authority-data, client-certificate-data, client-key-data)
- [x] Handle base64 encoding/decoding with whitespace stripping
- [x] Support namespace defaults
- [ ] Implement context switching API

### Phase 6: Core API Operations ✅
- [x] Implement Create operation (POST)
- [x] Implement Read operation (GET single resource)
- [x] Implement Update operation (PUT)
- [x] Implement Patch operation (PATCH)
- [x] Implement Delete operation (DELETE)
- [x] Implement List operation (GET collection)
- [ ] Implement pagination support (continue tokens, limits)
- [ ] Implement Watch operation (GET with ?watch=true, handle streaming)

### Phase 7: Resource Type Support ✅
- [x] Core/v1 resources
  - Pod, Service, ConfigMap, Secret, Namespace, Node, PersistentVolume, etc.
- [x] Apps/v1 resources
  - Deployment, StatefulSet, DaemonSet, ReplicaSet
- [x] Batch/v1 resources
  - Job, CronJob
- [x] Generic resource handler for custom CRDs (CustomResourceClient)
- [x] Generic ResourceClient(T) pattern with automatic resource name/version inference

### Phase 8: Advanced Features
- [ ] Field selectors
- [ ] Label selectors
- [ ] Resource quotas and limits
- [ ] Status subresource handling
- [ ] Scale subresource
- [ ] Exec/logs/port-forward operations

### Phase 9: Testing & Examples
- [x] Unit tests for kubeconfig parsing
- [x] Example: Load from kubeconfig (YAML)
- [x] Example: List pods in namespace
- [x] Example: Get deployment
- [x] Example: Typed resource access with ResourceClient
- [ ] Unit tests for authentication
- [ ] Unit tests for request building
- [ ] Unit tests for response parsing
- [ ] Integration tests (requires K8s cluster)
- [ ] Example: Create deployment
- [ ] Example: Watch events
- [ ] Example: Read logs from pod

### Phase 10: Documentation & Polish
- [x] Basic README.md with usage examples
- [x] ROADMAP.md with implementation status
- [x] Architecture documentation
- [ ] Comprehensive API documentation
- [ ] Contributing guide
- [ ] Performance benchmarks

## Technical Notes

### Kubernetes API Details
- **Base URL format**: `https://<server>:<port>/api/<version>` or `/apis/<group>/<version>`
- **Resource paths**: `/api/v1/namespaces/<namespace>/<resources>/<name>`
- **Serialization**: JSON (default), Protobuf (optional, more efficient)
- **API groups**: Core (no group prefix), Named groups (apps, batch, etc.)
- **Versioning**: Alpha (v1alpha1), Beta (v1beta1), Stable (v1, v2)

### Dependencies
- **zig-protobuf**: For generating Zig code from .proto files
- **std.http**: For HTTP client functionality
- **std.json**: For JSON parsing/serialization (fallback)
- **tls.zig**: For TLS/SSL support

### Design Decisions
1. **Protobuf-first**: Use protobuf serialization when possible for performance
2. **Type-safe**: Leverage Zig's compile-time features for type safety
3. **Memory-conscious**: Minimize allocations, provide allocator control
4. **Error handling**: Use Zig error unions for robust error handling
5. **Async support**: Consider async I/O for better performance

## Current Status

**Completed Phases**: 1-7 (Project Foundation through Resource Type Support)
**Current Phase**: 8 (Advanced Features)
**Progress**: ~75% complete

### Recent Achievements
- ✅ Full kubeconfig support (YAML and JSON)
- ✅ Certificate file path and inline data support
- ✅ Whitespace handling in base64-encoded certificates
- ✅ Generic ResourceClient(T) pattern
- ✅ In-cluster authentication
- ✅ Complete CRUD operations

### Next Priorities
1. Watch functionality for real-time resource updates
2. Label and field selectors for filtered queries
3. Pagination support for large resource lists
4. Strategic merge patch support
5. Comprehensive unit and integration tests
