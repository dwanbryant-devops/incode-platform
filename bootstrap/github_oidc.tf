locals {
  oidc_host = "token.actions.githubusercontent.com"

  # GitHub's `sub` claim identifies the repo as owner@ownerID/repo@repoID. Pinning the
  # immutable IDs means a deleted-and-recreated repo (or a renamed org) with the same name
  # can't assume these roles.
  repo_sub = { for repo, id in var.github_repo_ids : repo => "repo:${var.github_org}@${var.github_owner_id}/${repo}@${id}" }

  platform_repo = local.repo_sub[var.platform_repo]
}

# AWS validates GitHub's OIDC certificate chain itself, so no thumbprint is needed.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# Builds a trust policy for GitHub OIDC that allows only the listed `sub` claims.
data "aws_iam_policy_document" "trust" {
  for_each = merge(
    {
      tf-plan  = ["${local.platform_repo}:pull_request", "${local.platform_repo}:ref:refs/heads/main"]
      tf-apply = [for e in var.apply_environments : "${local.platform_repo}:environment:${e}"]
    },
    { for repo, _ in var.image_repos : "ecr-push-${repo}" => ["${local.repo_sub[repo]}:environment:${var.image_push_environment}"] },
  )

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# Terraform plan: read-only everywhere, plus writing lock files to the state bucket.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "tf_plan" {
  name                 = "gha-tf-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust["tf-plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_plan_state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
  statement {
    sid       = "LockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "tf_plan_state" {
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan_state.json
}

# ---------------------------------------------------------------------------
# Terraform apply: admin, but only from a GitHub Environment with required reviewers,
# and it can't modify the bootstrap resources that control its own access.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "tf_apply" {
  name                 = "gha-tf-apply"
  assume_role_policy   = data.aws_iam_policy_document.trust["tf-apply"].json
  max_session_duration = 7200 # EKS create + addons can take a while
}

resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "tf_apply_guardrails" {
  statement {
    sid    = "ProtectCiIdentities"
    effect = "Deny"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/gha-*"]
  }
  statement {
    sid       = "ProtectOidcProvider"
    effect    = "Deny"
    actions   = ["iam:*OpenIDConnectProvider*"]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }
  statement {
    sid       = "ProtectStateBucket"
    effect    = "Deny"
    actions   = ["s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  statement {
    sid       = "NoIamUsersOrKeys"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tf_apply_guardrails" {
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply_guardrails.json
}

# ---------------------------------------------------------------------------
# App CI: each repo can push only to its own ECR repository, and only from a job in
# its `dev` GitHub Environment (which is restricted to the main branch).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecr_push" {
  for_each             = var.image_repos
  name                 = "gha-ecr-push-${replace(each.value, "/", "-")}"
  assume_role_policy   = data.aws_iam_policy_document.trust["ecr-push-${each.key}"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ecr_push" {
  for_each = var.image_repos

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      "ecr:PutImage", "ecr:DescribeImages", "ecr:DescribeImageScanFindings",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/${each.value}"]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = var.image_repos
  role     = aws_iam_role.ecr_push[each.key].id
  policy   = data.aws_iam_policy_document.ecr_push[each.key].json
}
