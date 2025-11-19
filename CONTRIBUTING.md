# Contributing Guide

Thank you for considering contributing to AgentBox! This document will help you understand how to participate in the project.

## 📋 Code of Conduct

### Our Pledge

To foster an open and welcoming environment, we pledge to:

- Use welcoming and inclusive language
- Respect differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

## 🤝 How to Contribute

### Reporting Bugs

Before submitting a bug report, please search existing [Issues](https://github.com/Gravtice/AgentBox/issues) to confirm the problem hasn't been reported yet.

**A good bug report should include:**

1. **Clear title** - Brief description of the issue
2. **Steps to reproduce** - Detailed step-by-step instructions
3. **Expected behavior** - What you expected to happen
4. **Actual behavior** - What actually happened
5. **Environment information** - OS, Docker version, etc.
6. **Logs and screenshots** - Relevant error logs or screenshots

**Example:**

```markdown
## Bug Description
Permission error when starting container

## Steps to Reproduce
1. Run `./gbox claude`
2. Container starts
3. Error message appears: "Permission denied: /.claude.json"

## Environment Information
- OS: macOS 14.1
- Docker: 24.0.6
- AgentBox: v1.0.0

## Error Logs
```
Error: EACCES: permission denied, open '/.claude.json'
```
```

### Suggesting Features

We welcome new feature suggestions!

**A good feature suggestion should include:**

1. **Feature description** - Clear description of the proposed feature
2. **Use case** - Why this feature is needed
3. **Expected outcome** - How it would be implemented and used
4. **Alternatives** - Whether other solutions were considered

**Example:**

```markdown
## Feature Suggestion
Support for Docker Compose projects

## Use Case
Many projects use docker-compose.yml to define multiple services. Would like gbox to automatically detect and start these services.

## Expected Outcome
- Automatically detect docker-compose.yml
- Start all defined services
- Support inter-service network communication

## Alternatives
Manually start docker-compose, but integration would be more convenient
```

### Submitting Pull Requests

#### Preparation

1. **Fork the repository**
   ```bash
   # Fork the repository on GitHub
   # Then clone your fork
   git clone https://github.com/YOUR_USERNAME/AgentBox.git
   cd AgentBox
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```

3. **Configure upstream repository**
   ```bash
   git remote add upstream https://github.com/Gravtice/AgentBox.git
   ```

#### Development Workflow

1. **Stay synchronized**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Write code**
   - Follow project code style
   - Add necessary comments
   - Keep code clean and concise

3. **Test**
   ```bash
   # Test basic functionality
   ./gbox claude

   # Test modified functionality
   # ... Test according to specific changes

   # Syntax check
   bash -n gbox
   bash -n lib/*.sh
   ```

4. **Commit changes**
   ```bash
   git add .
   git commit -m "feat: add amazing feature"
   ```

#### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type categories:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation update
- `style` - Code formatting (doesn't affect functionality)
- `refactor` - Code refactoring (not a feature or fix)
- `perf` - Performance improvement
- `test` - Testing related
- `chore` - Build/tooling related

**Example:**

```
feat(oauth): add automatic OAuth account switching

Add functionality to automatically switch to other available accounts
when current account reaches usage limits.

- Scan all available accounts
- Check current account status
- Automatically switch to available account
- Update .claude.json config

Closes #123
```

#### Creating a Pull Request

1. **Push branch**
   ```bash
   git push origin feature/amazing-feature
   ```

2. **Create PR**
   - Visit the GitHub repository
   - Click "New Pull Request"
   - Select your branch
   - Fill in PR description

**PR description template:**

```markdown
## Summary of Changes
Brief description of the purpose and content of this PR

## Change Type
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Code refactoring
- [ ] Performance optimization

## Testing
Describe how to test these changes

## Related Issues
Closes #123

## Screenshots (if applicable)
Add relevant screenshots

## Checklist
- [ ] Code follows project style
- [ ] Added necessary comments
- [ ] Updated relevant documentation
- [ ] Completed local testing
- [ ] Commit messages follow conventions
```

## 💻 Development Guide

### Project Structure

```
AgentBox/
├── gbox                 # Main entry script
├── lib/                 # Modular libraries
│   ├── common.sh        # Common utilities
│   ├── container.sh     # Container management
│   ├── agent.sh         # Agent sessions
│   └── ...
├── docs/                # Documentation
├── Dockerfile           # Image build
└── README.md            # Project description
```

### Code Style

#### Shell Scripts

```bash
# ✅ Good style
function my_function() {
    local param1="$1"
    local param2="$2"

    if [[ -z "$param1" ]]; then
        error "Parameter cannot be empty"
        return 1
    fi

    echo "Processing: $param1"
    return 0
}

# ❌ Bad style
my_function() {
a=$1
if [ -z "$a" ]
then
echo "error"
fi
}
```

**Standards:**
- Use 4-space indentation
- Use `function name()` format
- Variables: lowercase_with_underscores
- Constants: UPPERCASE_WITH_UNDERSCORES
- Use `[[ ]]` instead of `[ ]`
- Quote all string variables
- Add necessary comments

#### Documentation

```markdown
# ✅ Good documentation
## Feature Description

Clear and concise description

### Usage Example

\`\`\`bash
./gbox claude
\`\`\`

### Parameter Description

- `--memory` - Memory limit (default: 4g)

# ❌ Bad documentation
Feature xxx

Usage: xxx
```

### Testing

#### Manual Testing Checklist

When adding new features, ensure you test:

- [ ] Basic functionality works
- [ ] Error handling is correct
- [ ] Log output is clear
- [ ] Doesn't affect existing functionality
- [ ] Documentation is updated

#### Test Scripts

```bash
# Test basic commands
./gbox help
./gbox list
./gbox status

# Test agent startup
./gbox claude
./gbox happy claude
./gbox codex

# Test container management
./gbox stop <container>
./gbox logs <container>
./gbox shell <container>

# Test OAuth management
./gbox oauth claude status
./gbox oauth claude list
```

## 📚 Development Resources

### Documentation
- [Quick Start](./QUICKSTART.md)
- [Architecture Design](./docs/ARCHITECTURE.md)

### Tools
- [shellcheck](https://www.shellcheck.net/) - Shell script linting
- [shfmt](https://github.com/mvdan/sh) - Shell script formatting

### Learning Resources
- [Bash Programming Guide](https://tldp.org/LDP/abs/html/)
- [Docker Documentation](https://docs.docker.com/)
- [Conventional Commits](https://www.conventionalcommits.org/)

## 🎓 Best Practices

### 1. Small Commits

Each commit should:
- Do one thing only
- Be independently reviewable
- Pass all tests
- Include clear commit message

### 2. Documentation First

When adding new features:
1. Update documentation first
2. Then implement the feature
3. Ensure documentation and code are consistent

### 3. Backward Compatibility

Unless it's a major version update:
- Don't break existing APIs
- Don't remove existing functionality
- Maintain compatibility when adding features

### 4. Code Review

After submitting a PR:
- Respond to review comments
- Update code promptly
- Stay polite and friendly

## 🆘 Getting Help

Running into issues?

1. **Check documentation** - [README](./README.md), [QUICKSTART](./QUICKSTART.md)
2. **Search Issues** - There may already be relevant discussions
3. **Ask questions** - Ask in [Discussions](https://github.com/Gravtice/AgentBox/discussions)
4. **Report bugs** - Create a new [Issue](https://github.com/Gravtice/AgentBox/issues)

## 📮 Contact

- **GitHub Issues**: [Submit issues](https://github.com/Gravtice/AgentBox/issues)
- **GitHub Discussions**: [Join discussions](https://github.com/Gravtice/AgentBox/discussions)

## 🙏 Acknowledgments

Thank you to all contributors for your efforts!

Your contributions will be listed in:
- [CHANGELOG.md](./CHANGELOG.md)
- GitHub Contributors

---

**Thank you again for your contributions!** ❤️
