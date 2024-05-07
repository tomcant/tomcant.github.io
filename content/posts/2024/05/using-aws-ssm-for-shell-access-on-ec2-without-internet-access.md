---
title: 'Using AWS SSM for Shell Access on EC2 Without Internet Access'
date: 2024-05-03
---

I've recently been working on a personal project that uses a Postgres relational database for persistence.
I'm running the project on AWS and using EC2 instead of RDS to keep costs down.
I need shell access to the instance for inspecting configuration, but it's attached to a private subnet and has no public IP.

<!--more-->

One option would be to run a public tunnel/bastion instance for proxying SSH connections into the network, but I didn't really want the extra hassle (or indeed the attack surface), so I turned to [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) instead.
Session Manager offers the ability to connect to an EC2 instance for shell access just like connecting via SSH, except there's no need to open any ports or manage SSH keys.
Instead, it works based on IAM and a connection with the SSM Agent software installed on the instance.

I thought this would be relatively trivial to setup because I'm using Amazon Linux (AL2023) which comes with the agent pre-installed.
However, I hadn't configured internet access from the private subnet and it turns out the agent needs to talk to the following endpoints using HTTPS in order for this feature to work:

- **ssm**.&lt;region&gt;.amazonaws.com
- **ssmmessages**.&lt;region&gt;.amazonaws.com
- **ec2messages**.&lt;region&gt;.amazonaws.com

Configuring internet access wasn't something I wanted to do just for the sake of gaining shell access with SSM, so I checked the VPC Endpoints documentation to see if access to these services could be configured privately within the VPC instead.
To my delight AWS do indeed support these services via *Interface endpoints*, so the only additional infrastructure I required was an Elastic Network Interface and Security Group per endpoint.

In case it might be useful to someone, here's the Terraform configuration I used to provision these resources:

```hcl
locals {
  endpoints = toset(["ssm", "ssmmessages", "ec2messages"])
}

data "aws_vpc_endpoint_service" "endpoints" {
  for_each = local.endpoints

  service = each.value
}

resource "aws_vpc_endpoint" "endpoints" {
  for_each = local.endpoints

  service_name        = data.aws_vpc_endpoint_service.endpoints[each.value].service_name
  security_group_ids  = [aws_security_group.endpoints[each.value].id]
  subnet_ids          = aws_subnet.private.*.id
  vpc_id              = aws_vpc.main.id
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  tags = {
    Name = each.value
  }
}

resource "aws_security_group" "endpoints" {
  for_each = local.endpoints

  name_prefix = "vpc-endpoint-${each.value}-"
  description = "VPC Endpoint Security Group for ${each.value}"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = each.value
  }
}

resource "aws_security_group_rule" "endpoints" {
  for_each = local.endpoints

  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  security_group_id = aws_security_group.endpoints[each.value].id
}
```

<small><em>Tested with Terraform v1.8.2 and AWS provider v5.44.0, the latest at the time of writing.</em></small>

And with that, I can now run the following AWS CLI command locally to access the instance:

```shell
aws ssm start-session --target <instance-id>
```

Bear in mind this requires the AWS CLI and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) to be installed on the machine you run this command on.

The only downside I can think of with this solution is the cost; each VPC Endpoint is $0.79 per day (at the time of writing), which quickly racks up! Not ideal for a side project but could be worth it if you have a bigger budget.

In the end it turned out that my application needed internet access anyway so I removed this configuration in favour of a [custom-built NAT instance](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html) (not a NAT Gateway, those are expensive too), but this still seemed like a good exercise in configuring shell access when both inbound and outbound access is limited.
