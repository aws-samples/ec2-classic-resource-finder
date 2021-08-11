# EC2 Classic Resource Finder

***EC2-Classic Networking is Retiring*** Find out how to prepare [here ](https://aws.amazon.com/blogs/aws/ec2-classic-is-retiring-heres-how-to-prepare/)

We launched Amazon VPC on 5-Sep-2009 as an enhancement over EC2-Classic and while we maintained EC2-Classic in its current state for our existing customers, we continuously made improvements, added cutting edge instances, and networking features on Amazon VPC. In the spirit of offering the best customer experience, we firmly believe that all our customers should migrate their resources from EC2-Classic to Amazon VPC. To help determine what resources may be running in EC2-Classic, this script will help identify resources running in EC2-Classic in an ad-hoc, self-service manner. For more information on migrating to VPC, visit our [docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/vpc-migrate.html).
 
This script helps identify all resources provisioned in EC2-Classic across all regions which support EC2-Classic in an account, as well as each of those regions' enablement status for EC2-Classic. Depending on the number of resources you are running, and the number of regions you are in, this script may take longer to run in order to describe and evaluate all resources. If no resources were found, all CSVs will be empty except Classic_Platform_Status.csv which will show the current status in each region. Also, make sure to check the errors.txt for any errors that occurred during running the script. It is normal to see some errors related to `Could not connect to the endpoint URL` for DataPipeline in some regions in which the service is not available in. Other errors should be investigated to confirm any missing data.
 
 
 
## Requirements
 
This script is designed to run in Bash and requires the [AWS CLI] (https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html), JQ, and the linux Cut utility. The CLI must either be already authenticated either via an IAM role, AWS SSO or an IAM access key with appropriate permissions as outlined below.
 
### For Mac
 
* To install the AWS CLI, follow the instructions [here](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html)
* To install JQ, run `brew install jq`
 
### For Amazon Linux 2
 
* To install the AWS CLI, follow the instructions [here](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html). (Note: many Amazon Linux 2 AMIs already have CLI installed. You can verify it is installed by running `aws --version`)
* To install JQ, run `yum -y install jq`
 
 
 
 
## Outputs
 
Currently, this iterates through all EC2 regions and creates the following CSVs:
 
| File Name                                              | Description                                                                     | Output                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------ |
| Classic_Platform_Status.csv                            | Regions with the ability to launch resources into EC2-Classic                   | Region, Status (Enabled, Disabled)         |
| Classic_EIPs.csv                                       | Elastic IPs allocated for EC2-Classic                                           | IP Address, Region                         |
| Classic_EC2_Instances.csv                              | EC2 Instances provisioned in EC2-Classic                                        | Instance ID, Region                        |
| Classic_SGs.csv                                        | Security Groups configured in EC2-Classic                                       | Security Group ID, Region                  |
| Classic_ClassicLink_VPCs.csv                           | VPCs with ClassicLink Enabled                                                   | VPC ID, Region                             |
| Classic_Auto_Scaling_Groups.csv                        | Auto-Scaling groups configured to launch EC2 Instances into EC2-Classic         | ASG ARN, Region                            |
| Classic_CLBs.csv                                       | Classic Loadbalancers provisioned in EC2-Classic                                | CLB Name, Region                           |
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
 
###ElasticBeanstalk Specific Permissions
 
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

# Multi-Account-Wrapper
Included in this repository is [multi-account-wrapper.sh](multi-account-wrapper.sh) which allows users needing to run the Classic-Resource-Finder against many accounts within an AWS Organization. Multi-account-wrapper has a few very specific requirements of its own, please make sure to read them carefully.

## Requirements 

* The IAM user which runs the script must have `organizations:ListAccounts` `sts:GetCallerIdentity` and `sts:AssumeRole` permissions
* The IAM user which runs the script must be able to assume the role specified in each account in the organization (If STS AssumeRole fails, we simply skip running the input script against that account)
* The role name for the role being called must exist in every AWS account within the organization and have the same name (If STS AssumeRole fails, we simply skip running the input script against that account)
* The role being called must have permissions to run all commands specified in the script. (For Classic-Resource-Finder see the permissions section above.)
* If ExternalID is required, you must specify the value in the input for Multi-Account-Wrapper
* The AWS CLI and JQ must be installed and configured as well as any other dependencies of the called script
* The called script must be written and executable in BASH (This is already taken care of in Classic-Resource-Finder)

## How to use Multi-Account-Wrapper

Multi-account-wrapper is designed to assume a specified role in each account within an organization and run a bash script using the credentials from that assumed role. To run the multi-account-wrapper for Classic-Resource-Finder.sh run the following command replacing the values in brackets with the appropriate value (Note: if ExternalId is required by the assumed role, please see the optional commandline switch below the following command.). A folder will be created for each account and any output will be created in the folder for each account. If MFA is required, the Multi-Account-Wrapper will not work.

```
multi-account-wrapper.sh -r <ROLE NAME> -f "Classic-Resource-Finder.sh"
```

Command Line switches:
* -r  <ROLE NAME> The name of the IAM Role to be assumed in each account within the Organization
* -f  <BASH FILE TO EXECUTE> The relative or exact path of the BASH file to execute against each account in the Organization
* -e  <EXTERNAL ID> The External ID to specify when calling AssumeRole

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
