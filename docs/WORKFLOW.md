# Seasonal GitFlow Workflow

## Overview
This project uses a seasonal branching strategy based on GitFlow principles.

## Current Season (2026)
- **main**: Production-ready code for current season
- **develop**: Integration branch for current season development
- **feature/**: Feature branches for current season
- **release/**: Release branches for current season
- **hotfix/**: Hotfix branches for current season

## Next Season (2027)
- **main/next**: Production-ready code for next season
- **develop/next**: Integration branch for next season development
- **feature/next/**: Feature branches for next season
- **release/next/**: Release branches for next season
- **hotfix/next/**: Hotfix branches for next season

## Common Commands

### Current Season Feature
```bash
git checkout develop
git checkout -b feature/my-feature
# ... development work ...
git checkout develop
git merge --no-ff feature/my-feature
```

### Next Season Feature
```bash
git checkout develop/next
git checkout -b feature/next/my-feature
# ... development work ...
git checkout develop/next
git merge --no-ff feature/next/my-feature
```

### Release (Current Season)
```bash
git checkout develop
git checkout -b release/1.0.0
# ... release preparation ...
git checkout main
git merge --no-ff release/1.0.0
git tag -a v1.0.0 -m "Release 1.0.0"
git checkout develop
git merge --no-ff release/1.0.0
```

### Hotfix (Current Season)
```bash
git checkout main
git checkout -b hotfix/critical-fix
# ... fix implementation ...
git checkout main
git merge --no-ff hotfix/critical-fix
git tag -a v1.0.1 -m "Hotfix 1.0.1"
git checkout develop
git merge --no-ff hotfix/critical-fix
```

### Cross-Season Sync
```bash
# Current to Next
git checkout main
git checkout -b sync/current-to-next-feature
git cherry-pick <commit-hash>
git checkout main/next
git merge --no-ff sync/current-to-next-feature

# Next to Current (via hotfix)
git checkout main/next
git checkout -b sync/next-to-current-improvement
git cherry-pick <commit-hash>
git checkout main
git checkout -b hotfix/backport-improvement
git merge sync/next-to-current-improvement
git checkout main
git merge --no-ff hotfix/backport-improvement
```

## Season Transition
Use the transition script: `./scripts/transition-season.sh`
