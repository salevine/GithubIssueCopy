# GitHub Issue Copy Script
This script is used to copy an issue from one repository to another.
The built in ability to github only allows for transferring issues between repositories

In addition, the script allows for creating a parent-child relationship between the source and destination issues.

## Usage

Make sure you have run `gh auth login` and have the correct permissions to create issues in the destination repository.


### Basic Copy
```bash
./github-issue-copy.sh 123
```

### Specify Repositories
```bash
# Custom source repository
./github-issue-copy.sh 123 -s owner/source-repo

# Custom destination repository
./github-issue-copy.sh 123 -d owner/dest-repo

# Both source and destination
./github-issue-copy.sh 123 -s owner/source-repo -d owner/dest-repo
```

### Create Relationship from destination to source
```bash
# With relationship
./github-issue-copy.sh 123 -r

# With custom repos and relationship
./github-issue-copy.sh 123 -s owner/source -d owner/dest -r
```

## Options
- `-s, --source-repo`: Specify source repository
- `-d, --dest-repo`: Specify destination repository
- `-r, --relationship`: Create parent-child issue relationship

## Prerequisites
- GitHub CLI (`gh`)
- `jq`

## Notes
- The script will prompt for the issue number if not provided as an argument.
- The script will prompt for the source and destination repositories if not provided as arguments.
- The script will prompt for the issue number if not provided as an argument.
