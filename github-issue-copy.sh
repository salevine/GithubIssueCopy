#!/bin/bash

# Default repositories
SOURCE_REPO="OWNER/REPO"
DEST_REPO="OWNER/REPO"

# Function to show usage
usage() {
    echo "Usage: $0 <issue_number> [OPTIONS]"
    echo "Options:"
    echo "  -s, --source-repo <owner/repo>   Specify source repository"
    echo "  -d, --dest-repo <owner/repo>     Specify destination repository"
    echo "  -r, --relationship              Create parent-child relationship"
    echo "Examples:"
    echo "  $0 123"
    echo "  $0 123 -s owner/repo -d owner/another-repo"
    echo "  $0 123 -r"
    exit 1
}

# Default flags
CREATE_RELATIONSHIP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source-repo)
            SOURCE_REPO="$2"
            shift 2
            ;;
        -d|--dest-repo)
            DEST_REPO="$2"
            shift 2
            ;;
        -r|--relationship)
            CREATE_RELATIONSHIP=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$ISSUE_NUMBER" ]; then
                ISSUE_NUMBER=$1
            else
                usage
            fi
            shift
            ;;
    esac
done

# Check if issue number is provided
if [ -z "$ISSUE_NUMBER" ]; then
    echo "No issue number provided. Using hardcoded repositories."
    echo "Source Repository: $SOURCE_REPO"
    echo "Destination Repository: $DEST_REPO"
    read -p "Enter the issue number: " ISSUE_NUMBER
fi

# Construct the source URL
SOURCE_URL="https://github.com/$SOURCE_REPO/issues/$ISSUE_NUMBER"

# Verify gh cli is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    echo "Please install it from: https://cli.github.com/"
    exit 1
fi

# Verify jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
    echo "Please install jq using your package manager"
    exit 1
fi

echo "Copying issue #$ISSUE_NUMBER from $SOURCE_REPO to $DEST_REPO..."

# Get full issue data including comments
issue_data=$(gh issue view $ISSUE_NUMBER -R $SOURCE_REPO --json title,body,labels,assignees,comments)

if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch issue data. Please check if:"
    echo "1. The issue number is correct"
    echo "2. You have access to the repository"
    echo "3. You are authenticated with gh cli"
    exit 1
fi

# Extract components using jq
title=$(echo "$issue_data" | jq -r .title)
body=$(echo "$issue_data" | jq -r .body)

# Handle labels
echo "Processing labels..."

# Get list of existing labels in destination repo (fetch all pages)
existing_labels=$(gh label list -R $DEST_REPO --json name --limit 1000 | jq -r '.[].name')

# Function to normalize strings by trimming whitespace and converting to lowercase
normalize() {
    echo "$1" | sed 's/^[ \t]*//;s/[ \t]*$//' | tr '[:upper:]' '[:lower:]'
}

# Create array to store labels for the new issue
label_names=()

# Process each label name from the source issue
while IFS= read -r name; do
    if [ ! -z "$name" ]; then
        # Normalize the label name
        name=$(normalize "$name")
        # Check if label exists in destination
        if ! echo "$existing_labels" | tr '[:upper:]' '[:lower:]' | grep -q "^$(normalize "$name")$"; then
            echo "Creating missing label: $name"
            # Create label with default color (using gray as fallback)
            gh label create "$name" -R $DEST_REPO --color "cccccc" >/dev/null 2>&1 || echo "Failed to create label: $name"
        else
            echo "Label already exists: $name"
        fi
        label_names+=("$name")
    fi
done < <(echo "$issue_data" | jq -r '.labels[].name')

# Format comments
comments_text=$(echo "$issue_data" | jq -r '.comments[] | "### Comment by @\(.author.login) on \(.createdAt)\n\n\(.body)\n"')

# Add reference to original issue and include comments in the body
new_body="$body

---
### Original Comments from $SOURCE_URL

$comments_text

---
*Copied from original issue: $SOURCE_URL*"

# Create new issue with extracted data
echo "Creating new issue in $DEST_REPO..."
new_issue_url=$(gh issue create -R $DEST_REPO \
    --title "$title" \
    --body "$new_body" | grep -Eo 'https://github.com/[^ ]+')

if [ $? -eq 0 ]; then
    echo "Successfully created new issue: $new_issue_url"
else
    echo "Error: Failed to create new issue"
    exit 1
fi

# Add labels to the newly created issue
for label in "${label_names[@]}"; do
    echo "Adding label: $label"
    gh issue edit "$new_issue_url" -R $DEST_REPO --add-label "$label" >/dev/null 2>&1 || echo "Failed to add label: $label"
done

if [ $? -eq 0 ]; then
    echo "Successfully added labels to the issue!"
else
    echo "Error: Failed to add some labels"
fi

# Create relationship only if flag is set
if [ "$CREATE_RELATIONSHIP" = true ]; then
    # Extract issue numbers from URLs
    SOURCE_ISSUE_NUMBER=$(echo "$SOURCE_URL" | grep -o '[0-9]*$')
    DEST_ISSUE_NUMBER=$(echo "$new_issue_url" | grep -o '[0-9]*$')

    # Get the GraphQL Node IDs for the source and destination issues
    echo "Fetching Node IDs for the source and destination issues..."
    SOURCE_NODE_ID=$(gh api graphql -F query='
      query ($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          issue(number: $number) {
            id
          }
        }
      }
    ' -F owner="$(echo $SOURCE_REPO | cut -d'/' -f1)" \
       -F repo="$(echo $SOURCE_REPO | cut -d'/' -f2)" \
       -F number="$ISSUE_NUMBER" \
       -q '.data.repository.issue.id')

    DEST_NODE_ID=$(gh api graphql -F query='
      query ($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          issue(number: $number) {
            id
          }
        }
      }
    ' -F owner="$(echo $DEST_REPO | cut -d'/' -f1)" \
       -F repo="$(echo $DEST_REPO | cut -d'/' -f2)" \
       -F number="$(echo $new_issue_url | grep -o '[0-9]*$')" \
       -q '.data.repository.issue.id')

    # Add the relationship to the relationships section
    echo "Setting parent relationship..."
    gh api graphql -f query='
      mutation {
        addSubIssue(input: {
          issueId: "'"$SOURCE_NODE_ID"'",
          subIssueId: "'"$DEST_NODE_ID"'"
        }) {
          subIssue {
            id
          }
        }
      }
    ' >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "Successfully set parent relationship between issues!"
    else
        echo "Error: Failed to set parent relationship between issues."
    fi
fi