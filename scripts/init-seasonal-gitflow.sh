#!/bin/bash

# init-seasonal-gitflow.sh
# Initialize seasonal GitFlow branching strategy
# Usage: ./scripts/init-seasonal-gitflow.sh [current_year] [next_year]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository. Please run this script from the root of your git repository."
        exit 1
    fi
}

# Function to check if branch exists
branch_exists() {
    git show-ref --verify --quiet refs/heads/"$1"
}

# Function to create branch if it doesn't exist
create_branch() {
    local branch_name="$1"
    local source_branch="${2:-main}"
    
    if branch_exists "$branch_name"; then
        print_warning "Branch '$branch_name' already exists, skipping creation"
    else
        git checkout "$source_branch"
        git checkout -b "$branch_name"
        print_success "Created branch '$branch_name' from '$source_branch'"
    fi
}

# Function to set up branch protection rules (GitHub CLI required)
setup_protection_rules() {
    if command -v gh > /dev/null 2>&1; then
        print_status "Setting up branch protection rules..."
        
        # Main branch protection
        gh api repos/:owner/:repo/branches/main/protection \
            --method PUT \
            --field required_status_checks='{"strict":true,"contexts":[]}' \
            --field enforce_admins=true \
            --field required_pull_request_reviews='{"required_approving_review_count":2,"dismiss_stale_reviews":true}' \
            --field restrictions=null \
            2>/dev/null || print_warning "Could not set protection for main branch"
        
        # Season/next branch protection
        if branch_exists "season/next"; then
            gh api repos/:owner/:repo/branches/season/next/protection \
                --method PUT \
                --field required_status_checks='{"strict":true,"contexts":[]}' \
                --field enforce_admins=true \
                --field required_pull_request_reviews='{"required_approving_review_count":2,"dismiss_stale_reviews":true}' \
                --field restrictions=null \
                2>/dev/null || print_warning "Could not set protection for season/next branch"
        fi
        
        print_success "Branch protection rules configured"
    else
        print_warning "GitHub CLI (gh) not found. Branch protection rules not set. Please configure manually."
    fi
}

# Main initialization function
init_seasonal_gitflow() {
    local current_year="${1:-$(date +%Y)}"
    local next_year="${2:-$((current_year + 1))}"
    
    print_status "Initializing Seasonal GitFlow for years $current_year (current) and $next_year (next)"
    
    # Check if we're in a git repository
    check_git_repo
    
    # Ensure we're on main branch and it exists
    if ! branch_exists "main"; then
        print_status "Creating main branch..."
        git checkout -b main
    else
        git checkout main
        git pull origin main 2>/dev/null || print_warning "Could not pull from origin/main"
    fi
    
    # Create develop branch for current season
    create_branch "develop" "main"
    
    # Create season/next branch for next season
    create_branch "season/next" "main"
    
    # Create initial tags
    print_status "Creating initial version tags..."
    if ! git tag | grep -q "v${current_year}.0"; then
        git tag -a "v${current_year}.0" -m "Initial release for season $current_year"
        print_success "Created tag v${current_year}.0"
    fi
    
    # Set up git config for seasonal workflow
    print_status "Configuring git settings for seasonal workflow..."
    git config gitflow.branch.main main
    git config gitflow.branch.develop develop
    git config gitflow.prefix.feature feature/
    git config gitflow.prefix.release release/
    git config gitflow.prefix.hotfix hotfix/
    git config gitflow.prefix.bugfix bugfix/
    git config gitflow.prefix.versiontag v
    
    # Configure next season prefixes
    git config seasonal.branch.season.next season/next
    git config seasonal.prefix.feature.next feature/next/
    git config seasonal.prefix.release.next release/next/
    git config seasonal.prefix.bugfix.next bugfix/next/
    git config seasonal.current-year "$current_year"
    git config seasonal.next-year "$next_year"
    
    print_success "Git configuration updated for seasonal workflow"
    
    # Create sample workflow documentation
    create_workflow_docs "$current_year" "$next_year"
    
    # Set up branch protection if GitHub CLI is available
    setup_protection_rules
    
    # Push all branches to origin if remote exists
    if git remote | grep -q origin; then
        print_status "Pushing branches to origin..."
        git push -u origin main 2>/dev/null || print_warning "Could not push main to origin"
        git push -u origin develop 2>/dev/null || print_warning "Could not push develop to origin"
        git push -u origin season/next 2>/dev/null || print_warning "Could not push season/next to origin"
        git push --tags 2>/dev/null || print_warning "Could not push tags to origin"
        print_success "Branches pushed to origin"
    fi
    
    print_success "Seasonal GitFlow initialization complete!"
    echo
    print_status "Branch structure created:"
    echo "  ├── main (current season $current_year - production)"
    echo "  ├── develop (current season $current_year - development)"
    echo "  ├── season/next (next season $next_year - development)"
    echo
    print_status "Next steps:"
    echo "  1. Start current season feature: git checkout develop && git checkout -b feature/your-feature"
    echo "  2. Start next season feature: git checkout season/next && git checkout -b feature/next/your-feature"
    echo "  3. Create releases: git checkout -b release/1.0.0 develop"
    echo "  4. Create next season releases: git checkout -b release/next/2.0.0 season/next"
}

# Function to create workflow documentation
create_workflow_docs() {
    local current_year="$1"
    local next_year="$2"
    
    if [ ! -f docs/WORKFLOW.md ]; then
        mkdir -p docs
        cat > docs/WORKFLOW.md << EOF
# Seasonal GitFlow Workflow

## Overview
This project uses a seasonal branching strategy based on GitFlow principles.

## Current Season ($current_year)
- **main**: Production-ready code for current season
- **develop**: Integration branch for current season development
- **feature/**: Feature branches for current season
- **release/**: Release branches for current season
- **hotfix/**: Hotfix branches for current season
- **bugfix/**: Bugfix branches for current season

## Next Season ($next_year)
- **season/next**: Integration branch for next season development
- **feature/next/**: Feature branches for next season
- **release/next/**: Release branches for next season
- **bugfix/next/**: Bugfix branches for next season

## Common Commands

### Current Season Feature
\`\`\`bash
git checkout develop
git checkout -b feature/my-feature
# ... development work ...
git checkout develop
git merge --no-ff feature/my-feature
\`\`\`

### Next Season Feature
\`\`\`bash
git checkout season/next
git checkout -b feature/next/my-feature
# ... development work ...
git checkout season/next
git merge --no-ff feature/next/my-feature
\`\`\`

### Release (Current Season)
\`\`\`bash
git checkout develop
git checkout -b release/1.0.0
# ... release preparation ...
git checkout main
git merge --no-ff release/1.0.0
git tag -a v1.0.0 -m "Release 1.0.0"
git checkout develop
git merge --no-ff release/1.0.0
\`\`\`

### Hotfix (Current Season)
\`\`\`bash
git checkout main
git checkout -b hotfix/critical-fix
# ... fix implementation ...
git checkout main
git merge --no-ff hotfix/critical-fix
git tag -a v1.0.1 -m "Hotfix 1.0.1"
git checkout develop
git merge --no-ff hotfix/critical-fix
\`\`\`

### Cross-Season Sync
\`\`\`bash
# Current to Next
git checkout main
git checkout -b sync/current-to-next-feature
git cherry-pick <commit-hash>
git checkout season/next
git merge --no-ff sync/current-to-next-feature

# Next to Current (via hotfix)
git checkout season/next
git checkout -b sync/next-to-current-improvement
git cherry-pick <commit-hash>
git checkout main
git checkout -b hotfix/backport-improvement
git merge sync/next-to-current-improvement
git checkout main
git merge --no-ff hotfix/backport-improvement
\`\`\`

## Season Transition
Use the transition script: \`./transition-season.sh\`
EOF
        git add docs/WORKFLOW.md
        git commit -m "docs: add seasonal workflow documentation"
        print_success "Created workflow documentation in docs/WORKFLOW.md"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    CURRENT_YEAR="${1}"
    NEXT_YEAR="${2}"
    
    # Show usage if help is requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: $0 [current_year] [next_year]"
        echo
        echo "Initialize seasonal GitFlow branching strategy"
        echo
        echo "Arguments:"
        echo "  current_year    Current season year (default: current year)"
        echo "  next_year       Next season year (default: current_year + 1)"
        echo
        echo "Examples:"
        echo "  $0                    # Use current year and next year"
        echo "  $0 2024 2025          # Explicitly set years"
        echo
        exit 0
    fi
    
    # Run initialization
    init_seasonal_gitflow "$CURRENT_YEAR" "$NEXT_YEAR"
fi