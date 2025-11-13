# Terraform Variables Configuration Guide

This guide explains how to configure the required variables for the HPC OOD Stack Terraform deployment.

## Required Variables

The following variables **must** be provided as they have no default values:

### 1. OCI Configuration
- `region` - Your OCI region (e.g., "us-ashburn-1", "us-phoenix-1", "eu-frankfurt-1")
- `tenancy_ocid` - Your OCI tenancy OCID (found in OCI Console > Administration > Tenancy Details)
- `targetCompartment` - Target compartment OCID where resources will be created

### 2. Availability Domains
- `ad` - Primary availability domain for your resources
- `controller_ad` - Controller availability domain (can be same as 'ad' or different)

### 3. SSH Access
- `ssh_key` - Path to your public SSH key file (e.g., "~/.ssh/id_rsa.pub")

### 4. Storage Configuration
- `controller_boot_volume_size` - Controller boot volume size in GB (minimum recommended: 50)
- `controller_boot_volume_backup` - Whether to enable backup for controller boot volume (true/false)

### 5. Open OnDemand (OOD) Configuration
- `ood_user_email` - Email address for the OOD user account
- `ood_user_password` - Password for the OOD user account

## Configuration Files

### Option 1: Minimal Configuration
Use `terraform.tfvars.minimal` for a quick start with only the required variables:

```bash
cp terraform.tfvars.minimal terraform.tfvars
# Edit terraform.tfvars with your actual values
```

### Option 2: Complete Configuration
Use `terraform.tfvars.example` for a comprehensive configuration with all variables and helpful comments:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
```

## How to Find Your Values

### OCI Tenancy OCID
1. Log into OCI Console
2. Go to Administration > Tenancy Details
3. Copy the OCID value

### Region
Common regions include:
- `us-ashburn-1` (US East)
- `us-phoenix-1` (US West)
- `eu-frankfurt-1` (Europe)
- `ap-sydney-1` (Asia Pacific)

### Availability Domains
1. In OCI Console, go to Compute > Instances
2. Click "Create Instance"
3. Note the available ADs (e.g., "AD-1", "AD-2", "AD-3")

### Compartment OCID
1. In OCI Console, go to Identity & Security > Compartments
2. Find your target compartment
3. Copy the OCID value

### SSH Key
Generate a new SSH key pair if you don't have one:
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

## Security Notes

- **Never commit `terraform.tfvars` to version control** as it may contain sensitive information
- Consider restricting `ssh_cidr` to your specific IP range instead of "0.0.0.0/0"
- Use strong passwords for OOD user accounts
- Store sensitive values in environment variables or use Terraform Cloud/Enterprise for better security

## Next Steps

1. Copy one of the example files to `terraform.tfvars`
2. Fill in all the required values
3. Run `terraform init` (already done)
4. Run `terraform plan` to review the deployment
5. Run `terraform apply` to create the infrastructure

## Troubleshooting

If you encounter issues:
1. Verify all required variables are set
2. Check that your OCI credentials are properly configured
3. Ensure you have the necessary permissions in your OCI tenancy
4. Review the Terraform plan output for any validation errors
