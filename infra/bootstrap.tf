# bootstrap.tf
# Run this ONCE before anything else to create the S3 bucket and DynamoDB table
# that Terraform uses to store remote state.
#
# Steps:
#   1. Comment out the entire backend "s3" block in main.tf
#   2. Run: terraform init
#   3. Run: terraform apply -target=aws_s3_bucket.terraform_state -target=aws_dynamodb_table.terraform_lock
#   4. Uncomment the backend "s3" block in main.tf and update bucket name with the output value
#   5. Run: terraform init (Terraform will migrate local state to S3)

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.cluster_name}-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags
}

output "state_bucket_name" {
  description = "S3 bucket name — update the backend block in main.tf with this value"
  value       = aws_s3_bucket.terraform_state.bucket
}
