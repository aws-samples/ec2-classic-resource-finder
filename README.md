# EC2 Classic Resource Finder

***EC2 Classic Resource Finder 2.0 is here. Read more below.***

***EC2-Classic Networking is Retiring*** Find out how to prepare [here](https://aws.amazon.com/blogs/aws/ec2-classic-is-retiring-heres-how-to-prepare/)

We launched Amazon VPC on 5-Sep-2009 as an enhancement over EC2-Classic and while we maintained EC2-Classic in its current state for our existing customers, we continuously made improvements, added cutting edge instances, and networking features on Amazon VPC. In the spirit of offering the best customer experience, we firmly believe that all our customers should migrate their resources from EC2-Classic to Amazon VPC. To help determine what resources may be running in EC2-Classic, this script will help identify resources running in EC2-Classic in an ad-hoc, self-service manner. For more information on migrating to VPC, visit our [docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/vpc-migrate.html).

Version 2.0 of this script is now available, named [py-Classic-Resource-Finder.py](py-Classic-Resource-Finder.py). This new iteration still loops through all regions where EC2-Classic is supported and determine if EC2-Classic is enabled and what, if any, resources are running or configured to run in EC2-Classic. The multi-account-wrapper is now built in and uses command line arguments to run. Additionally, use of multiple [AWS Credential profiles](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/credentials.html#shared-credentials-file) is now supported. This will output to a set of CSVs in a folder created for each account it is run against. The script is now written in Python and uses Boto3. It runs using multiprocessing to improve runtimes. Please note, because this runs multiple processes simultaneously it may consume more CPU. It is suggested not to run this on the same instance, or computer that is running any critical workloads that may become deprived of computational resources while this is running. Additionally, this fixes an issue with the version 1 script where AWS ElasticBeanstalk Environments with a space in the name may render a false positive. Any errors rendered in the Error CSV should be investigated to determine if the output was still accurate.

### Known issues / Notes:

* If you are running ElasticBeanstalk Environments in the Default VPC by not specifying a VPC, this may produce a false positive.
* If you are creating and terminating resources regularly, such as EMR clusters, this script does not identify terminated resources. If you have resources such as DataPipelines or AutoScaling Groups which create and terminate Classic EC2 Instances, as long as the DataPipeline or AutoScaling Group exists at the time the script is run it will be identified as configured to launch Classic resources, even if no Classic EC2 Instances are currently running.
* Classic Load Balancers which are running in a VPC are not in scope for this retirement, only Classic Load Balancers which are not running in a VPC, and therefore running in EC2-Classic need to be migrated to a VPC as part of this retirement.

## Requirements

This script is designed to run using Python 3 and requires the [Boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html). Credentials must be pre-configured using the AWS CLI, or an instance IAM profile, if using Amazon EC2. You can read more about how to pre-authenticate [here](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/credentials.html)

* To install the Boto3, follow the instructions [here](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/quickstart.html#installation)

## Outputs

Currently, this iterates through all EC2 regions which support EC2-Classic and creates the following CSVs prepended with the date and time in a folder for each account it is run against:

| File Name                                              | Description                                                                     | Output                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------ |
| Classic_Platform_Status.csv                            | Regions with the ability to launch resources into EC2-Classic                   | Region, Status (Enabled, Disabled)         |
| Classic_EIPs.csv                                       | Elastic IPs allocated for EC2-Classic                                           | IP Address, Region                         |
| Classic_EC2_Instances.csv                              | EC2 Instances provisioned in EC2-Classic                                        | Instance ID, Region                        |
| Classic_SGs.csv                                        | Security Groups configured in EC2-Classic                                       | Security Group ID, Region                  |
| Classic_ClassicLink_VPCs.csv                           | VPCs with ClassicLink Enabled                                                   | VPC ID, Region                             |
| Classic_Auto_Scaling_Groups.csv                        | Auto-Scaling groups configured to launch EC2 Instances into EC2-Classic         | ASG ARN, Region                            |
| Classic_CLBs.csv                                       | Classic Load Balancers provisioned in EC2-Classic                               | CLB Name, Region                           |
| Classic_RDS_Instances.csv                              | RDS Database Instances provisioned in EC2-Classic                               | DB Instance ARN, Region                    |
| Classic_ElastiCache_Clusters.csv                       | ElastiCache clusters provisioned in EC2-Classic                                 | Cluster ARN, Region                        |
| Classic_Redshift_Clusters.csv                          | Redshift clusters provisioned in EC2-Classic                                    | Cluster Identifier, Region                 |
| Classic_ElasticBeanstalk_Applications_Environments.csv | ElasticBeanstalk Applications and Environments configured to run in EC2-Classic | Application Name, Environment Name, Region |
| Classic_DataPipelines.csv                              | DataPipelines configured to launch instances in EC2-Classic                     | Pipeline ID, Region                        |
| Classic_EMR_Clusters.csv                               | EMR Clusters that may be configured to launch instances in EC2-Classic          | Cluster ID, Region                         |
| Classic_OpsWorks_Stacks.csv                            | OpsWorks stacks that have resources configured for EC2-Classic                  | Stack ID, Region                           |
| Error.txt                                              | This outputs any errors encountered when running the script.                    | print text of error outputs                |

## Permissions

The script requires IAM permissions which can be configured using either aws configure, or an IAM role on EC2. The following permissions are required (against all resources):

* autoscaling:DescribeAutoScalingGroups
* datapipeline:GetPipelineDefinition
* datapipeline:ListPipelines
* ec2:DescribeAccountAttributes
* ec2:DescribeAddresses
* ec2:DescribeInstances
* ec2:DescribeRegions
* ec2:DescribeSecurityGroups
* ec2:DescribeVpcClassicLink
* elasticbeanstalk:DescribeConfigurationSettings
* elasticbeanstalk:DescribeEnvironments
* elasticache:DescribeCacheClusters
* elasticloadbalancing:DescribeLoadBalancers
* elasticmapreduce:DescribeCluster
* elasticmapreduce:ListBootstrapActions
* elasticmapreduce:ListClusters
* elasticmapreduce:ListInstanceGroups
* rds:DescribeDBInstances
* redshift:DescribeClusters
* opsworks:DescribeStacks
* sts:GetCallerIdentity

### ElasticBeanstalk Specific Permissions

If you are utilizing ElasticBeanstalk, you will need the following additional permissions to identify environments and applications configured to launch resources in EC2-Classic. If you do not utilize ElasticBeanstalk, you can ignore the below permissions, and the script will continue to run successfully for all other services and produce an empty CSB for ElasticBeanstalk.

* autoscaling:DescribeAutoScalingInstances
* autoscaling:DescribeLaunchConfigurations
* autoscaling:DescribeScheduledActions
* cloudformation:DescribeStackResource
* cloudformation:DescribeStackResources
* ec2:DescribeImages
* ec2:DescribeSubnets
* ec2:DescribeVpcs
* ec2:CreateLaunchTemplate
* ec2:CreateLaunchTemplateVersion
* rds:DescribeDBEngineVersions
* rds:DescribeOrderableDBInstanceOptions
* s3:ListAllMyBuckets

The following permissions to allow the identification of ElasticBeanstalk environments that launch resources in EC2-Classic can be limited to a resource of `arn:aws:s3:::elasticbeanstalk-*`

* s3:GetObject
* s3:GetObjectAcl
* s3:GetObjectVersion
* s3:GetObjectVersionAcl
* s3:GetBucketLocation
* s3:GetBucketPolicy
* s3:ListBucket

### Multi-Account Permissions

* organizations:ListAccounts
* sts:AssumeRole

## Requirements for multi-account usage

* The IAM user which runs the script must be able to assume the role specified in each account in the organization (If STS AssumeRole fails, we simply skip running the input script against that account and print an error to the standard output)
* The role name for the role being called must exist in every AWS account within the organization and have the same name (If STS AssumeRole fails, we simply skip running the input script against that account)
* The role being called must have permissions to run all commands specified in the script. (For py-Classic-Resource-Finder see the permissions section above.)
* If ExternalID is required, you must specify the value in the input for Multi-Account-Wrapper

## Command line arguments

py-Classic-Resource-Finder.py can be called without any arguments and will be run against the account for the default configured credential.

### All Accounts in an Organization

#### With an External ID:

```python
python3 py-Classic-Resource-Finder.py -o -r <role name> -e <external ID>
```

or

```python
python3 py-Classic-Resource-Finder.py --organization --rolename <role name> --externalid <external ID>
```

#### Without an External ID:

```python
python3 py-Classic-Resource-Finder.py -o -r <role name>
```

or

```python
python3 py-Classic-Resource-Finder.py --organization --rolename <role name>
```

### Use Profile[s] in the Credential File

#### Single Profile

```python
python3 py-Classic-Resource-Finder.py -p <profile name>
```

or

```python
python3 py-Classic-Resource-Finder.py --profile <profile name>
```

#### Multiple Profiles

Use a comma delimited list of profile names. Do not put a space around the commas.

```python
python3 py-Classic-Resource-Finder.py -p <profile name 1>,<profile name 2>,<profile name 3>
```

or

```python
python3 py-Classic-Resource-Finder.py --profile <profile name 1>,<profile name 2>,<profile name 3>
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
