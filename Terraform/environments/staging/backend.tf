terraform {
  backend "s3" {
    bucket         = "capstone-tfstate-XXXX"   # remplace par ton bucket du bootstrap
    key            = "staging/vpc.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "capstone-tfstate-XXXX-locks"
    encrypt        = true
  }
}