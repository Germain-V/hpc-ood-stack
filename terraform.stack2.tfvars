# =============================================================================
# HPC OOD Stack - Minimal Required Variables
# =============================================================================
# This file contains ONLY the variables that have no default values and MUST be provided.
# Copy this file to terraform.tfvars and fill in your actual values.
# =============================================================================

# OCI Configuration
region = "us-ashburn-1"                    # e.g., "us-ashburn-1", "us-phoenix-1"
tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaa2l6fcfl7tfoun3i72tw4rjx4pja5lo7g5iakvptjzmuezihnr27q"             # Your OCI tenancy OCID
targetCompartment = "ocid1.tenancy.oc1..aaaaaaaa2l6fcfl7tfoun3i72tw4rjx4pja5lo7g5iakvptjzmuezihnr27q"        # Compartment OCID where resources will be created

# Availability Domains
ad = "iLlE:US-ASHBURN-AD-1"                       # Primary availability domain
controller_ad = "iLlE:US-ASHBURN-AD-1"            # Controller availability domain

# SSH Access
ssh_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDWXglEeGj/M0qWtVYiOm56nYjMAiROTHcgbDlH1hPpgud+k6lUigBf+O3D9mnUcuM0QqYkEdewiU/lJJyeuUHNLcy4p87QdLiFEnuRbjIOF0oejSc0kBKHx+ZNf66Ur+y0eQEh3L5e95VELweFOKRANvVojJBbjF/hRCaMgACTWiqljLHvpohKk4yypy97QzbrUigBHGdHateL6vy892jzU7fSOMv0msVM2rfxlIg3o1qFSlzgvB5XXbgdu1NsK4y6uRKqYQm77dROoxiTbF9cuTdE8AQUXCyrVT+OqGw/QVZTmQQWtqAm+UzIpp+vtOfyHL5XkdZ8Rw00ApmMv3u3"                  # Path to your public SSH key file

# Storage
controller_boot_volume_size = 150        # Controller boot volume size in GB
controller_boot_volume_backup = false    # Enable backup for controller boot volume

# Open OnDemand (OOD) User
ood_username = "koiker"
ood_user_email = "koike.rafael@oracle.com"           # Email for OOD user account
ood_user_password = "CwnX9.lK?mQ)BHZ4]+b*"        # Password for OOD user account

slurm = true
cluster_network = true
cluster_network_shape = "BM.Optimized3.36"
cluster_monitoring = true
autoscaling = true
autoscaling_monitoring = true
influxdb = true
controller_object_storage_par = true
rdma_subnet = "10.224.0.0/12"
compute_cluster = false
node_count = 2
healthchecks = false
use_existing_idcs = true
existing_domain_ocid = "ocid1.domain.oc1..aaaaaaaawdfo4wbnj2n3ru6o2mma26imzruniqac2phjaxgyvwwdobdufmea"
dns_entries = false

use_marketplace_image_controller = false
custom_controller_image = "ocid1.image.oc1.iad.aaaaaaaa6xtceq5mve2t7fpzgsxq43rzlemexzndwbh2sjocrwgiwiw5d2ya"

use_marketplace_image = false
image = "ocid1.image.oc1.iad.aaaaaaaa6xtceq5mve2t7fpzgsxq43rzlemexzndwbh2sjocrwgiwiw5d2ya"

login_node = false
latency_check = false


use_existing_vcn = true
vcn_compartment = "ocid1.tenancy.oc1..aaaaaaaa2l6fcfl7tfoun3i72tw4rjx4pja5lo7g5iakvptjzmuezihnr27q"
vcn_id = "ocid1.vcn.oc1.iad.amaaaaaatyq6jnyavb3ja23nsq2bpau2s6v2rccdxxdduoz7ggo53s24jdpq"
public_subnet_id = "ocid1.subnet.oc1.iad.aaaaaaaaakgs2mazuyioet2widoyyjgodbh7nfuadu5pe7y7sjoyuqugojta"
private_subnet_id = "ocid1.subnet.oc1.iad.aaaaaaaaux5uqu4srzoy5k253dkooixmgtrsu7auj5lyqqb7ojln3rlkbvlq"

cluster_name = "cluster2"