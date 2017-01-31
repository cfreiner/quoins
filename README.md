# Concur Quoins

Quoins are a set of [Terraform][terraform] modules used as building blocks for
an immutable infrastructure. We carefully curated a set of sane defaults for
configuring a provider's environment, but also allows you to fully customize it.

[Quoin's][quoin-definition] are best described as cornerstone's for a
building. They provide load bearing support to a wall.

Currently, the quoins only support [AWS][aws]. The available quoins:

- A network with an internet gateway
- External & internal network layout including NAT gateways
- Some default security groups for SSH and Windows Remoting
- A key pair
- A bastion jump host
- An external elastic load balancer
- A [Kubernetes][kubernetes] cluster

[terraform]: https://www.terraform.io/
[aws]: https://aws.amazon.com/
[quoin-definition]: https://en.wikipedia.org/wiki/Quoin
[kubernetes]: http://kubernetes.io

## Requirements

Before we run through the quickstart, there's a few requirements:

- [ ] Download and install [terraform][terraform-install]
- [ ] An [AWS][aws] account
- [ ] Locally configured [AWS credentials][aws-credentials]

[terraform-install]: https://www.terraform.io/intro/getting-started/install.html
[aws-credentials]: http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html#cli-quick-configuration

## Quickstart

_Disclaimer: To run the quoins, you'll need AWS access and terraform
installed. See [requirements](#requirements)._

Quoins are designed to be modular and the easiest way to get started is to
compose a terraform definition that picks the modules you need. Each module is
a building block that can be used separately to create your immutable
infrastructure.

Let's compose a configuration that uses the network module:

```hcl
module "network" {
  source   = "github.com/concur/quoins//network"
  cidr     = "172.16.0.0/16"
  name     = "prod-us-network"
}

provider "aws" {
  region      = "us-west-2"
  max_retries = 3
}
```

Since we're using a configuration that uses a module, prior to running any
commands such as plan or apply, we have to get the modules. This is done using
the get command:

    $ terraform get -update=true

To stage the changeset, let's run the plan command:

    $ terraform plan -out=plan.bin

To apply the changeset, let's run the apply command:

    $ terraform apply plan.bin

## License

Released under the [MIT License][mit-license]. See [LICENSE][license] for more information.

[mit-license]: http://www.opensource.org/licenses/mit-license.php
[license]: https://github.com/concur/quoins/blob/master/LICENSE
