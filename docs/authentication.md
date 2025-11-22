# Authentication

This document describes the authentication mechanisms supported by k8s.zig for connecting to Kubernetes API servers.

## Overview

k8s.zig supports multiple authentication methods commonly used with Kubernetes:

1. **Bearer Token Authentication** - Using service account tokens or user tokens
2. **Client Certificate Authentication** - Using X.509 client certificates
3. **In-Cluster Authentication** - Using service account tokens mounted in pods

## Authentication Flow

```
Client Request
     │
     ▼
┌─────────────────────────┐
│  Client.getAuthHeader() │
│  - Builds Authorization │
│    header if token set  │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  HttpClient.request()   │
│  - Adds Authorization   │
│    header to request    │
│  - Adds client cert if  │
│    configured           │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ TlsHttpClient.request() │
│  - Performs TLS         │
│    handshake with       │
│    client cert if set   │
└────────┬────────────────┘
         │
         ▼
  Kubernetes API Server
```

## Bearer Token Authentication

### Overview
Bearer tokens are the most common authentication method in Kubernetes. They can be:
- Service account tokens (JWT)
- User tokens from OpenID Connect (OIDC) providers
- Static tokens

### Implementation

**File:** `src/client.zig:45-54`

```zig
pub const Client = struct {
    auth_token: ?[]const u8 = null,

    /// Set the bearer token for authentication
    pub fn setAuthToken(self: *Client, token: []const u8) void {
        self.auth_token = token;
    }

    /// Build authorization header value
    fn getAuthHeader(self: *Client) !?[]const u8 {
        if (self.auth_token) |token| {
            return try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
        }
        return null;
    }
};
```

### Usage

```zig
var client = try Client.init(allocator, "https://kubernetes.default.svc", .{});
defer client.deinit();

// Set bearer token
client.setAuthToken("eyJhbGciOiJSUzI1NiIsImtpZCI6Ii...");

// Make authenticated request
var response = try client.listPods("default");
defer response.deinit();
```

### Token Sources

#### 1. Kubeconfig File
```zig
var config = try Config.fromKubeconfigJSONFile(allocator, path);
defer config.deinit();

var client = try clientFromConfig(&config);
defer client.deinit();

// Token is automatically set from kubeconfig user.token
```

#### 2. In-Cluster Service Account
```zig
var config = try Config.inCluster(allocator);
defer config.deinit();

var client = try clientFromConfig(&config);
defer client.deinit();

// Token is automatically read from /var/run/secrets/kubernetes.io/serviceaccount/token
```

#### 3. Manual Token
```zig
var client = try Client.init(allocator, url, .{});
defer client.deinit();

const token = "your-bearer-token";
client.setAuthToken(token);
```

### HTTP Header Format

```
Authorization: Bearer <token>
```

Example:
```
Authorization: Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6IjRlYzhjYTc...
```

## Client Certificate Authentication

### Overview
Client certificates (also called mutual TLS or mTLS) use X.509 certificates to authenticate clients. This method is commonly used for:
- Cluster administrators
- External automation tools
- High-security environments

### Implementation

**File:** `src/client.zig:15-24`

```zig
pub const InitOptions = struct {
    /// Base64-encoded PEM certificate data for the CA
    certificate_authority_data: ?[]const u8 = null,
    /// Base64-encoded PEM certificate data for client authentication
    client_certificate_data: ?[]const u8 = null,
    /// Base64-encoded PEM private key data for client authentication
    client_key_data: ?[]const u8 = null,
    /// Skip TLS certificate verification (insecure)
    insecure_skip_tls_verify: bool = false,
};
```

### Usage

```zig
// Base64-encoded PEM data
const ca_cert = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...";
const client_cert = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...";
const client_key = "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVkt...";

var client = try Client.init(allocator, "https://kubernetes.example.com:6443", .{
    .certificate_authority_data = ca_cert,
    .client_certificate_data = client_cert,
    .client_key_data = client_key,
});
defer client.deinit();

// Client certificate is automatically used for all requests
var response = try client.listPods("default");
defer response.deinit();
```

### Certificate Processing Flow

1. **Decode Base64** - Certificates are stored base64-encoded in kubeconfig
2. **Parse PEM** - Extract certificate and key from PEM format
3. **Convert Key Format** - Convert PKCS#1 to PKCS#8 if needed (see below)
4. **Create Cert-Key Pair** - Bundle certificate with private key
5. **TLS Handshake** - Use cert-key pair during TLS handshake

### PKCS#1 vs PKCS#8

**Problem:** tls.zig requires private keys in PKCS#8 format, but kubeconfig often stores them in PKCS#1 format.

**PKCS#1 Format** (RSA PRIVATE KEY):
```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----
```

**PKCS#8 Format** (PRIVATE KEY):
```
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEF...
-----END PRIVATE KEY-----
```

**Solution:** Automatic conversion using `convertRsaKeyToPkcs8IfNeeded()`

**File:** `src/tls_http_client.zig:213-263`

```zig
fn convertRsaKeyToPkcs8IfNeeded(self: *TlsHttpClient, key_pem: []const u8) ![]const u8 {
    // Check if this is an RSA PRIVATE KEY (PKCS#1 format)
    if (std.mem.indexOf(u8, key_pem, "-----BEGIN RSA PRIVATE KEY-----") == null) {
        // Not an RSA PRIVATE KEY, return as-is
        return key_pem;
    }

    // Use openssl to convert PKCS#1 to PKCS#8
    const result = try std.process.Child.run(.{
        .allocator = self.allocator,
        .argv = &[_][]const u8{
            "openssl",
            "pkcs8",
            "-topk8",
            "-nocrypt",
            "-in", temp_in,
            "-out", temp_out,
        },
    });

    // Return converted key
}
```

**Note:** Currently uses external `openssl` command. A pure Zig implementation is planned.

### Client Certificate Creation (TLS Layer)

**File:** `src/tls_http_client.zig:187-209`

```zig
fn createCertKeyPair(self: *TlsHttpClient) !tls.config.CertKeyPair {
    const cert_pem = self.client_cert_pem.?;
    const key_pem = self.client_key_pem.?;

    // 1. Parse client certificate into a bundle
    var cert_bundle: std.crypto.Certificate.Bundle = .{};
    errdefer cert_bundle.deinit(self.allocator);
    try self.parsePemCerts(&cert_bundle, cert_pem);

    // 2. Convert RSA PRIVATE KEY (PKCS#1) to PRIVATE KEY (PKCS#8) if needed
    const converted_key = try self.convertRsaKeyToPkcs8IfNeeded(key_pem);
    defer if (converted_key.ptr != key_pem.ptr) self.allocator.free(converted_key);

    // 3. Parse private key from PEM
    const private_key = try tls.config.PrivateKey.parsePem(converted_key);

    return tls.config.CertKeyPair{
        .bundle = cert_bundle,
        .key = private_key,
    };
}
```

### TLS Handshake with Client Certificate

**File:** `src/tls_http_client.zig:90-107`

```zig
fn requestTls(...) !Response {
    // Create client certificate pair if we have both cert and key
    var cert_key_pair_opt: ?tls.config.CertKeyPair = null;
    defer {
        if (cert_key_pair_opt) |*ckp| {
            ckp.deinit(self.allocator);
        }
    }

    if (self.client_cert_pem != null and self.client_key_pem != null) {
        cert_key_pair_opt = try self.createCertKeyPair();
    }

    // Upgrade to TLS using tls.zig with client certificate
    var tls_conn = try tls.clientFromStream(tcp_stream, .{
        .host = host,
        .root_ca = self.ca_bundle,
        .auth = if (cert_key_pair_opt) |*ckp| ckp else null,  // Client cert
    });
    defer tls_conn.close() catch {};

    // ... continue with request
}
```

## In-Cluster Authentication

### Overview
When running inside a Kubernetes pod, the pod has access to a service account token that can be used for authentication.

### Service Account Files
Kubernetes automatically mounts service account credentials in every pod:

- **Token:** `/var/run/secrets/kubernetes.io/serviceaccount/token`
- **CA Certificate:** `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
- **Namespace:** `/var/run/secrets/kubernetes.io/serviceaccount/namespace`

### Implementation

**File:** `src/config.zig`

```zig
/// Create configuration from in-cluster environment
pub fn inCluster(allocator: std.mem.Allocator) !Config {
    const token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token";
    const ca_path = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
    const namespace_path = "/var/run/secrets/kubernetes.io/serviceaccount/namespace";

    // Read token
    const token_file = try std.fs.openFileAbsolute(token_path, .{});
    defer token_file.close();
    const token = try token_file.readToEndAlloc(allocator, 4096);

    // Read CA certificate
    const ca_file = try std.fs.openFileAbsolute(ca_path, .{});
    defer ca_file.close();
    const ca_pem = try ca_file.readToEndAlloc(allocator, 4096);

    // Read namespace (optional)
    const namespace = blk: {
        const ns_file = std.fs.openFileAbsolute(namespace_path, .{}) catch break :blk null;
        defer if (ns_file) |f| f.close();
        break :blk try ns_file.?.readToEndAlloc(allocator, 256);
    };

    // Kubernetes API server is always at this address in-cluster
    const server = "https://kubernetes.default.svc";

    // Encode CA certificate to base64 (Config expects base64-encoded data)
    const ca_base64 = try encodeBase64(allocator, ca_pem);

    return Config{
        .allocator = allocator,
        .server = try allocator.dupe(u8, server),
        .certificate_authority_data = ca_base64,
        .token = token,
        .namespace = namespace,
    };
}
```

### Usage

```zig
// Detect and use in-cluster configuration
var config = try Config.inCluster(allocator);
defer config.deinit();

var client = try clientFromConfig(&config);
defer client.deinit();

// Token and CA are automatically configured
var response = try client.listPods(config.namespace.?);
defer response.deinit();
```

## CA Certificate Verification

### Purpose
CA (Certificate Authority) certificates are used to verify the identity of the Kubernetes API server.

### Loading CA Certificate

**From Kubeconfig:**
```zig
var client = try Client.init(allocator, url, .{
    .certificate_authority_data = ca_cert_base64,  // Base64-encoded PEM
});
```

**From System CA Bundle:**
```zig
// If certificate_authority_data is not provided, use system CA bundle
var client = try Client.init(allocator, url, .{});
```

### Certificate Bundle Creation

**File:** `src/http_client.zig:20-51`

```zig
pub fn init(allocator: std.mem.Allocator, options: InitOptions) !HttpClient {
    var ca_bundle: std.crypto.Certificate.Bundle = .{};
    var has_custom_ca = false;

    // Load CA bundle
    if (options.certificate_authority_data) |ca_data_b64| {
        has_custom_ca = true;
        // Decode base64 CA data to get PEM content
        const ca_pem = try decodeBase64(allocator, ca_data_b64);
        defer allocator.free(ca_pem);

        // Parse PEM certificates and add to bundle
        try parsePemCerts(&ca_bundle, allocator, ca_pem);
    } else if (!options.insecure_skip_tls_verify) {
        // Use system CA bundle
        try ca_bundle.rescan(allocator);
    }

    return HttpClient{
        .allocator = allocator,
        .tls_client = TlsHttpClient.init(allocator, ca_bundle, has_custom_ca, ...),
    };
}
```

### Insecure Mode (NOT RECOMMENDED)

For testing only, you can skip TLS verification:

```zig
var client = try Client.init(allocator, url, .{
    .insecure_skip_tls_verify = true,  // INSECURE - Do not use in production
});
```

**Warning:** This disables server certificate verification and should only be used in development environments.

## Authentication Priority

When multiple authentication methods are configured, they are used in this order:

1. **Client Certificate** - If both `client_certificate_data` and `client_key_data` are provided
2. **Bearer Token** - If set via `setAuthToken()` or from kubeconfig/in-cluster config

Both methods can be used simultaneously. The client certificate is used during TLS handshake, while the bearer token is sent as an HTTP header.

## Error Handling

### Authentication Errors

```zig
error.Unauthorized              // 401 - Invalid or missing credentials
error.Forbidden                 // 403 - Valid credentials but insufficient permissions
error.TlsInitializationFailed  // TLS handshake failed (cert issues)
error.InvalidCertificate       // Certificate parsing failed
error.KeyConversionFailed      // PKCS#1 to PKCS#8 conversion failed
error.FileNotFound             // In-cluster token/CA not found
```

### Handling Authentication Failures

```zig
const response = client.listPods("default") catch |err| {
    switch (err) {
        error.TlsInitializationFailed => {
            std.debug.print("TLS handshake failed - check certificates\n", .{});
            std.debug.print("Ensure CA certificate is valid\n", .{});
            return err;
        },
        else => {
            // Check HTTP status code in response for 401/403
            std.debug.print("Request failed: {}\n", .{err});
            return err;
        },
    }
};

// Check for HTTP-level auth errors
if (response.status == .unauthorized) {
    std.debug.print("Authentication failed - check token or client certificate\n", .{});
}
if (response.status == .forbidden) {
    std.debug.print("Insufficient permissions\n", .{});
}
```

## Best Practices

### 1. Store Credentials Securely
- Never hardcode tokens or certificates in source code
- Use environment variables or secure credential storage
- Rotate tokens regularly

### 2. Use Appropriate Authentication Method
- **In-cluster:** Use service account tokens (in-cluster config)
- **Development:** Use kubeconfig with user credentials
- **CI/CD:** Use service account tokens or OIDC
- **Production:** Use client certificates for non-human access

### 3. Verify Server Certificates
- Always use CA certificate verification in production
- Only use `insecure_skip_tls_verify` for local development

### 4. Principle of Least Privilege
- Use service accounts with minimal required permissions
- Regularly audit service account permissions

### 5. Handle Credential Expiration
```zig
const response = client.listPods("default") catch |err| {
    // Token may have expired
    if (response.status == .unauthorized) {
        // Refresh token and retry
    }
    return err;
};
```

## Future Enhancements

1. **OIDC Token Refresh** - Automatic token refresh for OIDC providers
2. **Token Expiration Detection** - Proactive token refresh
3. **Multiple Authentication Methods** - Support for auth provider chains
4. **Certificate Revocation** - CRL and OCSP support
5. **Pure Zig PKCS#1 to PKCS#8** - Remove openssl dependency
6. **Hardware Token Support** - PKCS#11 integration
7. **Kerberos/GSSAPI** - For enterprise environments
