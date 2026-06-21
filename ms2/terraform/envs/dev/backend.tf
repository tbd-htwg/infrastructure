terraform {
  backend "gcs" {
    bucket = "project-f7f74d87-072b-4e92-9c6-tfstate"
    prefix = "ms2/dev"
  }
}
