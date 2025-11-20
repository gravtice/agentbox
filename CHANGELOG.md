# Changelog

This document records all important changes to AgentBox.

Format based on [Keep a Changelog](https://keepachangelog.com/),
Version numbering follows [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2025-01-17

### Added
- Support for independent device IDs across multiple containers with shared login state (#80a454b)
- Happy CLI updated to automatic hostname detection version (#5a1bb6b)

### Removed
- Removed shim API and API mode functionality (#18d05fc)
- Removed gbox extend feature to simplify tool design (#f74b84b)

### Documentation
- Complete alignment with actual happy-cli code (#96e473d)
- Corrected permission fix solution to actual implementation (#7bd64b3)
- Simplified documentation, preserving final solutions (#c77735b)

## [1.0.0] - 2025-01-15

### Added

#### Core Features
- Working directory-driven automatic container management
- Multi-AI Agent support for Claude Code, Codex, and Gemini
- Happy remote collaboration mode
- OAuth multi-account management and automatic switching
- Complete Git Worktree support

#### Resource Configuration
- Memory and CPU limit configuration
- Flexible port mapping (#6c54546, #14ddec9)
- Read-only reference directory mounting (#6c54546)
- Proxy configuration support (#5e5b03c)

#### Development Tools
- Zsh auto-completion plugin (#20382f7)
- OAuth account status viewing and switching
- Keepalive automatic login session maintenance
- Container logging and debugging

### Optimized

#### Performance
- Dependency cache sharing (pip, npm, uv)
- Multi-stage Docker image building
- Automatic Git submodule management

#### User Experience
- One-click startup with automatic container creation/connection
- Automatic container cleanup on exit
- Direct configuration file editing on host machine
- Intelligent container naming

### Technical Implementation
- Refactored from single 3546-line file to modular architecture (#REFACTORING_COMPLETE.md)
- Git submodule management for happy-cli (#d56ab75)
- Environment variable-driven automatic permission bypass (#9be1182, #b3cdd1f)
- Docker network isolation

### Documentation
- Complete user documentation and quick start guide
- Architecture design documentation
- Developer documentation and contribution guidelines
- Zsh completion maintenance documentation (#b346513)

### Fixed
- Fixed git submodule recursive update issue (#4ac3281)
- Fixed reference directory mounting security issue (#4038841)
- Fixed parameter passing to internal agent issue (#14ddec9)

## [Unreleased]

### Planned
- Pre-built image release to Docker Hub
- GitHub Actions CI/CD
- Additional AI Agent support
- Web UI management interface

---

## Version Notes

### [Major Version] - Major Changes
- Breaking changes
- Architecture restructuring

### [Minor Version] - Feature Updates
- New features
- Feature enhancements

### [Patch Version] - Bug Fixes
- Bug fixes
- Documentation updates
- Performance improvements

## Contributing

Issues and Pull Requests are welcome!

See [Contributing Guide](./CONTRIBUTING.md) to learn how to participate in the project.
