terraform {
  backend "gcs" {
    bucket = "tbd-cloudappdev-tfstate"
    prefix = "ms2/dev"
  }
}
