resource "aws_iam_user" "dev_readonly" {
  name = "dev-readonly"
  tags = { Project = "bedrock" }
}

data "aws_iam_policy_document" "dev_readonly_min" {
  statement {
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "dev_readonly_min" {
  name        = "DevEksReadOnlyMinimal"
  description = "Allow STS identity + EKS DescribeCluster"
  policy      = data.aws_iam_policy_document.dev_readonly_min.json
}

resource "aws_iam_user_policy_attachment" "dev_min_attach" {
  user       = aws_iam_user.dev_readonly.name
  policy_arn = aws_iam_policy.dev_readonly_min.arn
}

output "dev_readonly_user_arn" {
  value = aws_iam_user.dev_readonly.arn
}
