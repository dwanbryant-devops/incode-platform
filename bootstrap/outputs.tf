output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "tf_plan_role_arn" {
  value = aws_iam_role.tf_plan.arn
}

output "tf_apply_role_arn" {
  value = aws_iam_role.tf_apply.arn
}

output "ecr_push_role_arns" {
  description = "Set as AWS_ROLE_ARN in each app repo's GitHub Actions variables."
  value       = { for repo, role in aws_iam_role.ecr_push : repo => role.arn }
}
