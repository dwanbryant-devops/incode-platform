variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "incode"
}

variable "github_org" {
  type    = string
  default = "dwanbryant-devops"
}

variable "github_owner_id" {
  description = "Immutable numeric ID of the GitHub owner (gh api users/<org> --jq .id)."
  type        = number
  default     = 332991340
}

variable "github_repo_ids" {
  description = "Immutable numeric repo IDs (gh api repos/<org>/<repo> --jq .id). GitHub's OIDC sub claim includes them."
  type        = map(number)
  default = {
    "incode-platform"                  = 1383886992
    "golang-gin-realworld-example-app" = 1383921949
    "angular-realworld-example-app"    = 1383920665
  }
}

variable "platform_repo" {
  description = "Repo that runs Terraform plan/apply."
  type        = string
  default     = "incode-platform"
}

variable "apply_environments" {
  description = "GitHub Environments (with required reviewers) allowed to assume the apply role. Add one per deployed env."
  type        = list(string)
  default     = ["dev"]
}

variable "image_push_environment" {
  description = "GitHub Environment in the app repos that holds the push role. Restrict it to the main branch in GitHub."
  type        = string
  default     = "dev"
}

variable "image_repos" {
  description = "App repo name => ECR repository it may push to."
  type        = map(string)
  default = {
    "angular-realworld-example-app"    = "incode/ui"
    "golang-gin-realworld-example-app" = "incode/api"
  }
}
