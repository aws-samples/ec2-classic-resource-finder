#!/bin/bash
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
unset awscurrentversion awsversionregex jqtest cuttest region classicstatus ec2next ec2loopcounter ec2raw sgnext sgloopcounter sgraw asgnext asgloopcounter \
    asgraw clbnext clbloopcounter clbraw rdsnext rdsloopcounter rdsraw ecachenext ecacheloopcounter ecacheraw redshiftnext redshiftloopcounter redshiftraw ebappnext \
    ebapploopcounter ebappraw ebenvapp ebapp ebenv ebnsval ebnsvalregex dpnext dploopcounter dpraw pipeline dpdefinition dpdefinitionregex emrnext emrloopcounter \
    emrraw emrclust emrclustconfig emrsubnetid emrrequestedsubnetids

## Check to make sure AWS CLI is installed
awscurrentversion=`aws --version 2>&1`  ## Get the version of the AWS CLI installed. If the AWS CLI is not installed the error pipes to dev null
awsversionregex="^(aws-cli\/)"  ## Set the regex we compare the AWS CLI version against to make sure a valid version of AWS CLI is installed
if [[ ! $awscurrentversion =~ $awsversionregex ]]  ## If the AWS CLI version does not fit to the regex for a valid AWS CLI version
    then printf "AWS CLI does not appear to be installed, please install the AWS CLI and try running this again.\n" ## Then print an error
    exit 1 ## and exit the script with a non success (non-zero) error code
fi

jqtest=`jq -r '.test' <<< '{"test": "success"}' 2>> errors.txt` ## Parse a simple JSON input to output "success", pipe all errors to dev null
if [[ ! $jqtest == "success" ]] ## If the test did not result in the output of "success"
    then printf "JQ does not appear to be installed, please install JQ and try running this again.\n" ## Then print an error
    exit 1 ## and exit the script with a non success (non-zero) error code
fi

cuttest=`cut -d " " -f2 <<< "fail success" 2>> errors.txt` ## Parse a simple input to output "success", pipe all errors to dev null
if [[ ! $cuttest == "success" ]] ## If the test did not result in the output of "success"
    then printf "cut does not appear to be installed, please install cut and try this again.\n" ## Then print an error
    exit 1 ## and exit the script with a non success (non-zero) error code
fi

## Search for EC2-Classic Resources
declare -a regions=('us-east-1' 'eu-west-1' 'us-west-1' 'ap-southeast-1' 'ap-northeast-1' 'us-west-2' 'sa-east-1' 'ap-southeast-2') ## Define regions that support EC2-Classic
for region in "${regions[@]}" ## Loop through the regions that support EC2-Classic
do
    printf "# -------------------------------------------------------------------------\nSearching for resources in EC2-Classic in $region\n# -------------------------------------------------------------------------\n\n"

    ## Get Enablement Status
    printf "Determining if EC2-Classic is enabled..."
    classicstatus=`aws ec2 describe-account-attributes --attribute-names supported-platforms --region $region --output json 2>> errors.txt` ## Get supported platforms for the region.
    if [[ ${#classicstatus} -gt 2 ]] ## Make sure we got a return value
        then classicstatusfiltered=`jq -r '.AccountAttributes[] .AttributeValues[] | select(.AttributeValue=="EC2") | .AttributeValue' <<< $classicstatus 2>> errors.txt` ##Filter the input to determine if EC2 (classic) is supported
            if [[ ${#classicstatusfiltered} -gt 2 ]]
                then printf "$region, Enabled\n" >> Classic_Platform_Status.csv ## If supported platforms includes EC2 in addition to VPC, output the region and Enabled to a CSV
                else printf "$region, Disabled\n" >> Classic_Platform_Status.csv ## If supported platforms is only VPC and does not include EC2, output the region and Disabled to a CSV
            fi
        else printf "$region, Unknown\n" >> Classic_Platform_Status.csv
    fi
    printf "Done \xe2\x9c\x85 \n"

    ## Search for EIPs
    printf "Searching for EIPs in EC2-Classic..."
    aws ec2 describe-addresses --filters Name=domain,Values=standard --region $region --output json 2>> errors.txt | jq -r --arg region ",$region" '.Addresses[] .PublicIp + $region' >> Classic_EIPs.csv  ## Get all EIPs in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xe2\x9c\x85 \n"

    ## Search for EC2 Instances
    printf "Searching for any EC2-Classic instances..."
    ec2next="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i ec2loopcounter ## Set a variable as int for loop counter
    ec2loopcounter=1 ## Set the loop counter value to 1
    while [[ ${#ec2next} -gt 10 ]] && [[ $ec2loopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $ec2next == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then ec2raw=`aws ec2 describe-instances --region $region --filter Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped --query '{NextToken:NextToken,Reservations:Reservations[*].Instances[?VpcId==\`null\`]}' --output json 2>> errors.txt` ## Get the NextToken and InstanceID in JSON and store it in a variable
            else ec2raw=`aws ec2 describe-instances --region $region --filter Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped --query '{NextToken:NextToken,Reservations:Reservations[*].Instances[?VpcId==\`null\`]}' --starting-token $ec2next --output json 2>> errors.txt` ## Get the NextToken and InstanceID in in JSON starting at the current token value and store it in a variable
        fi
        ec2next=`jq -r '.NextToken' <<< $ec2raw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        jq -r --arg region ",$region" '.Reservations[] | .[] .InstanceId + $region' <<< $ec2raw >> Classic_EC2_Instances.csv ## Parse the instance IDs, append the region to each line delimited by a comma and output to the CSV
        ec2loopcounter=$((ec2loopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"

    ## Search for Security Groups
    printf "Searching for any Security Groups not in a VPC..."
    sgnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i sgloopcounter ## Set a variable as int for loop counter
    sgloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#sgnext} -gt 10 ]] && [[ $sgloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $sgnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then sgraw=`aws ec2 describe-security-groups --query '{NextToken:NextToken,SecurityGroups:SecurityGroups[?VpcId==\`null\`].GroupId}' --region $region --output json 2>> errors.txt` ## Get the NextToken and Security GroupID in JSON and store it in a variable
            else sgraw=`aws ec2 describe-security-groups --query '{NextToken:NextToken,SecurityGroups:SecurityGroups[?VpcId==\`null\`].GroupId}' --region $region --output json --starting-token $sgnext 2>> errors.txt` ## Get the NextToken and Security GroupID in in JSON starting at the current token value and store it in a variable
        fi
        sgnext=`jq -r '.NextToken' <<< $sgraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        jq -r --arg region ",$region" '.SecurityGroups[] + $region' <<< $sgraw >> Classic_SGs.csv ## Parse the Security Group IDs, append the region to each line delimited by a comma and output to the CSV
        sgloopcounter=$((sgloopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"

    ## Search VPC Classic Links
    printf "Searching for VPCs with ClassicLink Enabled..."
    aws ec2 describe-vpc-classic-link --filter "Name=is-classic-link-enabled,Values=true" --region $region --output json 2>> errors.txt | jq -r --arg region ",$region" '.Vpcs[] .VpcId + $region' >> Classic_ClassicLink_VPCs.csv ## Get all VPC IDs with ClassicLink emabled and output them with their corresponding region to a CSV
    printf "Done \xe2\x9c\x85 \n"

    ## Search for Auto-Scaling Groups
    printf "Searching for Auto-Scaling groups without a VPC configured..."
    asgnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i asgloopcounter ## Set a variable as int for loop counter
    asgloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#asgnext} -gt 10 ]] && [[ $asgloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $asgnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then asgraw=`aws autoscaling describe-auto-scaling-groups --query '{NextToken:NextToken,AutoScalingGroups:AutoScalingGroups[?VPCZoneIdentifier==\`\`]}' --region $region --output json 2>> errors.txt` ## Get the NextToken and ASG ARN in JSON and store it in a variable
            else asgraw=`aws autoscaling describe-auto-scaling-groups --query '{NextToken:NextToken,AutoScalingGroups:AutoScalingGroups[?VPCZoneIdentifier==\`\`]}' --region $region --output json --starting-token $asgnext 2>> errors.txt` ## Get the NextToken and ASG ARN in in JSON starting at the current token value and store it in a variable
        fi
        asgnext=`jq -r '.NextToken' <<< $asgraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        jq -r --arg region ",$region" '.AutoScalingGroups[] .AutoScalingGroupARN + $region' <<< $asgraw >> Classic_Auto_Scaling_Groups.csv ## Parse the ASG ARN, append the region to each line delimited by a comma and output to the CSV
        asgloopcounter=$((asgloopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"
    
    ## Search for CLBs
    printf "Searching for any Classic Load Balancer in EC2-Classic..."
    clbnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i clbloopcounter ## Set a variable as int for loop counter
    clbloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#clbnext} -gt 10 ]] && [[ $clbloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $clbnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then clbraw=`aws elb describe-load-balancers --query '{NextMarker:NextMarker,LoadBalancerName:LoadBalancerDescriptions[?VPCId==\`null\`]}' --region $region --output json 2>> errors.txt` ## Get the NextMarker and CLB Name in JSON and store it in a variable
            else clbraw=`aws elb describe-load-balancers --query '{NextMarker:NextMarker,LoadBalancerName:LoadBalancerDescriptions[?VPCId==\`null\`]}' --region $region --starting-token $clbnext --output json 2>> errors.txt` ## Get the NextMarker and CLB Name in in JSON starting at the current token value and store it in a variable
        fi
        clbnext=`jq -r '.NextMarker' <<< $clbraw 2>> errors.txt` ## Use JQ to parse the NextMarker and store it in a variable
        jq -r --arg region ",$region" '.LoadBalancerName[] .LoadBalancerName + $region' <<< $clbraw 2>> errors.txt >> Classic_CLBs.csv ## Parse the CLB Name, append the region to each line delimited by a comma and output to the CSV
        clbloopcounter=$((clbloopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"

    ## Search for RDS DBs
    printf "Searching for any RDS-Classic instances..."
    rdsnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i rdsloopcounter ## Set a variable as int for loop counter
    rdsloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#rdsnext} -gt 10 ]] && [[ $rdsloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $rdsnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then rdsraw=`aws rds describe-db-instances --query '{NextToken:NextToken,DBInstanceArn:DBInstances[*].DBInstanceArn}' --region $region --output json 2>> errors.txt` ## Get the NextToken and DB ARN in JSON and store it in a variable
            else rdsraw=`aws rds describe-db-instances --query '{NextToken:NextToken,DBInstanceArn:DBInstances[*].DBInstanceArn}' --region $region --starting-token $rdsnext --output json 2>> errors.txt` ## Get the NextToken and DB ARN in in JSON starting at the current token value and store it in a variable
        fi
       
        rdsnext=`jq -r '.NextToken' <<< $rdsraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        for dbinstance in `jq -r '.DBInstanceArn[]' <<< $rdsraw 2>> errors.txt` ## Loop through all DB Instances
        do 
            instancesg=`aws rds describe-db-instances --filters Name=db-instance-id,Values=$dbinstance --query 'DBInstances[*].VpcSecurityGroups[*].VpcSecurityGroupId' --region $region --output text 2>> errors.txt` ## Get the VPC Security Group ID[s] attached. If it is classic, this will be empty.
            if [[ ${#instancesg} -lt 5 ]] ## If the return is empty, thus classic then:
                then printf "$dbinstance, $region \n" >> Classic_RDS_Instances.csv ## Print the DB Instance ARN and Region and output it to a CSV
            fi
            unset instancesg ## Clean up our variable from this loop
        done
        rdsloopcounter=$((rdsloopcounter + 1))
        unset dbinstance rdsraw ## Clean up our variables from this loop
    done
    printf "Done \xe2\x9c\x85 \n"

    ## Search for ElastiCache Clusters
    printf "Searching for any Elasticache clusters not in a VPC..."
    ecachenext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i ecacheloopcounter ## Set a variable as int for loop counter
    ecacheloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#ecachenext} -gt 10 ]] && [[ $ecacheloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $ecachenext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then ecacheraw=`aws elasticache describe-cache-clusters --query '{NextToken:NextToken,ARN:CacheClusters[?CacheSubnetGroupName==\`null\`]}' --region $region --output json 2>> errors.txt` ## Get the NextToken and Cluster ARN in JSON and store it in a variable
            else ecacheraw=`aws elasticache describe-cache-clusters --query '{NextToken:NextToken,ARN:CacheClusters[?CacheSubnetGroupName==\`null\`]}' --region $region --starting-token $ecachenext --output json 2>> errors.txt` ## Get the NextToken and Cluster ARN in in JSON starting at the current token value and store it in a variable
        fi
        ecachenext=`jq -r '.NextToken' <<< $ecacheraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        jq -r --arg region ",$region" '.ARN[] .ARN + $region' <<< $ecacheraw 2>> errors.txt >> Classic_ElastiCache_Clusters.csv ## Parse the Cluster ARN, append the region to each line delimited by a comma and output to the CSV
        ecacheloopcounter=$((ecacheloopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"

    ## Search for Redshift Cluster
    printf "Searching for any Redshift clusters not in a VPC..."
    redshiftnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i redshiftloopcounter ## Set a variable as int for loop counter
    redshiftloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#redshiftnext} -gt 10 ]] && [[ $redshiftloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $redshiftnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then redshiftraw=`aws redshift describe-clusters --query '{NextToken:NextToken,ClusterIdentifier:Clusters[?VpcId==\`null\`]}' --region $region --output json 2>> errors.txt` ## Get the NextToken and Cluster Identifier in JSON and store it in a variable
            else redshiftraw=`aws redshift describe-clusters --query '{NextToken:NextToken,ClusterIdentifier:Clusters[?VpcId==\`null\`]}' --region $region --starting-token $redshiftnext --output json 2>> errors.txt` ## Get the NextToken and Cluster Identifier in in JSON starting at the current token value and store it in a variable
        fi
        redshiftnext=`jq -r '.NextToken' <<< $redshiftraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        jq -r --arg region ",$region" '.ClusterIdentifier[] .ClusterIdentifier + $region' <<< $redshiftraw 2>> errors.txt >> Classic_Redshift_Clusters.csv ## Parse the Cluster Identifier, append the region to each line delimited by a comma and output to the CSV
        redshiftloopcounter=$((redshiftloopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"
    
    ## Search for ElasticBeanstalk Environments
    printf "Searching for any ElasticBeanstalk Environments without a VPC..."
    ebappnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i ebapploopcounter ## Set a variable as int for loop counter
    ebapploopcounter=1 ## Set the loop counter value to 1
    while [[ ${#ebappnext} -gt 10 ]] && [[ $ebapploopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $ebappnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then ebappraw=`aws elasticbeanstalk describe-environments --no-include-deleted --query '{NextToken:NextToken,Environments:Environments[*]}' --region $region  --output json 2>> errors.txt` ## Get the NextToken and environment values in JSON and store it in a variable
            else ebappraw=`aws elasticbeanstalk describe-environments --no-include-deleted --query 'Environments[*]' --region $region  --output json --starting-token $ebappnext 2>> errors.txt` ## Get the NextToken and environment values in in JSON starting at the current token value and store it in a variable
        fi
        ebappnext=`jq -r '.NextToken' <<< $ebappraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        IFS=$'\n' ## Set our internal field seperator to newline so we ignore the space delimiter in the for loop
        for ebenvapp in `jq -r '.Environments[] | .ApplicationName +" "+ .EnvironmentName' <<< $ebappraw 2>> errors.txt` ## Loop over each application and environment pair
            do
            ebapp=`cut -d " " -f1 <<< $ebenvapp 2>> errors.txt` ## Extract the Application name
            ebenv=`cut -d " " -f2 <<< $ebenvapp 2>> errors.txt` ## Extract the Environment name
            ebnsval=`aws elasticbeanstalk describe-configuration-settings --application-name $ebapp --environment-name $ebenv --query 'ConfigurationSettings[*].OptionSettings[?Namespace==\`aws:ec2:vpc\`&&OptionName==\`VPCId\`&&Value!=\`null\`].OptionName' --region $region --output text 2>> errors.txt` ## If the environment is configured for a vpc return "VPCId"
            ebnsvalregex="VPCId"
            if [[ ! $ebnsval == $ebnsvalregex ]] ## If the configuration does not have a VPC:
                then printf "$ebapp, $ebenv, $region\n" >> Classic_ElasticBeanstalk_Applications_Environments.csv ## Return the Application Name, Environment Name and Region for EB that doesnt have a VPC
            fi
            unset ebapp
            unset ebenv
            unset ebnsval
            unset ebnsvalregex
        done
        unset ebappraw
        unset ebenvapp
    done
    printf "Done \xe2\x9c\x85 \n"
    
    ## Search for DataPipelines
    printf "Searching for any DataPipelines that dont have subnets associated..."
    dpnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i dploopcounter ## Set a variable as int for loop counter
    dploopcounter=1 ## Set the loop counter value to 1
    while [[ ${#dpnext} -gt 10 ]] && [[ $dploopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $dpnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then dpraw=`aws datapipeline list-pipelines --query '{NextToken:NextToken,id:pipelineIdList[*]}' --region $region --output json 2>> errors.txt` ## Get the NextToken and Pipeline ID in JSON and store it in a variable
            else dpraw=`aws datapipeline list-pipelines --query '{NextToken:NextToken,id:pipelineIdList[*]}' --region $region --starting-token $dpnext --output json 2>> errors.txt` ## Get the NextToken and Pipeline ID in in JSON starting at the current token value and store it in a variable
        fi
        dpnext=`jq -r '.NextToken' <<< $dpraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        for pipeline in `jq -r '.id[] .id' <<< $dpraw 2>> errors.txt` ## Parse the Cluster Identifier, append the region to each line delimited by a comma and output to the CSV
        do
            dpdefinition=`aws datapipeline get-pipeline-definition --pipeline-id $pipeline --query 'objects[?type==\`Ec2Resource\`&&subnetId==\`null\`].type' --region $region --output text 2>> errors.txt` ## Return "Ec2Resource" only if the ec2 resource subnet ID is null
            dpdefinitionregex="Ec2Resource"
            if [[ $dpdefinition == $dpdefinitionregex ]]
                then printf "$pipeline, $region\n" >> Classic_DataPipelines.csv ## Return the Pipeline ID and region and output it to a CSV
            fi
            unset dpdefinition
            unset dpdefinitionregex
        done
        unset pipeline
        unset dpraw
        dploopcounter=$((dploopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"
    
    ## Search for EMR Clusters
    printf "Searching for EMR clusters not configured to launch in a subnet..."
    emrnext="placeholder" ## Set a placeholder value for pagination token so the while loop kicks in. It gets dropped later in an IF statement.
    declare -i emrloopcounter ## Set a variable as int for loop counter
    emrloopcounter=1 ## Set the loop counter value to 1
    while [[ ${#emrnext} -gt 10 ]] && [[ $emrloopcounter -lt 100 ]] ## While the next token is not empty or "null" and the loopcounter is less than 100 
        do
        if [[ $emrnext == "placeholder" ]] ## If token is still the placeholder, dont pass a starting-token else pass the starting token
            then emrraw=`aws emr list-clusters --active --query '{NextToken:NextToken,id:Clusters[*]}' --region $region --output json 2>> errors.txt` ## Get the NextToken and cluster ID in JSON and store it in a variable
            else emrraw=`aws emr list-clusters --active --query '{NextToken:NextToken,id:Clusters[*]}' --region $region --starting-token $emrnext --output json 2>> errors.txt` ## Get the NextToken and cluster ID in in JSON starting at the current token value and store it in a variable
        fi
        emrnext=`jq -r '.NextToken' <<< $emrraw 2>> errors.txt` ## Use JQ to parse the NextToken and store it in a variable
        for emrclust in `jq -r '.id[] .Id' <<< $emrraw 2>> errors.txt` ## Parse the Cluster Identifier, append the region to each line delimited by a comma and output to the CSV
        do
            emrclustconfig=`aws emr describe-cluster --cluster-id $emrclust --query 'Cluster.Ec2InstanceAttributes' --region $region --output json 2>> errors.txt` ## Get "true" for clusters that don't have a VPC subnet configured and "false" for ones that do have a subnet configured
            emrsubnetid=`jq -r '.Ec2SubnetId' <<< $emrclustconfig 2>> errors.txt`
            emrrequestedsubnetids=`jq -r '.RequestedEc2SubnetIds[]' <<< $emrclustconfig 2>> errors.txt`
            if [[ ${#emrsubnetid} -lt 10 ]] && [[ ${#emrrequestedsubnetids} -lt 10 ]] ## If the cluster doesn't have a subnet configured then: 
                then printf "$emrclust, $region\n" >> Classic_EMR_Clusters.csv ## Return the Cluster ID and region and output it to a CSV
            fi
            unset emrsubnetid
            unset emrrequestedsubnetids
            unset emrclustconfig
        done
        unset emrclust
        unset emrraw
        emrloopcounter=$((emrloopcounter + 1))
    done
    printf "Done \xe2\x9c\x85 \n"
    
    ## Search for OpsWorks Stacks
    printf "Searching for OpsWorks stacks with resources in EC2-Classic..."
    aws opsworks describe-stacks --query 'Stacks[?VpcId==`null`]' --region $region --output json 2>> errors.txt | jq -r --arg region ",$region" '.[] .StackId + $region' >> Classic_OpsWorks_Stacks.csv ## Get all OpsWorks Stacks in EC2-Classic and output them with their corresponding region to a CSV
    printf "Done \xe2\x9c\x85 \n"
    
    ## Unset all the variables we used within the region loop
    unset classicstatus ec2next ec2loopcounter ec2raw sgnext sgloopcounter sgraw asgnext asgloopcounter \
        asgraw clbnext clbloopcounter clbraw rdsnext rdsloopcounter rdsraw ecachenext ecacheloopcounter ecacheraw redshiftnext redshiftloopcounter redshiftraw ebappnext \
        ebapploopcounter ebappraw ebenvapp ebapp ebenv ebnsval ebnsvalregex dpnext dploopcounter dpraw pipeline dpdefinition dpdefinitionregex emrnext emrloopcounter \
        emrraw emrclust emrclustconfig emrsubnetid emrrequestedsubnetids

    printf "\n# -------------------------------------------------------------------------\nSearch for resources in $region is complete\n# -------------------------------------------------------------------------\n\n\n\n"
done

## Unset all the variables we used outside of and for the region loop
unset awscurrentversion awsversionregex jqtest cuttest region 

printf "Search for EC2-Classic Resources is complete! Please check for the CSVs output to this directory."
printf "If no resources were found in EC2-Classic for a service, empty CSVs were created with no resources except for Classic_Platform_Status.csv which shows the current status of all regions."
printf "As a final step once you have verified you have no other EC2-Classic resources, "
printf "please open a support case and request your account be converted to VPC-Only as outlined in this document: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/vpc-migrate.html \n\n"
