locals {
  service_account_emails = {
    platform-admin = "platform-admin@${var.project_id}.iam.gserviceaccount.com"
    gitops         = "gitops@${var.project_id}.iam.gserviceaccount.com"
    workload       = "workload@${var.project_id}.iam.gserviceaccount.com"
  }
}
