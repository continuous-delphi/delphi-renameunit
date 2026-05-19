@echo off
git config core.hooksPath tools/hooks
echo Hooks configured. Pre-commit hook will auto-increment version on each commit.
