# Restic Repository Setup Guide

This guide will help you set up a restic repository and configure the backup script.

## Prerequisites

- restic installed on your system
- Access to a location for storing backups (local disk, remote server, cloud storage)

## Step 1: Install Restic

### Linux (Debian/Ubuntu)
```bash
sudo apt update
sudo apt install restic
```

### Linux (via binary download)
```bash
wget https://github.com/restic/restic/releases/latest/download/restic_*_linux_amd64.bz2
bunzip2 restic_*_linux_amd64.bz2
chmod +x restic_*_linux_amd64
sudo mv restic_*_linux_amd64 /usr/local/bin/restic
```

### Verify installation
```bash
restic version
```

## Step 2: Choose Repository Location

Restic supports multiple backend types:

### Local Directory
```bash
REPO_PATH="/backup/restic-repo"
```

### SFTP (SSH/Remote Server)
```bash
REPO_PATH="sftp:user@hostname:/path/to/repo"
```

### Amazon S3
```bash
REPO_PATH="s3:s3.amazonaws.com/bucket-name"
# Requires: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
```

### Backblaze B2
```bash
REPO_PATH="b2:bucket-name:path/to/repo"
# Requires: B2_ACCOUNT_ID and B2_ACCOUNT_KEY environment variables
```

### Other backends
- Azure Blob Storage: `azure:container-name:/path`
- Google Cloud Storage: `gs:bucket-name:/path`
- REST Server: `rest:http://hostname:8000/`
- rclone: `rclone:remote:path`

## Step 3: Create Configuration Directories

Set up secure directories for configuration and secrets:

```bash
# Create .restic directory for config files
mkdir -p ~/.restic
chmod 700 ~/.restic

# Create .secrets directory for password file
mkdir -p ~/.secrets
chmod 700 ~/.secrets
```

These restrictive permissions ensure only you can access the configuration and password files.

## Step 4: Initialize Repository

Create a strong password for your repository:

```bash
# Generate a secure password
openssl rand -base64 32

# Save it securely in .secrets directory
echo "your-generated-password" > ~/.secrets/restic-password
chmod 600 ~/.secrets/restic-password
```

Initialize the repository:

```bash
# For local repository
export RESTIC_REPOSITORY="/backup/restic-repo"
export RESTIC_PASSWORD_FILE="$HOME/.secrets/restic-password"

# Create directory if local
mkdir -p "$RESTIC_REPOSITORY"

# Initialize
restic init
```

Expected output:
```
created restic repository a1b2c3d4 at /backup/restic-repo
Please note that knowledge of your password is required to access the repository.
Losing your password means that your data is irrecoverably lost.
```

## Step 5: Configure the Backup Script

Copy the example configuration to your .restic directory:

```bash
cd /path/to/restic-backup
cp restic-backup.conf.example ~/.restic/restic-backup.conf
chmod 600 ~/.restic/restic-backup.conf
```

Edit the configuration:

```bash
nano ~/.restic/restic-backup.conf
```

Update these settings:

```bash
# Set your repository location
RESTIC_REPOSITORY="/backup/restic-repo"

# Use password file from .secrets directory (recommended)
RESTIC_PASSWORD_FILE="$HOME/.secrets/restic-password"

# Define directories to backup (colon-separated)
BACKUP_TARGETS="/home/user/documents:/home/user/pictures:/home/user/projects"

# Optional: Set retention policy for automatic pruning
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=2
```

## Step 6: Test Your Setup

Verify your configuration:
```bash
./restic-backup.sh config
```

Check repository access:
```bash
./restic-backup.sh check
```

Perform a test backup:
```bash
./restic-backup.sh backup all
```

List snapshots:
```bash
./restic-backup.sh list
```

## Step 7: Automate Backups (Optional)

### Using cron

```bash
crontab -e
```

Add an entry for daily backups at 2 AM:
```
0 2 * * * /home/mkronvold/src/restic-backup/restic-backup.sh backup all
```

### Using systemd timer

Create `/etc/systemd/system/restic-backup.service`:
```ini
[Unit]
Description=Restic Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/home/mkronvold/src/restic-backup/restic-backup.sh backup all
User=mkronvold
Group=mkronvold
```

Create `/etc/systemd/system/restic-backup.timer`:
```ini
[Unit]
Description=Restic Backup Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable restic-backup.timer
sudo systemctl start restic-backup.timer
```

## Repository Maintenance

### Check repository integrity
```bash
./restic-backup.sh check
```

### Prune old snapshots (manual)
```bash
restic forget --keep-last 7 --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

### View repository statistics
```bash
restic stats
```

## Remote Repository Setup Examples

### SFTP Setup

1. Ensure SSH access to remote server:
```bash
ssh user@hostname
```

2. Create repository directory on remote server:
```bash
ssh user@hostname 'mkdir -p /path/to/repo'
```

3. Initialize:
```bash
export RESTIC_REPOSITORY="sftp:user@hostname:/path/to/repo"
export RESTIC_PASSWORD_FILE="$HOME/.restic-password"
restic init
```

### S3 Setup

1. Create S3 bucket via AWS Console or CLI

2. Configure AWS credentials:
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

3. Initialize:
```bash
export RESTIC_REPOSITORY="s3:s3.amazonaws.com/bucket-name"
export RESTIC_PASSWORD_FILE="$HOME/.restic-password"
restic init
```

4. Add AWS credentials to config file:
```bash
# In restic-backup.conf, add:
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

### Backblaze B2 Setup

1. Create B2 bucket and get credentials from Backblaze

2. Initialize:
```bash
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-application-key"
export RESTIC_REPOSITORY="b2:bucket-name:repo-name"
export RESTIC_PASSWORD_FILE="$HOME/.restic-password"
restic init
```

3. Add B2 credentials to config file:
```bash
# In restic-backup.conf, add:
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-application-key"
```

## Security Best Practices

1. **Password Security**
   - Use a strong, randomly generated password
   - Store in password file with restricted permissions (600)
   - Never commit passwords to version control

2. **Repository Access**
   - Limit file system permissions on local repositories
   - Use SSH keys (not passwords) for SFTP
   - Enable MFA for cloud storage accounts

3. **Backup Encryption**
   - Restic encrypts all data by default
   - Keep your password secure - lost passwords mean lost data
   - Consider backing up your password to a password manager

4. **Test Restores**
   - Regularly test restore operations
   - Verify backup integrity with `restic check`

## Troubleshooting

### "repository does not exist"
- Verify RESTIC_REPOSITORY path is correct
- Ensure repository has been initialized with `restic init`

### "wrong password"
- Check RESTIC_PASSWORD or RESTIC_PASSWORD_FILE
- Verify password file contents and permissions

### "cannot access repository"
- Check network connectivity for remote repositories
- Verify SSH keys for SFTP
- Confirm cloud credentials for S3/B2

### Permission denied
- Check file/directory permissions
- Ensure backup script has read access to source directories
- Verify write access to repository location

## Additional Resources

- [Restic Documentation](https://restic.readthedocs.io/)
- [Restic GitHub Repository](https://github.com/restic/restic)
- [Restic Forum](https://forum.restic.net/)
