terraform {
  backend "s3" {
    bucket         = "capstone-tfstate-igor-2026-06-21"   # remplace par ton bucket du bootstrap
    key            = "staging/vpc.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "capstone-tfstate-igor-2026-06-21-locks"
    encrypt        = true
  }
}