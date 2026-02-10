# Contributing to the DevOps Lab

Thank you for your interest in contributing! This lab helps learners practice DevOps skills by fixing intentionally broken configurations.

## How to Contribute

### Adding a New Challenge

1. Create the broken configuration file(s) with realistic errors
2. Add the incident ticket description to the cloud-specific README
3. Add validation logic to `validate.sh`
4. Update the root README challenge table
5. Test the full lab flow end-to-end

### Guidelines

- **Errors should be realistic** — typos, misconfigurations, and common mistakes that engineers actually make
- **Errors should be discoverable** — running the tool should produce an error message that points toward the fix
- **No trick questions** — learners should be able to fix issues by reading docs and error messages
- **No solutions in the repo** — only symptoms, tool hints, and clear task descriptions

### Reporting Issues

Please only submit issues about the lab infrastructure, not for help completing challenges — struggling is part of learning!

## Development

### Testing Changes

Use the automated validation in `.github/skills/validate-devops-lab/` to test the full lab flow:

```bash
cd .github/skills/validate-devops-lab/azure/scripts
chmod +x *.sh
./run-full-validation.sh
```

## Code of Conduct

Be kind, be helpful, and remember we're all here to learn.
