const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import protobuf dependency
    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    // Import tls dependency
    const tls_dep = b.dependency("tls", .{
        .target = target,
        .optimize = optimize,
    });

    // Import yaml dependency
    const yaml_dep = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    // Create module for external use
    const k8s_module = b.addModule("k8s", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add protobuf module to k8s module
    k8s_module.addImport("protobuf", protobuf_dep.module("protobuf"));

    // Add tls module to k8s module
    k8s_module.addImport("tls", tls_dep.module("tls"));

    // Add yaml module to k8s module
    k8s_module.addImport("yaml", yaml_dep.module("yaml"));

    // Create the k8s.zig static library
    const lib = b.addLibrary(.{
        .name = "k8s",
        .root_module = k8s_module,
        .linkage = .static,
    });

    b.installArtifact(lib);

    // Proto code generation setup
    // The proto files use k8s.io import paths (e.g., k8s.io/api/core/v1/generated.proto).
    // These are resolved via symlinks in proto/k8s.io/ that point to the actual proto files.
    // See proto/README.md for details on the directory structure and import path mapping.
    const gen_proto_step = b.step("gen-proto", "Generate Zig code from protobuf definitions");

    // Define proto source files in dependency order (imported files must come before files that import them)
    // Use k8s.io import paths that match the import statements in the proto files
    const proto_files = [_][]const u8{
        // Base runtime types (no dependencies)
        "proto/k8s.io/apimachinery/pkg/runtime/generated.proto",
        "proto/k8s.io/apimachinery/pkg/runtime/schema/generated.proto",

        // Utility types (depend on runtime)
        "proto/k8s.io/apimachinery/pkg/util/intstr/generated.proto",
        "proto/k8s.io/apimachinery/pkg/api/resource/generated.proto",

        // Meta types (depend on runtime and schema)
        "proto/k8s.io/apimachinery/pkg/apis/meta/v1/generated.proto",

        // API types (depend on meta and other base types)
        "proto/k8s.io/api/core/v1/generated.proto",
        "proto/k8s.io/api/apps/v1/generated.proto",
        "proto/k8s.io/api/batch/v1/generated.proto",
    };

    // Create protoc generation step using zig-protobuf's RunProtocStep
    // The proto files use imports like "k8s.io/apimachinery/pkg/..." which map to "proto/apimachinery/..."
    const protoc_step = protobuf.RunProtocStep.create(protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/proto"),
        .source_files = &proto_files,
        .include_directories = &.{"proto"},
    });

    gen_proto_step.dependOn(&protoc_step.step);

    // Example executables
    const examples_step = b.step("examples", "Build example programs");

    const example_names = [_][]const u8{
        "list_pods",
        "get_deployment",
        "from_kubeconfig",
        "typed_resources",
    };

    // Test to demonstrate protobuf library issues
    const protobuf_test_module = b.createModule(.{
        .root_source_file = b.path("test_protobuf_issue.zig"),
        .target = target,
        .optimize = optimize,
    });
    protobuf_test_module.addImport("k8s", k8s_module);

    const protobuf_test_exe = b.addExecutable(.{
        .name = "test_protobuf_issue",
        .root_module = protobuf_test_module,
    });

    const install_protobuf_test = b.addInstallArtifact(protobuf_test_exe, .{});
    const protobuf_test_step = b.step("test-protobuf", "Build test that shows protobuf issues");
    protobuf_test_step.dependOn(&install_protobuf_test.step);

    // Test simple pod JSON parsing
    const simple_pod_test_module = b.createModule(.{
        .root_source_file = b.path("test_simple_pod.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_pod_test_module.addImport("k8s", k8s_module);

    const simple_pod_test_exe = b.addExecutable(.{
        .name = "test_simple_pod",
        .root_module = simple_pod_test_module,
    });

    const install_simple_pod_test = b.addInstallArtifact(simple_pod_test_exe, .{});
    const simple_pod_test_step = b.step("test-simple-pod", "Build test for simple pod JSON parsing");
    simple_pod_test_step.dependOn(&install_simple_pod_test.step);

    for (example_names) |example_name| {
        const example_path = b.fmt("examples/{s}.zig", .{example_name});

        // Create module for the example
        const example_module = b.createModule(.{
            .root_source_file = b.path(example_path),
            .target = target,
            .optimize = optimize,
        });

        // Add k8s module to example
        example_module.addImport("k8s", k8s_module);

        // Create executable
        const example_exe = b.addExecutable(.{
            .name = example_name,
            .root_module = example_module,
        });

        // Install the example executable
        const install_example = b.addInstallArtifact(example_exe, .{});
        examples_step.dependOn(&install_example.step);
    }

    // Unit tests
    const lib_tests = b.addTest(.{
        .root_module = k8s_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // TLS test with tls.zig library
    const tls_test_module = b.createModule(.{
        .root_source_file = b.path("test_tls_zig.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add tls module to the test
    tls_test_module.addImport("tls", tls_dep.module("tls"));

    const tls_test = b.addExecutable(.{
        .name = "test_tls_zig",
        .root_module = tls_test_module,
    });

    const install_tls_test = b.addInstallArtifact(tls_test, .{});

    const tls_test_step = b.step("test-tls", "Build and run TLS test with tls.zig");
    tls_test_step.dependOn(&install_tls_test.step);

    const run_tls_test = b.addRunArtifact(tls_test);
    const run_tls_step = b.step("run-tls-test", "Run TLS test with minikube");
    run_tls_step.dependOn(&run_tls_test.step);

    // YAML kubeconfig test
    const yaml_test_module = b.createModule(.{
        .root_source_file = b.path("test_yaml_kubeconfig.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add yaml module to the test
    yaml_test_module.addImport("yaml", yaml_dep.module("yaml"));

    const yaml_test = b.addExecutable(.{
        .name = "test_yaml_kubeconfig",
        .root_module = yaml_test_module,
    });

    const install_yaml_test = b.addInstallArtifact(yaml_test, .{});

    const yaml_test_step = b.step("test-yaml", "Build and run YAML kubeconfig test");
    yaml_test_step.dependOn(&install_yaml_test.step);

    const run_yaml_test = b.addRunArtifact(yaml_test);
    const run_yaml_step = b.step("run-yaml-test", "Run YAML kubeconfig parsing test");
    run_yaml_step.dependOn(&run_yaml_test.step);

    // YAML integration test with full k8s library
    const yaml_integration_module = b.createModule(.{
        .root_source_file = b.path("test_yaml_integration.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add k8s and yaml modules to the test
    yaml_integration_module.addImport("k8s", k8s_module);
    yaml_integration_module.addImport("yaml", yaml_dep.module("yaml"));

    const yaml_integration_test = b.addExecutable(.{
        .name = "test_yaml_integration",
        .root_module = yaml_integration_module,
    });

    const install_yaml_integration = b.addInstallArtifact(yaml_integration_test, .{});

    const yaml_integration_step = b.step("test-yaml-integration", "Build and run YAML integration test");
    yaml_integration_step.dependOn(&install_yaml_integration.step);

    const run_yaml_integration = b.addRunArtifact(yaml_integration_test);
    const run_yaml_integration_step = b.step("run-yaml-integration", "Run YAML integration test");
    run_yaml_integration_step.dependOn(&run_yaml_integration.step);
}
