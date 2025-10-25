# EC2 Batch Tools

Bash scripts for batch operations on AWS EC2 instances - start, stop, list, change instance types, and EBS disk warm-up

## Features

- **List EC2 Instances** - Export instance information to CSV
- **Start/Stop Instances** - Bulk start or stop multiple instances
- **Change Instance Type** - Modify instance types for multiple instances at once
- **EBS Disk Warm-up** - Initialize EBS volumes restored from snapshots
- **Create EC2 Instances** - Batch create instances with Elastic IPs

## Prerequisites

- AWS CLI configured with appropriate credentials
- SSH key file for EC2 instances (for warm-up script)
- `jq` installed (for list script)
- Bash shell

## Configuration

Each script uses the following common variables that you should modify:

```bash
EC2_NAME="test"              # EC2 instance name prefix to filter
AWS_REGION="us-west-2"       # AWS region
```

## Scripts

### list_ec2_instances.sh

Lists EC2 instances matching the name prefix and exports to CSV.

```bash
./list_ec2_instances.sh
```

Output: `ec2_instances.csv` with Name, InstanceId, PublicDnsName, PublicIpAddress, State

### start_ec2_instances.sh

Starts all stopped instances matching the name prefix.

```bash
./start_ec2_instances.sh
```

### stop_ec2_instances.sh

Stops all running instances matching the name prefix.

```bash
./stop_ec2_instances.sh
```

### change_ec2_instance_type.sh

Changes instance type for stopped instances. Modify `NEW_INSTANCE_TYPE` variable before running.

```bash
# Edit the script to set desired instance type
NEW_INSTANCE_TYPE="t3.medium"

./change_ec2_instance_type.sh
```

**Note:** Instances must be stopped before changing instance type.

### ebs-disk-warm-up.sh

Performs EBS volume warm-up for instances restored from snapshots. This script:
- Installs `fio` if not present
- Reads entire disk to initialize all blocks
- Processes instances in batches
- Tracks completed servers to resume after interruption

```bash
# Configure these variables in the script
BATCH_SIZE=10                              # Number of instances to process simultaneously
SSH_USER="ubuntu"                          # SSH username
SSH_KEY_PATH="./your-key.pem"             # Path to SSH key file

./ebs-disk-warm-up.sh
```

**For long-running operations (50+ hours):**

Use `screen` to prevent session timeout:

```bash
# Install screen
sudo apt install -y screen

# Start screen session
screen -S warmup

# Run the script
./ebs-disk-warm-up.sh

# Detach: Ctrl+A, D
# Reattach later: screen -r warmup
```

Output: `completed_servers.txt` tracks finished instances

### create_ec2_instances_with_eip.sh

Creates multiple EC2 instances with Elastic IPs.

```bash
./create_ec2_instances_with_eip.sh
```

## Security Notes

- **Never commit SSH key files** (`.pem`, `.key`) to the repository
- **Never commit CSV files** containing IP addresses or instance information
- The `.gitignore` file is configured to exclude these sensitive files

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Feel free to submit issues or pull requests for improvements.
