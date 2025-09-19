#!/bin/bash

# transition-season.sh
# Transition from current season to next season
# Usage: ./scripts/transition-season.sh [--dry-run] [--force]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Global flags
DRY_RUN=false
FORCE_TRANSITION=false
BACKUP_CREATED=false

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

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_dry_run() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $1"
    fi
}

# Function to execute command with dry-run support
execute_command() {
    local command="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        print_dry_run "$description: $command"
    else
        print_status "$description"
        eval "$command"
    fi
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
    git show-ref --verify --quiet refs/heads/"$1" 2>/dev/null
}

# Function to check if remote branch exists
remote_branch_exists() {
    git ls-remote --heads origin "$1" | grep -q "$1" 2>/dev/null
}

# Function to get current season info from git config
get_season_info() {
    CURRENT_YEAR=$(git config --get seasonal.current-year 2>/dev/null || echo "")
    NEXT_YEAR=$(git config --get seasonal.next-year 2>/dev/null || echo "")
    
    if [[ -z "$CURRENT_YEAR" || -z "$NEXT_YEAR" ]]; then
        print_error "Seasonal configuration not found. Please run init-seasonal-gitflow.sh first."
        exit 1
    fi
    
    NEW_NEXT_YEAR=$((NEXT_YEAR + 1))
    
    print_status "Season transition: $CURRENT_YEAR (current) → $NEXT_YEAR (new current) → $NEW_NEXT_YEAR (new next)"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_step "Validating prerequisites..."
    
    # Check if required branches exist
    local required_branches=("main" "develop" "season/next")
    for branch in "${required_branches[@]}"; do
        if ! branch_exists "$branch"; then
            print_error "Required branch '$branch' does not exist. Please run init-seasonal-gitflow.sh first."
            exit 1
        fi
    done
    
    # Check for uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        if [ "$FORCE_TRANSITION" = false ]; then
            print_error "You have uncommitted changes. Please commit or stash them before transitioning."
            print_status "Use --force to ignore this check (not recommended)."
            exit 1
        else
            print_warning "Proceeding with uncommitted changes due to --force flag."
        fi
    fi
    
    # Check if we're on a safe branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "main" && "$current_branch" != "develop" ]]; then
        print_warning "Currently on branch '$current_branch'. Consider switching to main or develop."
        if [ "$FORCE_TRANSITION" = false ]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    print_success "Prerequisites validated"
}

# Function to create backup
create_backup() {
    print_step "Creating backup..."
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_tag="backup/pre-transition-${timestamp}"
    
    execute_command "git tag -a '$backup_tag' -m 'Backup before season transition from $CURRENT_YEAR to $NEXT_YEAR'" \
                   "Creating backup tag"
    
    if [ "$DRY_RUN" = false ]; then
        BACKUP_CREATED=true
        print_success "Backup created with tag: $backup_tag"
    fi
}

# Function to sync with remote
sync_with_remote() {
    print_step "Syncing with remote repository..."
    
    if git remote | grep -q origin; then
        execute_command "git fetch origin" "Fetching latest changes from origin"
        
        # Update local branches from remote
        local branches=("main" "develop" "season/next")
        for branch in "${branches[@]}"; do
            if remote_branch_exists "$branch"; then
                execute_command "git checkout $branch && git pull origin $branch" \
                               "Updating $branch from origin"
            fi
        done
    else
        print_warning "No remote 'origin' found. Skipping remote sync."
    fi
}

# Function to finalize current season
finalize_current_season() {
    print_step "Finalizing current season ($CURRENT_YEAR)..."
    
    # Ensure main and develop are in sync
    execute_command "git checkout main" "Switching to main branch"
    execute_command "git merge develop --no-ff -m 'Final merge of develop into main for season $CURRENT_YEAR'" \
                   "Final merge of develop into main"
    
    # Create final season tag
    local final_tag="v${CURRENT_YEAR}.final"
    if ! git tag | grep -q "$final_tag"; then
        execute_command "git tag -a '$final_tag' -m 'Final release for season $CURRENT_YEAR'" \
                       "Creating final season tag"
    fi
    
    print_success "Current season ($CURRENT_YEAR) finalized"
}

# Function to archive current season
archive_current_season() {
    print_step "Archiving current season ($CURRENT_YEAR)..."
    
    local archive_branch="season/previous-${CURRENT_YEAR}"
    
    # Create archive branch from current main
    if ! branch_exists "$archive_branch"; then
        execute_command "git checkout main && git checkout -b '$archive_branch'" \
                       "Creating archive branch for $CURRENT_YEAR"
        
        execute_command "git tag -a 'archive/$CURRENT_YEAR' -m 'Archived season $CURRENT_YEAR'" \
                       "Creating archive tag"
    else
        print_warning "Archive branch '$archive_branch' already exists, skipping creation"
    fi
    
    print_success "Season $CURRENT_YEAR archived to branch: $archive_branch"
}

# Function to promote next season to current
promote_next_season() {
    print_step "Promoting next season ($NEXT_YEAR) to current..."
    
    # Update main with season/next
    execute_command "git checkout main" "Switching to main branch"
    execute_command "git reset --hard season/next" "Promoting season/next to main"
    
    # Sync develop with main
    execute_command "git checkout develop" "Switching to develop branch"
    execute_command "git reset --hard main" "Sync develop with main"
    
    # Create season start tag
    local start_tag="v${NEXT_YEAR}.0"
    if ! git tag | grep -q "$start_tag"; then
        execute_command "git checkout main && git tag -a '$start_tag' -m 'Season $NEXT_YEAR begins'" \
                       "Creating season start tag"
    fi
    
    print_success "Season $NEXT_YEAR promoted to current"
}

# Function to create new next season
create_new_next_season() {
    print_step "Creating new next season ($NEW_NEXT_YEAR)..."
    
    # Reset season/next to current main
    execute_command "git checkout season/next && git reset --hard main" \
                   "Resetting season/next for new season $NEW_NEXT_YEAR"
    
    # Create initial tag for new next season
    local next_init_tag="v${NEW_NEXT_YEAR}.init"
    execute_command "git checkout season/next && git tag -a '$next_init_tag' -m 'Initialize season $NEW_NEXT_YEAR development'" \
                   "Creating initialization tag for new next season"
    
    print_success "New next season ($NEW_NEXT_YEAR) initialized"
}

# Function to update git configuration
update_git_config() {
    print_step "Updating git configuration..."
    
    execute_command "git config seasonal.current-year $NEXT_YEAR" \
                   "Updating current year to $NEXT_YEAR"
    execute_command "git config seasonal.next-year $NEW_NEXT_YEAR" \
                   "Updating next year to $NEW_NEXT_YEAR"
    
    print_success "Git configuration updated"
}

# Function to push changes to remote
push_to_remote() {
    print_step "Pushing changes to remote..."
    
    if git remote | grep -q origin && [ "$DRY_RUN" = false ]; then
        print_status "Pushing all branches and tags to origin..."
        
        # Push main branches
        git push origin main 2>/dev/null || print_warning "Could not push main"
        git push origin develop 2>/dev/null || print_warning "Could not push develop"
        git push origin season/next 2>/dev/null || print_warning "Could not push season/next"
        
        # Push archive branch
        git push origin "season/previous-${CURRENT_YEAR}" 2>/dev/null || print_warning "Could not push archive branch"
        
        # Push all tags
        git push --tags 2>/dev/null || print_warning "Could not push tags"
        
        print_success "Changes pushed to origin"
    elif [ "$DRY_RUN" = true ]; then
        print_dry_run "Push all branches and tags to origin"
    else
        print_warning "No remote 'origin' found. Skipping push to remote."
    fi
}

# Function to clean up merged branches
cleanup_branches() {
    print_step "Cleaning up merged branches..."
    
    if [ "$DRY_RUN" = false ]; then
        # Clean up merged feature branches
        print_status "Cleaning up merged feature branches..."
        git branch --merged develop | grep "feature/" | head -10 | xargs -r git branch -d 2>/dev/null || true
        git branch --merged season/next | grep "feature/next/" | head -10 | xargs -r git branch -d 2>/dev/null || true
        
        # Clean up merged release branches
        print_status "Cleaning up merged release branches..."
        git branch --merged main | grep "release/" | head -5 | xargs -r git branch -d 2>/dev/null || true
        git branch --merged season/next | grep "release/next/" | head -5 | xargs -r git branch -d 2>/dev/null || true
        
        print_success "Branch cleanup completed"
    else
        print_dry_run "Clean up merged feature and release branches"
    fi
}

# Function to generate transition report
generate_report() {
    print_step "Generating transition report..."
    
    local report_file="transition-report-$(date +%Y%m%d_%H%M%S).md"
    
    if [ "$DRY_RUN" = false ]; then
        cat > "$report_file" << EOF
# Season Transition Report

**Date:** $(date)
**Previous Current Season:** $CURRENT_YEAR
**New Current Season:** $NEXT_YEAR
**New Next Season:** $NEW_NEXT_YEAR

## Actions Performed

1. ✅ Validated prerequisites
2. ✅ Created backup tags
3. ✅ Synchronized with remote repository
4. ✅ Finalized current season ($CURRENT_YEAR)
5. ✅ Archived season $CURRENT_YEAR to \`season/previous-$CURRENT_YEAR\`
6. ✅ Promoted season $NEXT_YEAR to current
7. ✅ Initialized new next season ($NEW_NEXT_YEAR)
8. ✅ Updated git configuration
9. ✅ Pushed changes to remote
10. ✅ Cleaned up merged branches

## Branch Status After Transition

- \`main\`: Now contains season $NEXT_YEAR
- \`develop\`: Now contains season $NEXT_YEAR development
- \`season/next\`: Now prepared for season $NEW_NEXT_YEAR
- \`season/previous-$CURRENT_YEAR\`: Archive of season $CURRENT_YEAR

## Tags Created

- \`v${CURRENT_YEAR}.final\`: Final release of season $CURRENT_YEAR
- \`archive/$CURRENT_YEAR\`: Archive marker for season $CURRENT_YEAR
- \`v${NEXT_YEAR}.0\`: Initial release of season $NEXT_YEAR
- \`v${NEW_NEXT_YEAR}.init\`: Initialize development for season $NEW_NEXT_YEAR

## Next Steps

1. Update CI/CD pipelines for new season configuration
2. Notify team members about the season transition
3. Update project documentation and README
4. Begin development for season $NEXT_YEAR features
5. Plan roadmap for season $NEW_NEXT_YEAR

## Rollback Information

If rollback is needed, use the backup tag created before transition:
\`\`\`bash
git checkout backup/pre-transition-[timestamp]
\`\`\`
EOF
        
        print_success "Transition report generated: $report_file"
    else
        print_dry_run "Generate transition report: $report_file"
    fi
}

# Function to show help
show_help() {
    cat << EOF
Season Transition Script

Usage: $0 [OPTIONS]

This script transitions from the current season to the next season in a
seasonal GitFlow branching strategy.

OPTIONS:
    --dry-run       Show what would be done without making changes
    --force         Force transition even with uncommitted changes
    -h, --help      Show this help message

PROCESS:
1. Validate prerequisites and create backup
2. Sync with remote repository
3. Finalize current season with tags
4. Archive current season to season/previous-YEAR
5. Promote next season to current (main/develop)
6. Initialize new next season branch
7. Update git configuration
8. Push changes to remote
9. Clean up merged branches
10. Generate transition report

EXAMPLES:
    $0                    # Normal transition
    $0 --dry-run          # Preview what would happen
    $0 --force            # Force transition with uncommitted changes

PREREQUISITES:
- Must be in a git repository with seasonal GitFlow initialized
- All important changes should be committed
- Internet connection for remote operations (optional)

EOF
}

# Function to confirm transition
confirm_transition() {
    if [ "$FORCE_TRANSITION" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo
    print_warning "⚠️  SEASON TRANSITION CONFIRMATION ⚠️"
    echo
    echo "You are about to transition from season $CURRENT_YEAR to season $NEXT_YEAR"
    echo
    echo "This will:"
    echo "  • Archive current season ($CURRENT_YEAR) to season/previous-$CURRENT_YEAR"
    echo "  • Promote next season ($NEXT_YEAR) to main production"
    echo "  • Initialize new next season ($NEW_NEXT_YEAR)"
    echo "  • Update all branch configurations"
    echo
    print_warning "This action cannot be easily undone!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    if [[ "$REPLY" != "yes" ]]; then
        print_status "Season transition cancelled."
        exit 0
    fi
}

# Main transition function
main() {
    print_status "Starting seasonal transition process..."
    
    check_git_repo
    get_season_info
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi
    
    confirm_transition
    validate_prerequisites
    create_backup
    sync_with_remote
    finalize_current_season
    archive_current_season
    promote_next_season
    create_new_next_season
    update_git_config
    push_to_remote
    cleanup_branches
    generate_report
    
    echo
    print_success "🎉 Season transition completed successfully! 🎉"
    echo
    print_status "Summary:"
    echo "  ├── Previous season: $CURRENT_YEAR (archived in season/previous-$CURRENT_YEAR)"
    echo "  ├── Current season: $NEXT_YEAR (now in main/develop)"
    echo "  └── Next season: $NEW_NEXT_YEAR (initialized in season/next)"
    echo
    print_status "Current branch status:"
    git branch -a | grep -E "(main|develop)" | sed 's/^/  /'
    echo
    print_status "Recent tags:"
    git tag --sort=-version:refname | head -5 | sed 's/^/  /'
    echo
    if [ "$BACKUP_CREATED" = true ]; then
        print_status "💾 Backup created - you can rollback if needed using the backup tag"
    fi
    echo
    print_status "Next steps:"
    echo "  1. Review the transition report generated"
    echo "  2. Update your CI/CD configuration for new season"
    echo "  3. Notify team members about the transition"
    echo "  4. Start planning features for season $NEXT_YEAR"
    echo "  5. Begin roadmap for season $NEW_NEXT_YEAR"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ "$BACKUP_CREATED" = true ]; then
        print_error "Transition failed! You can restore using the backup tag created earlier."
        print_status "Check 'git tag | grep backup' to find the backup tag."
    fi
    exit $exit_code
}

# Set up error handling
trap cleanup_on_error ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_TRANSITION=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi