#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


## Unset a bunch of variables we will use later
unset AWSCURRENTVERSION
unset AWSVERSIONREGEX
unset region
unset ebapp
unset ebenv
unset ebnsval
unset ebnsvalregex
unset pipeline
unset dpdefinition
unset dpdefinitionregex
unset emrclust
unset emrsubnet
unset emrsubnetregex
unset opsstack
unset opsip
unset opselb
unset opsec2
unset classicstatus

## Check to make sure AWS CLI is installed
AWSCURRENTVERSION=`aws --version 2>&1`  ## Get the version of the AWS CLI installed. If the AWS CLI is not installed the error pipes to dev null
AWSVERSIONREGEX="^(aws-cli\/)"  ## Set the regex we compare the AWS CLI version against to make sure a valid version of AWS CLI is installed
if [[ ! $AWSCURRENTVERSION =~ $AWSVERSIONREGEX ]]  ## If the AWS CLI version does not fit to the regex for a valid AWS CLI version
    then printf "AWS CLI does not appear to be installed, please install the AWS CLI and try running this again.\n" ## Then print an error
    exit 1 ## and exit the script with a non success (non-zero) error code
fi


## Search for EC2-Classic Resources
for region in `aws ec2 describe-regions --query 'Regions[*].RegionName' --output text --region us-east-1 | awk 'BEGIN { OFS = "\n" } { $1=$1; print }'` ## Use the EC2 CLI to get all region and loop through them
do
    printf "# -------------------------------------------------------------------------\nSearching for resources in EC2-Classic in $region\n# -------------------------------------------------------------------------\n\n"

    ## Get Enablement Status
    printf "Determining if EC2-Classic is enabled..."
    classicstatus=`aws ec2 describe-account-attributes --attribute-names supported-platforms --query 'AccountAttributes[*].AttributeValues[*].AttributeValue' --region $region --output text 2> /dev/null | grep EC2` ## Get supported platforms for the region.
    if [[ ${#classicstatus} -gt 2 ]]
        then printf "$region, Enabled\n" >> Classic_Platform_Status.csv ## If supported platforms includes EC2 in addition to VPC, output the region and Enabled to a CSV
        else printf "$region, Disabled\n" >> Classic_Platform_Status.csv ## If supported platforms is only VPC and does not include EC2, output the region and Disabled to a CSV
    fi
    printf "Done \xE2\x9C\x94 \n"

    ## Search for EIPs
    printf "Searching for EIPs in EC2-Classic..."
    aws ec2 describe-addresses --filters Name=domain,Values=standard --region $region --query 'Addresses[*].PublicIp' --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_EIPs.csv  ## Get all EIPs in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"

    ## Search for EC2 Instances
    printf "Searching for any EC2-Classic instances..."
    aws ec2 describe-instances --query 'Reservations[*].Instances[?VpcId==`null`].InstanceId' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_EC2_Instances.csv ## Get all EC2 Instance IDs in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for Security Groups
    printf "Searching for any Security Groups not in a VPC..."
    aws ec2 describe-security-groups --query 'SecurityGroups[?VpcId==`null`].GroupId' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_SGs.csv ## Get all Security Group IDs in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search VPC Classic Links
    printf "Searching for VPCs with ClassicLink Enabled..."
    aws ec2 describe-vpc-classic-link --filter "Name=is-classic-link-enabled,Values=true" --query 'Vpcs[*].VpcId' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_ClassicLink_VPCs.csv ## Get all VPC IDs with ClassicLink emabled and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for Auto-Scaling Groups
    printf "Searching for Auto-Scaling groups without a VPC configured..."
    aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?VPCZoneIdentifier==``].AutoScalingGroupName' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_Auto_Scaling_Groups.csv ## Get all ASGs in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for CLBs
    printf "Searching for any Classic Load Balancer in EC2-Classic..."
    aws elb describe-load-balancers --query 'LoadBalancerDescriptions[?VPCId==`null`].LoadBalancerName' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_CLBs.csv ## Get all CLBs in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for RDS DBs
    printf "Searching for any RDS-Classic instances..."
    aws rds describe-db-instances --query 'DBInstances[?DBSubnetGroup==`null`].DBInstanceArn' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_RDS_Instances.csv ## Get all RDS Instances in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for ElastiCache Clusters
    printf "Searching for any Elasticache clusters not in a VPC..."
    aws elasticache describe-cache-clusters --query 'CacheClusters[?CacheSubnetGroupName==`null`].ARN'  --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_ElastiCache_Clusters.csv ## Get all ElastiCache Clusters in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for Redshift Cluster
    printf "Searching for any Redshift clusters not in a VPC..."
    aws redshift describe-clusters --query 'Clusters[?VpcId==`null`].ClusterIdentifier' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_Redshift_Clusters.csv ## Get all Redshift Clusters in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for ElasticBeanstalk Environments
    printf "Searching for any ElasticBeanstalk Environments without a VPC..."
    for ebapp in `aws elasticbeanstalk describe-environments --query 'Environments[*].ApplicationName' --region $region --output text 2> /dev/null | awk 'BEGIN { OFS = "\n" } { $1=$1; print }'`   ## Get EB Application Names
    do
        for ebenv in `aws elasticbeanstalk describe-environments --application-name $ebapp --query 'Environments[*].EnvironmentName' --region $region --output text 2> /dev/null | awk 'BEGIN { OFS = "\n" } { $1=$1; print }'` ## Get EB Environment Names for the Application
        do
            ebnsval=`aws elasticbeanstalk describe-configuration-settings --application-name $ebapp --environment-name $ebenv --query 'ConfigurationSettings[*].OptionSettings[?Namespace==\`aws:ec2:vpc\`&&OptionName==\`VPCId\`&&Value!=\`null\`].OptionName' --region $region --output text 2> /dev/null` ## If the engironment is configured for a vpc return "VPCId"
            ebnsvalregex="VPCId"
            if [[ ! $ebnsval == $ebnsvalregex ]] ## If the configuration does not have a VPC:
                then printf "$ebapp, $ebenv, $region\n" >> Classic_ElasticBeanstalk_Applications_Environments.csv ## Return the Application Name, Environment Name and Region for EB that doesnt have a VPC
            fi
        done
    done
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for DataPipelines
    printf "Searching for any DataPipelines that dont have subnets associated..."
    for pipeline in `aws datapipeline list-pipelines --query 'pipelineIdList[*].id' --region $region --output text 2> /dev/null | awk 'BEGIN { OFS = "\n" } { $1=$1; print }'` ## Get all data pipelines in the region
    do
        dpdefinition=`aws datapipeline get-pipeline-definition --pipeline-id $pipeline --query 'objects[?type==\`Ec2Resource\`&&subnetId==\`null\`].type' --region $region --output text 2> /dev/null` ## Return "Ec2Resource" only if the ec2 resource subnet ID is null
        dpdefinitionregex="Ec2Resource"
        if [[ $dpdefinition == $dpdefinitionregex ]]
            then printf "$pipeline, $region\n" >> Classic_DataPipelines.csv ## Return the Pipeline ID and region and output it to a CSV
        fi
    done
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for EMR Clusters
    printf "Searching for EMR clusters not configured to launch in a subnet..."
    for emrclust in `aws emr list-clusters --query 'Clusters[*].Id' --region $region --output text 2> /dev/null | awk 'BEGIN { OFS = "\n" } { $1=$1; print }'` ## Get all EMR clusters in the region
    do
        emrsubnet=`aws emr describe-cluster --cluster-id $emrclust --query 'Cluster.Ec2InstanceAttributes.RequestedEc2SubnetIds==\`null\`' --region $region --output text 2> /dev/null` ## Get "true" for clusters that don't have a VPC subnet configured and "false" for ones that do have a subnet configured
        emrsubnetregex="true"
        if [[ $emrclust == $emrsubnetregex ]] ## If the cluster doesn't have a subnet configured then: 
            then printf "$emrclust, $region\n" >> Classic_EMR_Clusters.csv ## Return the Cluster ID and region and output it to a CSV
        fi
    done
    printf "Done \xE2\x9C\x94 \n"
    
    ## Search for OpsWorks Stacks
    printf "Searching for OpsWorks stacks with resources in EC2-Classic..."
    aws opsworks describe-stacks --query 'Stacks[?VpcId==`null`].StackId' --region $region --output text 2> /dev/null | awk '{gsub("\t","\n",$0); print;}' | sed -e "s/$/,$region/" >> Classic_OpsWorks_Stacks.csv ## Get all OpsWorks Stacks in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xE2\x9C\x94 \n"
    
    printf "\n# -------------------------------------------------------------------------\nSearch for resources in $region is complete\n# -------------------------------------------------------------------------\n\n\n\n"
done

printf "Search for EC2-Classic Resources is complete! Please check for the CSVs output to this directory."
printf "If no resources were found in EC2-Classic for a service, there was no CSV created."
printf "As a final step once you have verified you have no other EC2-Classic resources, "
printf "please open a support case and request your account be converted to VPC-Only as outlined in this document: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/vpc-migrate.html \n\n"
