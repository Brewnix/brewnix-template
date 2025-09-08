# BrewNix Architecture: Design Principles and Layout Choices

## Overview

This document outlines the architectural principles and design decisions that govern the BrewNix network infrastructure management system. These principles ensure long-term maintainability, scalability, and proper separation of concerns.

## Core Architectural Principles

### 1. Separation of Design and Instance Management

**Principle**: Design artifacts (reusable components, shared functionality) must be strictly separated from instance management (site-specific configurations, deployment orchestration).

**Rationale**:

- **Maintainability**: Changes to design don't break instance management
- **Reusability**: Design components can be shared across multiple instances
- **Testability**: Design and instance management can be tested independently
- **Scalability**: New instances can be created without duplicating design artifacts

**Implementation**:

```text
brewnix-template/          # Instance Management Layer
├── config/                # Site-specific configurations
├── scripts/               # Instance orchestration scripts
├── vendor/                # References to design submodules
│   ├── common/           # Shared design components (submodule)
│   ├── proxmox-firewall/ # Vendor-specific design (submodule)
│   ├── k3s-cluster/      # Vendor-specific design (submodule)
│   └── proxmox-nas/      # Vendor-specific design (submodule)
└── docs/                  # Instance-specific documentation
```

### 2. Git Submodules for Design Components

**Principle**: All design artifacts must be managed as Git submodules to maintain clear boundaries and enable independent versioning.

**Rationale**:

- **Version Control**: Each design component can be versioned independently
- **Dependency Management**: Clear dependency relationships between components
- **Collaboration**: Multiple teams can work on different design components simultaneously
- **Release Management**: Design components can be released and updated independently

**Implementation**:

- `vendor/common/`: Shared functionality used by all vendor implementations
- `vendor/{vendor-name}/`: Vendor-specific design and implementation
- Template repo references submodules but doesn't contain design code

### 3. Modular Script Architecture

**Principle**: Scripts must be organized into focused modules with clear responsibilities and interfaces.

**Rationale**:

- **Single Responsibility**: Each module handles one concern
- **Testability**: Modules can be unit tested independently
- **Maintainability**: Changes are localized to specific modules
- **Reusability**: Modules can be composed for different use cases

**Implementation**:

```text
scripts/
├── core/                  # Shared core functionality
│   ├── init.sh           # Environment setup and validation
│   ├── config.sh         # Configuration management
│   └── logging.sh        # Centralized logging
├── {feature}/            # Feature-specific modules
│   ├── {feature}.sh      # Main feature implementation
│   └── supporting files
└── brewnix.sh            # Main orchestrator and router
```

### 4. Configuration Hierarchy and Inheritance

**Principle**: Configuration must support hierarchical inheritance with clear precedence rules.

**Rationale**:

- **Flexibility**: Site-specific overrides without duplicating common config
- **Maintainability**: Common configuration changes propagate automatically
- **Validation**: Configuration can be validated at each level
- **Documentation**: Clear understanding of configuration sources

**Implementation**:

```text
config/
├── defaults.yml          # System-wide defaults
├── site1/
│   ├── site.yml         # Site-specific configuration
│   └── devices/         # Device-specific overrides
└── inheritance rules:
    Device > Site > Vendor Defaults > System Defaults
```

## Design vs. Instance Management Boundaries

### What Belongs in Design (Submodules)

**✅ Design Components**:

- Reusable Ansible roles and playbooks
- Shared utility scripts and libraries
- Common validation logic
- Testing frameworks and test suites
- Documentation templates
- CI/CD workflow templates
- Vendor-specific implementation details

**❌ What Does NOT Belong in Design**:

- Site-specific configurations
- Environment-specific variables
- Deployment orchestration scripts
- Instance management workflows
- Site-specific documentation

### What Belongs in Instance Management (Template)

**✅ Instance Management Components**:

- Site-specific configuration files
- Deployment orchestration scripts
- Environment-specific variables
- Instance management workflows
- Site-specific documentation
- Integration testing across submodules
- Cross-vendor coordination logic

**❌ What Does NOT Belong in Instance Management**:

- Reusable Ansible roles
- Shared utility libraries
- Common validation logic
- Vendor-specific implementation details
- Design documentation

## Submodule Organization Principles

### 1. Vendor Submodules (`vendor/{vendor-name}/`)

**Purpose**: Contain vendor-specific design and implementation details.

**Contents**:

```text
vendor/{vendor-name}/
├── ansible/              # Vendor-specific playbooks and roles
├── scripts/              # Vendor-specific scripts
├── config/               # Vendor default configurations
├── docs/                 # Vendor-specific documentation
├── tests/                # Vendor-specific tests
└── CI/CD workflows for vendor validation
```

**Responsibilities**:

- Implement vendor-specific functionality
- Provide vendor-specific configurations
- Handle vendor-specific testing
- Maintain vendor-specific documentation

### 2. Common Submodule (`vendor/common/`)

**Purpose**: Contain shared functionality used across all vendor implementations.

**Contents**:

```text
vendor/common/
├── ansible/              # Common playbooks and roles
├── scripts/              # Shared utility scripts
├── common/               # Shared libraries and utilities
├── deployment/           # Common deployment logic
├── docker-test-framework/ # Testing infrastructure
└── docs/                 # Common documentation
```

**Responsibilities**:

- Provide shared functionality
- Define common interfaces
- Implement cross-vendor utilities
- Maintain common documentation

**Constraints**:

- Must be vendor-agnostic
- Cannot contain vendor-specific logic
- Must be usable by all vendor implementations
- Changes must be backward compatible

## Workflow and CI/CD Architecture

### 1. Submodule-Level Workflows

**Purpose**: Validate individual design components independently.

**Location**: Within each submodule (`vendor/{vendor-name}/.github/workflows/`)

**Responsibilities**:

- Unit testing of submodule components
- Integration testing within the submodule
- Code quality checks
- Documentation validation
- Release preparation

### 2. Template-Level Workflows

**Purpose**: Validate integration across all submodules and instance management.

**Location**: Template repo (`.github/workflows/`)

**Responsibilities**:

- Cross-submodule integration testing
- End-to-end deployment validation
- Instance management testing
- Release coordination across submodules
- Overall system validation

### 3. Workflow Dependencies

**Template workflows depend on submodule workflows**:

- Submodule workflows run first and must pass
- Template workflows test integration
- Failures in submodules block template workflows
- Success in all components enables releases

## Testing Strategy

### 1. Unit Testing (Submodule Level)

**Location**: Within each submodule
**Scope**: Individual components and functions
**Tools**: Language-specific testing frameworks
**Execution**: Submodule CI/CD pipelines

### 2. Integration Testing (Submodule Level)

**Location**: Within each submodule
**Scope**: Component interactions within the submodule
**Tools**: Docker Compose, local test environments
**Execution**: Submodule CI/CD pipelines

### 3. Cross-Submodule Testing (Template Level)

**Location**: Template repo
**Scope**: Interactions between submodules
**Tools**: Docker Compose, multi-service test environments
**Execution**: Template CI/CD pipelines

### 4. End-to-End Testing (Template Level)

**Location**: Template repo
**Scope**: Complete system deployment and operation
**Tools**: Full environment simulation
**Execution**: Template CI/CD pipelines

## Configuration Management

### 1. Configuration Sources

**Hierarchy** (highest to lowest precedence):

1. **Instance-specific overrides** (template repo)
2. **Site-specific configuration** (template repo)
3. **Vendor defaults** (vendor submodules)
4. **System defaults** (common submodule)

### 2. Configuration Validation

**Multi-level validation**:

- **Syntax validation**: YAML/JSON structure
- **Schema validation**: Required fields and types
- **Cross-reference validation**: Dependencies between components
- **Business logic validation**: Configuration consistency

### 3. Configuration Discovery

**Automatic discovery mechanisms**:

- **File-based**: Standard locations and naming conventions
- **Environment-based**: Environment variable overrides
- **Runtime-based**: Dynamic configuration from external sources

## Documentation Strategy

### 1. Documentation Locations

**Design Documentation** (Submodules):

- API documentation
- Implementation guides
- Architecture decisions
- Code documentation

**Instance Documentation** (Template):

- Deployment guides
- Configuration examples
- Troubleshooting guides
- Integration documentation

### 2. Documentation Standards

**Required documentation**:

- README.md in every directory
- API documentation for public interfaces
- Architecture decision records (ADRs)
- Troubleshooting guides
- Migration guides

## Migration and Evolution

### 1. Adding New Vendors

**Process**:

1. Create new vendor submodule
2. Implement vendor-specific functionality
3. Add submodule reference to template
4. Update common interfaces if needed
5. Add vendor to integration tests

### 2. Evolving Common Interfaces

**Process**:

1. Assess impact on existing vendors
2. Provide migration path
3. Update all affected submodules
4. Update integration tests
5. Communicate changes to teams

### 3. Deprecating Functionality

**Process**:

1. Mark functionality as deprecated
2. Provide migration documentation
3. Maintain backward compatibility
4. Remove in future major version
5. Update all dependent components

## Quality Assurance

### 1. Code Quality Standards

**Enforced standards**:

- Linting and formatting
- Code coverage requirements
- Security scanning
- Performance benchmarks
- Documentation completeness

### 2. Review Processes

**Required reviews**:

- Code reviews for all changes
- Architecture reviews for significant changes
- Security reviews for security-related changes
- Documentation reviews for user-facing changes

### 3. Automated Quality Gates

**CI/CD quality gates**:

- Code quality checks
- Test coverage requirements
- Security vulnerability scans
- Performance regression tests
- Documentation validation

## Security Considerations

### 1. Submodule Security

**Security practices**:

- Regular dependency updates
- Security scanning of submodules
- Access control for submodule repositories
- Audit trails for submodule changes

### 2. Configuration Security

**Security measures**:

- Secure storage of sensitive configuration
- Encryption of secrets
- Access controls for configuration
- Audit logging of configuration changes

### 3. Deployment Security

**Security validations**:

- Security scanning of deployment artifacts
- Vulnerability assessments
- Compliance checks
- Security testing in CI/CD pipelines

## Future Considerations

### 1. Scalability

**Design for growth**:

- Modular architecture supports new vendors
- Common interfaces enable extension
- Configuration hierarchy supports complex deployments
- Testing framework scales with system complexity

### 2. Maintainability

**Long-term maintenance**:

- Clear separation of concerns
- Comprehensive documentation
- Automated testing
- Modular design enables incremental updates

### 3. Evolution

**Adapting to changes**:

- Versioned interfaces
- Migration paths
- Backward compatibility
- Deprecation processes

This architectural framework ensures that BrewNix remains maintainable, scalable, and secure as it evolves to support new vendors, technologies, and deployment scenarios.
