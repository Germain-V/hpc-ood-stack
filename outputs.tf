output "controller" {
  value = local.host
}

output "cluster_name" {
  value = oci_core_instance.controller.display_name
}

output "private_ips" {
  value = join(" ", local.cluster_instances_ips)
}

output "backup" {
  value = var.slurm_ha ? local.host_backup : "No Slurm Backup Defined"
}

output "login" {
  value = var.login_node ? local.host_login : "No Login Node Defined"
}

output "monitoring" {
  value = var.monitoring_node ? local.host_monitoring : "No Monitoring Node Defined"
}

// Open OnDemand Outputs

output "Open_OnDemand_Username" {
  description = "Username to login to your Open OnDemand Application"
  value = var.ood_username
}

output "Open_OnDemand_Password" {
  description = "Password to login to your Open OnDemand Application"
  value       = var.ood_user_password
  sensitive   = true
}

output "Open_OnDemand_URL" {
  description = "URL to your Open OnDemand Application"
  value       = "https://ood-${replace(oci_core_instance.controller.public_ip, ".", "-")}.nip.io/"
}

// Removed bootstrap command; scripts now read /opt/oci-hpc/ood.env

output "IDCS_URL" {
  description = "Identity Cloud Service metadata base URL"
  value       = local.idcs_url
}

// Open OnDemand Debugging

# output "app_client_id" {
#   value = oci_identity_domains_app.ood_app.name
# }

# output "app_client_secret" {
#   value = oci_identity_domains_app.ood_app.client_secret
# }

# output "idcs_url" {
#   value = local.idcs_url
# }

# output "idcs_domain_id" {
#   value = local.idcs_domain_id
# }

# output "controller_dns_record" {
#   value = "${oci_core_instance.controller.display_name}.${local.zone_name}"
# }

