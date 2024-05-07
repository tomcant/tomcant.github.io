---
title: Codifying Authentication for Terraform Cloud in an AWS Control Tower Environment
date: 2022-06-23
draft: false
---

I recently stumbled upon an old diagram I drew to document part of our platform at [MyBuilder.com](https://www.mybuilder.com),
and this got me thinking it _could_ be useful to share publicly. Let's see...

<!--more-->

<img src="multi-aws-account-auth.jpeg">

The diagram shows a number of AWS accounts used to run applications on Lambda, with access granted to Terraform Cloud
and GitHub Actions via IAM users. We use Terraform to provision supporting infrastructure like networks and databases,
and we use the Serverless framework to create runtime resources like Lambda functions.
What the diagram doesn't show is that we manage the accounts with AWS Control Tower, and what I want to share is how we
handle authentication for Terraform across a multi-account Control Tower environment.

Note that this post is specific to Terraform Cloud, where a backend configuration similar to the following is used:

```hcl
terraform {
  backend "remote" {
    organization = "MyBuilder"

    workspaces {
      name = "some-app-prod"
    }
  }
}
```

If you use Terraform CLI then the OIDC protocol (OpenID Connect) is another option worth considering, but at the time of
writing [this is not supported by Terraform Cloud](https://discuss.hashicorp.com/t/oidc-auth-aws-azure/35463/2).
Instead, the process described here requires an IAM user with an access key in the root AWS account. We'll authenticate
as this user and use the [STS AssumeRole action](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
to access the child accounts.

Now, if you're anything like me then the thought of creating resources by clicking around the AWS console makes you
shudder, and most of the time we don't have to. It wouldn't take a moment
to codify an IAM user, but unfortunately we'll find ourselves in a bit of a chicken and egg scenario trying to provision
it: Terraform needs an IAM user to gain access!

I always feel a sense of fragility when a system's desired state isn't codified, so manually creating an
IAM user for something so critical is painful. There are a few similar cases where we've had no choice, but
we make sure they're documented in our Terraform repository. Here's the first entry in `MANUALCONFIG.md`:

```json
- Created the TerraformCloud IAM user with inline policy:

  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "sts:AssumeRole",
        "Resource": [
          "arn:aws:iam::*:role/InfraProvisioner",
          "arn:aws:iam::*:role/AWSControlTowerExecution"
        ]
      }
    ]
  }
```

The policy allows the user to assume the `InfraProvisioner` role, so now we just need to create the role in each child
account. Fortunately (for our sanity) we don't have to do this manually...

Notice the `AWSControlTowerExecution` role in the policy; this is present in each account managed by Control Tower and
has unrestricted permission to perform any action. We _could_ just use this role for all Terraform Cloud access going forward, but it's better not to depend on
a Control Tower implementation detail if we can help it; AWS could change or remove the role without notice and break our workflows.
Instead, we use this role in a one-off task to
create the `InfraProvisioner` role, which we know will be safe to use going forward. This also allows us to attach a
custom policy with restrictions on what Terraform is allowed to do.

With this in mind, here's how we configure the AWS provider to provision the roles:

<div class="highlight-filename before">projects/infra-provisioner-roles/config.tf</div>

```hcl
provider "aws" {
  alias      = "prod"
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  assume_role {
    role_arn = format(
      "arn:aws:iam::%s:role/AWSControlTowerExecution",
      var.aws_accounts["prod"]["account_id"]
    )
    session_name = "TerraformCloudViaControlTower"
  }
}
```

The `access_key` and `secret_key` attributes come from the IAM access key created earlier, and the Control Tower role is
specified in the `role_arn` attribute. Terraform will assume this role in the `prod` account by looking up an account ID
in the `aws_accounts` map variable, defined as follows:

<div class="highlight-filename before">projects/infra-provisioner-roles/variables.tf</div>

```hcl
variable "aws_accounts" {
  type = map(object({
    account_id  = string
    external_id = string
  }))
}
```

The `external_id` attribute is a secret string that provides an additional layer of security. It will form part of the
policy on the new role and will be required in calls to the AssumeRole action. We configure `aws_accounts` to look like
this in the Terraform Cloud workspace:

```hcl
aws_accounts = {
  prod = {
    account_id  = "prod account ID"
    external_id = "...secret string..."
  }
  staging = {
    ...
  }
}
```

In practice there are many more accounts in the map, otherwise it might just be simpler to maintain a few basic
variables.

Next, we need to define an IAM policy to limit what the `InfraProvisioner` role can do. At the very least this should
limit scope to the services we expect Terraform to maintain. It may also be desirable to block actions that delete
certain types of resources, just in case a destroy plan is accidentally applied (or not accidentally!).

For demonstration purposes I've specified wide open permissions, but I wouldn't recommend this anywhere in the real
world...

<div class="highlight-filename before">projects/infra-provisioner-roles/policy.tf</div>

```hcl
data "aws_iam_policy_document" "infra_provisioner_policy" {
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}
```

Creation of the actual role is handled by a module that gets invoked once for each account, as follows:

<div class="highlight-filename before">projects/infra-provisioner-roles/main.tf</div>

```hcl
module "provisioner_role_prod" {
  source = "modules/assume-role"

  providers = {
    aws = aws.prod
  }

  name           = "InfraProvisioner"
  policy         = data.aws_iam_policy_document.infra_provisioner_policy.json
  trusted_entity = format("arn:aws:iam::%s:user/TerraformCloud", var.aws_root_account_id)
  external_id    = var.aws_accounts["prod"]["external_id"]
}

module "provisioner_role_staging" {
  ...
}
```

Notice the `trusted_entity` attribute. This specifies the AWS principal that will be granted access to the role (the
root IAM user in this case), and the module will take care of enforcing this in the role policy.

We should end up with a provider block and a module invocation for each account. All this duplication can't be
avoided because [we can't pass providers to modules dynamically](https://github.com/hashicorp/terraform/issues/24476),
but hopefully this will change in an upcoming release of Terraform.

Lastly, we define the `assume-role` module as follows:

<div class="highlight-filename before">modules/assume-role/main.tf</div>

```hcl
variable "name" {}
variable "policy" {}
variable "trusted_entity" {}
variable "external_id" {}

resource "aws_iam_role" "assume_role" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "assume_role" {
  name   = var.name
  policy = var.policy
}

resource "aws_iam_role_policy_attachment" "assume_role" {
  role       = aws_iam_role.assume_role.name
  policy_arn = aws_iam_policy.assume_role.arn
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.trusted_entity]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}
```

## Putting It All Together

We now have an IAM user with an access key in the root account and an IAM role in each account we want Terraform to
provision resources in. The last thing to show is how we use the new role to authenticate.

An example configuration for a project that defines the infrastructure of some app could look like this:

<div class="highlight-filename before">projects/some-app/variables.auth.tf</div>

```hcl
variable "aws_region" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_account_id" {}
variable "aws_role_external_id" {}
```

<div class="highlight-filename before">projects/some-app/config.tf</div>

```hcl
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  assume_role {
    role_arn = format(
      "arn:aws:iam::%s:role/InfraProvisioner",
      var.aws_account_id
    )
    external_id  = var.aws_role_external_id
    session_name = "TerraformCloud"
  }
}
```

<div class="highlight-filename before">projects/some-app/network.tf</div>

```hcl
resource "aws_vpc" "some_app_vpc" {
  ...
}
```

## Wrapping Up

Looking back it feels like we've got a lot of configuration for not a lot in return! However, the value of this
approach becomes clear as you scale up the number of accounts under Control Tower's management. At MyBuilder we
currently manage ~70 accounts, so having some kind of automation in place for creating all the roles is a necessity. The
value becomes clearer still when you consider that we need to maintain all of this again for authentication from other
platforms, e.g. GitHub Actions.

In the future I'm hoping we can simplify some of this configuration by using OIDC. It would likely still require the
manual configuration of an [IAM OIDC identity provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html),
but there would be no need to maintain an IAM user and access key.

Hopefully someone finds the ideas described here useful in some way. Happy Terraforming!
