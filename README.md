# EC2 Classic Resource Finder
This script is designed to output all resources in EC2-Classic across all regions in an account and output them to CSVs. This bash script can be run on any bash terminal (including MacOS) with AWK and AWS CLI installed. 

We launched Amazon VPC on 5-Sep-2009 as an enhancement over EC2-Classic and while we maintained EC2-Classic in its current state for our existing customers, we continuously made improvements, and added cutting edge instances and networking features on Amazon VPC. In the spirit of offering best customer experience, we firmly believe that all our customers should migrate their resources from EC2-Classic to Amazon VPC. To help determine what resources may be running in EC2-Classic, this script will help identify resources running in EC2-Classsic in an ad-hoc, self-service manner. For more information on migrating to VPC, visit our [docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/vpc-migrate.html).

Currently this iterates through all EC2 regions and creates the following CSVs (note if no resources are found, no CSV is created for that resource category):
* Classic_Platform_Status.csv
* Classic_EIPs.csv
* Classic_EC2_Instances.csv
* Classic_SGs.csv
* Classic_Auto_Scaling_Groups.csv
* Classic_CLBs.csv 
* Classic_RDS_Instances.csv
* Classic_ElastiCache_Clusters.csv
* Classic_Redshift_Clusters.csv
* Classic_ElasticBeanstalk_Applications_Environments.csv
* Classic_DataPipelines.csv
* Classic_EMR_Clusters.csv
* Classic_OpsWorks_Stacks.csv


The script requires IAM permissions which can be configured using either aws configure, or an IAM role on EC2. The following permissions are required (against all resources):
* autoscaling:DescribeAutoScalingGroups
* datapipeline:GetPipelineDefinition
* datapipeline:ListPipelines
* ec2:DescribeAccountAttributes
* ec2:DescribeAddresses
* ec2:DescribeInstances
* ec2:DescribeRegions
* ec2:DescribeSecurityGroup
* elasticache:DescribeCacheClusters
* elasticloadbalancing:DescribeLoadBalancers
* elasticmapreduce:ListClusters
* elasticmapreduce:DescribeCluster
* opsworks:DescribeStacks
* redshift:DescribeClusters
* rds:DescribeDBInstances