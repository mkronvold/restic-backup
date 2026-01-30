# Restic Backup Script

A comprehensive bash script for managing restic backups with multiple directories, selective restore, and detailed logging.

## Features

- ✅ **Config-based setup** - Single configuration file for all settings
- ✅ **Multiple backup targets** - Backup multiple directories with one command
- ✅ **Selective operations** - Backup/restore individual targets or all at once
- ✅ **Flexible restore** - Restore to original or alternative locations
- ✅ **Comprehensive logging** - Tracks attempts, success/failure, and size metrics
- ✅ **Error handling** - Automatic cleanup of temporary files
- ✅ **Dependency checking** - Validates restic installation and configuration
- ✅ **Repository support** - Works with local, SFTP, S3, B2, and other backends

## Quick Start

1. **Install restic** (if not already installed):
   ```bash
   sudo apt install restic
   ```

2. **Clone this repository**:
   ```bash
   git clone https://github.com/yourusername/restic-backup.git
   cd restic-backup
   ```

3. **Configure your backup**:
   ```bash
   # Create directories with secure permissions
   mkdir -p ~/.restic ~/.secrets
   chmod 700 ~/.restic ~/.secrets
   
   # Copy example config
   cp restic-backup.conf.example ~/.restic/restic-backup.conf
   chmod 600 ~/.restic/restic-backup.conf
   nano ~/.restic/restic-backup.conf
   ```

4. **Initialize your restic repository** (first time only):
   ```bash
   # Create password file in .secrets directory
   echo "your-secure-password" > ~/.secrets/restic-password
   chmod 600 ~/.secrets/restic-password
   
   # Initialize repository
   export RESTIC_REPOSITORY="/backup/restic-repo"
   export RESTIC_PASSWORD_FILE="$HOME/.secrets/restic-password"
   restic init
   ```

5. **Run your first backup**:
   ```bash
   ./restic-backup.sh backup all
   ```

## Usage

```bash
./restic-backup.sh [OPTIONS] COMMAND
```

### Commands

| Command | Description |
|---------|-------------|
| `backup <target\|all>` | Backup a specific directory or all configured targets |
| `list [tag]` | List all snapshots or snapshots for a specific tag |
| `restore <snapshot> [path]` | Restore a specific snapshot to optional path |
| `restore-latest <tag> [path]` | Restore latest snapshot for tag to optional path |
| `restore-all [path]` | Restore all targets to optional base path |
| `prune` | Manually apply retention policy and prune old snapshots |
| `check` | Check repository integrity |
| `config` | Show current configuration (with masked password) |

### Options

| Option | Description |
|--------|-------------|
| `-c, --config FILE` | Use specified config file |
| `-l, --log FILE` | Use specified log file |
| `-h, --help` | Show detailed help |

### Examples

```bash
# Backup all configured directories
./restic-backup.sh backup all

# Backup a specific directory
./restic-backup.sh backup /home/user/documents

# List all snapshots
./restic-backup.sh list

# List snapshots for a specific target
./restic-backup.sh list documents

# Restore latest snapshot to original location
./restic-backup.sh restore-latest documents

# Restore to alternative location
./restic-backup.sh restore-latest documents /tmp/restore

# Restore specific snapshot
./restic-backup.sh restore a1b2c3d4 /tmp/restore

# Restore all targets to recovery location
./restic-backup.sh restore-all /mnt/recovery

# Check repository integrity
./restic-backup.sh check

# Manually prune old snapshots
./restic-backup.sh prune

# Show current configuration
./restic-backup.sh config
```

## Configuration

The script searches for configuration in this order:
1. `~/.restic/restic-backup.conf` (recommended)
2. `./restic-backup.conf` (fallback)
3. Path specified with `-c` option (override)

The configuration file uses bash syntax:

```bash
# Repository location (local, sftp, s3, b2, etc.)
RESTIC_REPOSITORY="/backup/restic-repo"

# Password file (recommended - stored in ~/.secrets/)
RESTIC_PASSWORD_FILE="$HOME/.secrets/restic-password"

# Colon-separated list of directories to backup
BACKUP_TARGETS="/home/user/documents:/home/user/pictures:/etc"

# Retention policy (automatic cleanup after backup)
KEEP_LAST=7        # Keep last 7 snapshots
KEEP_DAILY=14      # Keep 1 snapshot per day for 14 days
KEEP_WEEKLY=8      # Keep 1 snapshot per week for 8 weeks
KEEP_MONTHLY=12    # Keep 1 snapshot per month for 12 months
KEEP_YEARLY=3      # Keep 1 snapshot per year for 3 years
```

### Automatic Snapshot Pruning

By default, the script **automatically prunes old snapshots** after each `backup all` operation based on your retention policy. This means you don't need a separate cron job for cleanup.

**To disable automatic pruning:**
```bash
AUTO_PRUNE=false
```

**To manually prune:**
```bash
./restic-backup.sh prune
```

Logs are written to `~/.restic/restic-backup.log` by default.

### Supported Repository Types

- **Local**: `/path/to/repo`
- **SFTP**: `sftp:user@host:/path/to/repo`
- **Amazon S3**: `s3:s3.amazonaws.com/bucket-name`
- **Backblaze B2**: `b2:bucket-name:path`
- **Azure**: `azure:container:/path`
- **Google Cloud**: `gs:bucket-name:/path`
- **REST Server**: `rest:http://hostname:8000/`
- **rclone**: `rclone:remote:path`

See [SETUP.md](SETUP.md) for detailed setup instructions for each backend.

## Logging

All operations are logged to `~/.restic/restic-backup.log` (default) with:
- Timestamp for each operation
- Attempt/success/failure status
- Size metrics (files processed, data added)

**Log Rotation:**
- Logs automatically rotate when exceeding 10MB
- Keeps last 10 rotated logs (`.log.1` through `.log.10`)
- Oldest logs are removed automatically

Example log output:
```
[2026-01-29 14:30:00] [INFO] ATTEMPT: Backing up documents: /home/user/documents
[2026-01-29 14:30:15] [SUCCESS] Backup completed for documents
[2026-01-29 14:30:15] [INFO] SIZE: Files: 1234 (new: 5, changed: 10, unmodified: 1219)
[2026-01-29 14:30:15] [INFO] SIZE: Data added: 45.3 MiB
```

## Automation

### Using cron

```bash
crontab -e
```

Add for daily backups at 2 AM:
```
0 2 * * * /path/to/restic-backup.sh backup all
```

Or if the script is in your PATH:
```
0 2 * * * restic-backup.sh backup all
```

### Using systemd

See [SETUP.md](SETUP.md) for complete systemd timer configuration.

## Important Notes

### OneDrive and Cloud Sync

⚠️ **Do not** backup directly to OneDrive/Dropbox synced folders! This can cause:
- File sync conflicts
- Lock file issues
- Corruption during sync

**Recommended approach**: Use `rclone` backend:
```bash
RESTIC_REPOSITORY="rclone:onedrive:restic-repo"
```

See [SETUP.md](SETUP.md#remote-repository-setup-examples) for details.

### Security

- **Never commit your config file with passwords to git**
- Use `RESTIC_PASSWORD_FILE` instead of `RESTIC_PASSWORD`
- Store password in `~/.secrets/` with `chmod 700` on directory
- Set restrictive permissions: `chmod 600 ~/.secrets/restic-password`
- Set config permissions: `chmod 600 ~/.restic/restic-backup.conf`
- Use strong, randomly generated passwords
- **Important**: Lost passwords = lost backups (no recovery possible)

## Documentation

- **[SETUP.md](SETUP.md)** - Complete setup guide for all repository types
- **[restic Documentation](https://restic.readthedocs.io/)** - Official restic docs

## Requirements

- bash 4.0+
- restic 0.9.0+
- Standard Unix tools (grep, tee, date)

## License

MIT License - Feel free to use and modify as needed.

## Contributing

Issues and pull requests welcome!

## Troubleshooting

### "repository does not exist"
Run `restic init` to initialize the repository first.

### "wrong password"
Verify `RESTIC_PASSWORD` or `RESTIC_PASSWORD_FILE` is correct.

### "cannot access repository"
- Check network connectivity for remote repositories
- Verify SSH keys for SFTP
- Confirm cloud credentials for S3/B2

### Repository locked
```bash
# Check for stale locks
restic unlock
```

For more troubleshooting, see [SETUP.md](SETUP.md#troubleshooting).
