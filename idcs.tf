# --- Existing Domain (optional) ---
data "oci_identity_domain" "idcs_domain" {
  count     = var.use_existing_idcs ? 1 : 0
  domain_id = var.use_existing_idcs ? var.existing_domain_ocid : null
}

resource "oci_identity_domain" "new_idcs_domain" {
  count     = var.use_existing_idcs ? 0 : 1

  # Required
  compartment_id  = var.targetCompartment
  home_region     = var.region
  display_name    = "HPC-OOD-IDCS-Domain"
  description     = "IDCS Domain for HPC Open OnDemand"
  license_type    = "Premium"

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      oci iam domain deactivate \
        --domain-id ${self.id}
      sleep 10
    EOT
  }
}

resource "oci_identity_domains_setting" "idcs_settings" {
  count = var.use_existing_idcs ? 0 : 1

  # Optional attributes
  signing_cert_public_access = true
  timezone = "America/New_York"
  # Required attributes
  schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:Settings"]
  setting_id =  "Settings"
  idcs_endpoint = oci_identity_domain.new_idcs_domain[0].url
  csr_access = "none"
}

resource "oci_identity_domains_app" "ood_app" {
  # Required
  display_name               = "${local.cluster_name}-Open-Ondemand"
  idcs_endpoint = var.use_existing_idcs ? (local.idcs_url) : (oci_identity_domain.new_idcs_domain[0].url)
  schemas                    = var.ood_schemas
  # Optional
  description                = "HPC OOD Application"
  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  active = var.active
  allowed_grants = var.allowed_grants                                   #["authorization_code", "client_credentials"]
  client_type = var.client_type                                         #"confidential"
  is_oauth_client = var.is_oauth_client                                 #true
  force_delete = var.force_delete                                       #true
  show_in_my_apps = var.show_in_my_apps                                 #true
  client_ip_checking = var.client_ip_checking                           #"anywhere"
  # Dynamically construct redirect URIs using the OOD instance public IP
  redirect_uris = [
    "https://ood-${replace(oci_core_instance.controller.public_ip, ".", "-")}.nip.io/oidc"
  ]
  post_logout_redirect_uris = [
    "https://ood-${replace(oci_core_instance.controller.public_ip, ".", "-")}.nip.io/"
  ]
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      oci identity-domains app patch \
        --endpoint ${self.idcs_endpoint} \
        --app-id ${self.id} \
        --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
        --operations '[{"op": "replace", "path": "active", "value": false}]'
      sleep 10
    EOT
  }
}

resource "oci_identity_domains_user" "ood_user" {
  count = var.use_existing_idcs ? 0 : 1
  idcs_endpoint = var.use_existing_idcs != "" ? (local.idcs_url) : (oci_identity_domain.new_idcs_domain[0].url)
  schemas       = var.user_schemas
  user_name     = var.ood_username
  display_name  = var.ood_username
  emails {
    value = var.ood_user_email
    type  = "work"
    primary = true
  }
  name {
    given_name  = var.ood_username
    family_name = var.ood_username
  }
  active = true
}
