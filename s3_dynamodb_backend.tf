terraform {
  required_version = ">= 1.0.0"
  backend "s3" {
    bucket         = "nginx-autohealing-binhbe"           # Thay bằng tên bucket S3 của bạn
    key            = "terraform/state/terraform.tfstate" # Đường dẫn file state trong bucket
    region         = "ap-southeast-1"               # Thay bằng region của bạn
    use_lockfile   = true
  }
}

#resource "aws_s3_bucket" "tf_state" {
#  bucket = "nginx-autohealing-binhbe"
#  force_destroy = true
#  versioning {
#    enabled = true
#  }
#  server_side_encryption_configuration {
#    rule {
#      apply_server_side_encryption_by_default {
#        sse_algorithm = "AES256"
#      }
#    }
#  }
#  lifecycle {
#    prevent_destroy = false
#   ignore_changes = [bucket]
#  }
#}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "Nginx-autohealing-binhbe-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
