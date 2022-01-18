#!/usr/bin/python3

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



import getopt
import os
import sys
from datetime import datetime
from multiprocessing import Process

import boto3
import boto3.session
import botocore.exceptions
from botocore.config import Config


# Parses the input arguments


def argparser(argv):
    try:
        opts, args = getopt.getopt(argv, "hop:r:e:", ["help", "organization", "profile=", "rolename=", "externalid="])
    except getopt.GetoptError:
        print('This only accepts -h --help, -o --organization, -p --profile <comma delimited list of profile names>')
        sys.exit(2)
    orgarg = False
    profilearg = False
    orgdict = {}
    for opt, arg in opts:
        if opt == '-h':
            print('You can use the following arguments, -o to run against all accounts in an organization, or -p '
                  '<comma delimited list of profile names> to run using locally configured profiles configured using '
                  'the AWS CLI. If you run this without any arguments it will run against the default credentials '
                  'configured using the AWS CLI or the instance role if running on EC2.')
            sys.exit()
        elif opt in ("-o", "--organization"):
            orgarg = True
        elif opt in ("-p", "--profile"):
            profiledict = arg.split(',')
            profilearg = True
        elif opt in ("-r", "--rolename"):
            orgdict['rolename'] = arg
        elif opt in ("-e", "--externalid"):
            orgdict['externalid'] = arg
    if orgarg:
        return orgdict
    elif profilearg:
        return profiledict
    else:
        return str('default')


# Delete File function


def deletefile(filename):
    if os.path.exists(filename):
        os.remove(filename)
        return True
    else:
        return False


# File Concatenation function


def fileconcatenator(executionprefixobj, regionnameobj, filename, outputobj):
    readfile = open(executionprefixobj + regionnameobj + filename, 'r')
    outputobj.write(readfile.read())
    readfile.close()
    deletefile(executionprefixobj + regionnameobj + filename)


# Writes the results to a regional file for later aggregation


def filewriter(prefixobj, efileobj, inputlist, currentregionnameobj, suffixobj):
    writefile = open(prefixobj + currentregionnameobj + suffixobj, 'a')
    try:
        for line in inputlist:
            writefile.write(currentregionnameobj + ', ' + line + '\n')
    except Exception as e:
        efileobj.write(suffixobj + ' for ' + currentregionnameobj + ' failed to write. Error: ' + str(e))
    finally:
        writefile.close()


# Gets the Classic Platform Status for the region


def classicplatformstatus(ec2client, errorfileobj, currentregion):
    try:
        accountattributes = ec2client.describe_account_attributes(
            AttributeNames=[
                'supported-platforms',
            ]
        )
        classicenabled = False
        for attributes in accountattributes['AccountAttributes'][0]['AttributeValues']:
            if attributes['AttributeValue'] == 'EC2':
                classicenabled = True
        if classicenabled:
            return 'Enabled'
        else:
            return 'Disabled'
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_account_attributes in ' + currentregion + ' returned: ' + str(error))
        return 'UNKNOWN'
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_account_attributes in ' + currentregion + ' returned: ' + str(error))
        return 'UNKNOWN'
    except Exception as error:
        errorfileobj.write('describe_account_attributes in ' + currentregion + ' returned: ' + str(error))
        return 'UNKNOWN'


# Gets all Classic EIPs


def classiceips(ec2client, errorfileobj, currentregion):
    try:
        eips = ec2client.describe_addresses(
            Filters=[
                {
                    'Name': 'domain',
                    'Values': [
                        'standard',
                    ]
                },
            ]
        )
        eiplist = list()
        for address in eips['Addresses']:
            eiplist.append(address['PublicIp'])
        return eiplist
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_addresses in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_addresses in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_addresses in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic EC2 Instances


def classicec2instances(ec2client, errorfileobj, currentregion):
    try:
        paginator = ec2client.get_paginator('describe_instances')
        operation_parameters = {'Filters': [
            {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'shutting-down', 'stopping', 'stopped']}]}
        page_iterator = paginator.paginate(**operation_parameters)
        classicinstances = list()
        for page in page_iterator:
            for reservation in page['Reservations']:
                for instance in reservation['Instances']:
                    if 'VpcId' not in instance.keys():
                        classicinstances.append(instance['InstanceId'])
        return classicinstances
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_instances in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_instances in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_instances in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic Security Groups


def classicsecuritygroups(ec2client, errorfileobj, currentregion):
    try:
        paginator = ec2client.get_paginator('describe_security_groups')
        page_iterator = paginator.paginate()
        classicsgs = list()
        for page in page_iterator:
            for sgdata in page['SecurityGroups']:
                if 'VpcId' not in sgdata.keys():
                    classicsgs.append(sgdata['GroupId'])
        return classicsgs
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_security_groups in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_security_groups in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_security_groups in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all VPCs with ClassicLink Enabled


def classiclinks(ec2client, errorfileobj, currentregion):
    try:
        classiclinkvpcs = ec2client.describe_vpc_classic_link(
            Filters=[
                {
                    'Name': 'is-classic-link-enabled',
                    'Values': [
                        'true',
                    ]
                },
            ]
        )
        classiclinkvpcslist = list()
        for vpccl in classiclinkvpcs['Vpcs']:
            classiclinkvpcslist.append(vpccl['VpcId'])
        return classiclinkvpcslist
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_vpc_classic_link in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_vpc_classic_link in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_vpc_classic_link in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all ASGs without a VPC configured


def classicasgs(asgclient, errorfileobj, currentregion):
    try:
        paginator = asgclient.get_paginator('describe_auto_scaling_groups')
        page_iterator = paginator.paginate()
        classicasglist = list()
        for page in page_iterator:
            for asgdata in page['AutoScalingGroups']:
                if asgdata['VPCZoneIdentifier'] == '':
                    classicasglist.append(asgdata['AutoScalingGroupARN'])
        return classicasglist
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_auto_scaling_groups in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_auto_scaling_groups in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_auto_scaling_groups in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all CLBs running in EC2-Classic


def classicclbs(elbclient, errorfileobj, currentregion):
    try:
        paginator = elbclient.get_paginator('describe_load_balancers')
        page_iterator = paginator.paginate()
        classicclblist = list()
        for page in page_iterator:
            for clbdata in page['LoadBalancerDescriptions']:
                if 'VPCId' not in clbdata.keys():
                    classicclblist.append(clbdata['LoadBalancerName'])
        return classicclblist
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_load_balancers in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_load_balancers in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_load_balancers in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic RDS instances


def classicrds(rdsclient, errorfileobj, currentregion):
    try:
        paginator = rdsclient.get_paginator('describe_db_instances')
        page_iterator = paginator.paginate()
        classicrdsinstances = list()
        for page in page_iterator:
            for instance in page['DBInstances']:
                if 'VpcSecurityGroups' not in instance.keys() or not instance['VpcSecurityGroups']:
                    classicrdsinstances.append(instance['DBInstanceArn'])
        return classicrdsinstances
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_db_instances in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_db_instances in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_db_instances in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic ElastiCache Clusters


def classicelasticache(ecclient, errorfileobj, currentregion):
    try:
        paginator = ecclient.get_paginator('describe_cache_clusters')
        page_iterator = paginator.paginate()
        classicecclusters = list()
        for page in page_iterator:
            for cluster in page['CacheClusters']:
                if 'CacheSubnetGroupName' not in cluster.keys():
                    classicecclusters.append(cluster['ARN'])
        return classicecclusters
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_cache_clusters in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_cache_clusters in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_cache_clusters in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic Redshift Clusters


def classicredshift(rsclient, errorfileobj, currentregion):
    try:
        paginator = rsclient.get_paginator('describe_clusters')
        page_iterator = paginator.paginate()
        classicrsclusters = list()
        for page in page_iterator:
            for cluster in page['Clusters']:
                if 'VpcId' not in cluster.keys():
                    classicrsclusters.append(cluster['ClusterIdentifier'])
        return classicrsclusters
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_clusters in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_clusters in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_clusters in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic ElasticBeanstalk Environments


def classicbeanstalk(ebclient, errorfileobj, currentregion):
    try:
        paginator = ebclient.get_paginator('describe_environments')
        operation_parameters = {'IncludeDeleted': False}
        page_iterator = paginator.paginate(**operation_parameters)
        ebclusters = list()
        for page in page_iterator:
            for environment in page['Environments']:
                configsettings = ebclient.describe_configuration_settings(
                    ApplicationName=environment['ApplicationName'],
                    EnvironmentName=environment['EnvironmentName']
                )
                vpcset = False
                for setting in configsettings['ConfigurationSettings']:
                    for option in setting['OptionSettings']:
                        if option['Namespace'] == 'aws:ec2:vpc' and option['OptionName'] == 'VPCId' and 'Value' in \
                                option.keys():
                            vpcset = True
                if not vpcset:
                    ebclusters.append(str(environment['ApplicationName'] + ', ' + environment['EnvironmentName']))
        return ebclusters
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('classicbeanstalk() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('classicbeanstalk() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('classicbeanstalk() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic Data Pipelines


def classicdatapipelines(dpclient, errorfileobj, currentregion):
    try:
        paginator = dpclient.get_paginator('list_pipelines')
        page_iterator = paginator.paginate()
        classicpipelines = list()
        for page in page_iterator:
            for pipeline in page['pipelineIdList']:
                definition = dpclient.get_pipeline_definition(
                    pipelineId=pipeline['id']
                )
                hasclassicresource = False
                for plobject in definition['pipelineObjects']:
                    for field in plobject['fields']:
                        if field['key'] == 'type' and field['stringValue'] == 'Ec2Resource':
                            instanceisclassic = True
                            for fielditerator2 in plobject['fields']:
                                if fielditerator2['key'] == 'subnetId' and fielditerator2['stringValue']:
                                    instanceisclassic = False
                            if instanceisclassic:
                                hasclassicresource = True
                if hasclassicresource:
                    classicpipelines.append(pipeline['id'])
        return classicpipelines
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('classicdatapipelines() in ' + currentregion + ' returned: ' + str(error))
        return('UNKNOWN', )
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('classicdatapipelines() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('classicdatapipelines() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get all Classic EMR Clusters


def classicemr(emrclient, errorfileobj, currentregion):
    try:
        paginator = emrclient.get_paginator('list_clusters')
        operation_parameters = {'ClusterStates': ['STARTING', 'BOOTSTRAPPING', 'RUNNING', 'WAITING']}
        page_iterator = paginator.paginate(**operation_parameters)
        emrclusters = list()
        for page in page_iterator:
            for cluster in page['Clusters']:
                clusterinfo = emrclient.describe_cluster(
                    ClusterId=cluster['Id']
                )
                if not clusterinfo['Cluster']['Ec2InstanceAttributes']['RequestedEc2SubnetIds'] and \
                        'Ec2SubnetId' not in clusterinfo['Cluster']['Ec2InstanceAttributes'].keys():
                    emrclusters.append(cluster['Id'])
        return emrclusters
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('classicemr() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('classicemr() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('classicemr() in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Get OpsWorks Stacks with Classic Resources


def classicopswork(owclient, errorfileobj, currentregion):
    try:
        classicstacks = list()
        stacks = owclient.describe_stacks()
        for stack in stacks['Stacks']:
            if 'VpcId' not in stack.keys():
                classicstacks.append(stack['StackId'])
        return classicstacks
    except botocore.exceptions.ClientError as error:
        errorfileobj.write('describe_stacks in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except botocore.exceptions.ParamValidationError as error:
        errorfileobj.write('describe_stacks in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)
    except Exception as error:
        errorfileobj.write('describe_stacks in ' + currentregion + ' returned: ' + str(error))
        return ('UNKNOWN',)


# Defines the main function on a per region level


def getclassicresources(prefix, region, datapipelineregionlist, creds):
    config = Config(
        region_name=region,
        retries={
            'max_attempts': 10,
            'mode': 'standard'
        }
    )

    # Parse creds parameter to determine if using provided access creds, a cred profile or the default system creds.

    if 'secretkey' not in creds.keys() and 'sessiontoken' not in creds.keys() and 'accesskey' not in creds.keys() and \
            'profile' not in creds.keys():
        session = boto3.session.Session()
    elif 'secretkey' in creds.keys() and 'sessiontoken' in creds.keys() and 'accesskey' in creds.keys():
        session = boto3.session.Session(
            aws_access_key_id=creds['accesskey'],
            aws_secret_access_key=creds['secretkey'],
            aws_session_token=creds['sessiontoken']
        )
    elif 'profile' in creds.keys():
        session = boto3.session.Session(
            profile_name=creds['profile']
        )
    else:
        print('We received a partial authentication session but not all attributes included when calling '
              'getclassicresources(). We proceeded using the system configured credentials. The keys included were: '
              '' + str(creds.keys()))
        session = boto3.session.Session()

    ec2obj = session.client('ec2', config=config)
    asgobj = session.client('autoscaling', config=config)
    elbobj = session.client('elb', config=config)
    rdsobj = session.client('rds', config=config)
    ecobj = session.client('elasticache', config=config)
    rsobj = session.client('redshift', config=config)
    ebobj = session.client('elasticbeanstalk', config=config)
    emrobj = session.client('emr', config=config)
    owobj = session.client('opsworks', config=config)

    errorfile = open(prefix + region + '_errors.txt', 'a')

    # Classic Platform Status
    print('Checking the Classic platform status in ' + region)

    platformfile = open(prefix + region + '_Classic_Platform_Status.csv', 'a')
    try:
        platformfile.write(region + ', ' + classicplatformstatus(ec2obj, errorfile, region) + '\n')
    except Exception as e:
        errorfile.write('Platform Status for ' + region + ' failed to write. Error: ' + str(e))
    finally:
        platformfile.close()

    # Classic EIPs
    print('Checking for EIPs in ' + region)
    filewriter(prefix, errorfile, classiceips(ec2obj, errorfile, region), region, '_Classic_EIPs.csv')

    # Classic EC2 Instances
    print('Checking for Classic EC2 Instances in ' + region)
    filewriter(prefix, errorfile, classicec2instances(ec2obj, errorfile, region), region, '_Classic_EC2_Instances.csv')

    # Classic Security Groups
    print('Checking for Classic Security Groups in ' + region)
    filewriter(prefix, errorfile, classicsecuritygroups(ec2obj, errorfile, region), region, '_Classic_SGs.csv')

    # ClassicLink VPCs
    print('Checking for VPCs with ClassicLink enabled in ' + region)
    filewriter(prefix, errorfile, classiclinks(ec2obj, errorfile, region), region, '_Classic_ClassicLink_VPCs.csv')

    # Classic Auto Scaling Groups
    print('Checking for AutoScaling Groups configured for Classic in ' + region)
    filewriter(prefix, errorfile, classicasgs(asgobj, errorfile, region), region, '_Classic_Auto_Scaling_Groups.csv')

    # Classic CLBs
    print('Checking for Classic Load Balancers running in EC2-Classic in ' + region)
    filewriter(prefix, errorfile, classicclbs(elbobj, errorfile, region), region, '_Classic_CLBs.csv')

    # Classic RDS Instances
    print('Checking for Classic RDS Instances in ' + region)
    filewriter(prefix, errorfile, classicrds(rdsobj, errorfile, region), region, '_Classic_RDS_Instances.csv')

    # Classic ElastiCache Clusters
    print('Checking for Classic ElastiCache clusters in ' + region)
    filewriter(prefix, errorfile, classicelasticache(ecobj, errorfile, region), region,
               '_Classic_ElastiCache_Clusters.csv')

    # Classic Redshift Clusters
    print('Checking for Classic Redshift clusters in ' + region)
    filewriter(prefix, errorfile, classicredshift(rsobj, errorfile, region), region, '_Classic_Redshift_Clusters.csv')

    # Classic Elastic Beanstalk Environments
    print('Checking for Classic Elastic BeanStalk Environments in ' + region)
    filewriter(prefix, errorfile, classicbeanstalk(ebobj, errorfile, region), region,
               '_Classic_ElasticBeanstalk_Applications_Environments.csv')

    # classic EMR Clusters
    print('Checking for Classic EMR clusters in ' + region)
    filewriter(prefix, errorfile, classicemr(emrobj, errorfile, region), region, '_Classic_EMR_Clusters.csv')

    # Classic OpsWorks Stacks
    print('Checking for Classic OpsWorks stacks in ' + region)
    filewriter(prefix, errorfile, classicopswork(owobj, errorfile, region), region, '_Classic_OpsWorks_Stacks.csv')

    # Classic Data Pipelines
    if region in datapipelineregionlist:
        print('Checking for Classic Data Pipelines in ' + region)
        dpobj = session.client('datapipeline', config=config)
        filewriter(prefix, errorfile, classicdatapipelines(dpobj, errorfile, region), region,
                   '_Classic_DataPipelines.csv')

    errorfile.close()


# Loop through regions and spawn a process for each region


def loopregions(classicregionslist, datapipelineregionslist, creds):
    executionprefix = datetime.now()
    executionprefix = executionprefix.strftime("%d-%m-%Y-%H-%M-%S_")

    if 'secretkey' not in creds.keys() and 'sessiontoken' not in creds.keys() and 'accesskey' not in creds.keys() and \
            'profile' not in creds.keys():
        session = boto3.session.Session()
        sts = session.client('sts')
        accountid = sts.get_caller_identity()
        executionprefix = accountid['Account'] + '/' + executionprefix
        if not os.path.exists(accountid['Account']):
            os.mkdir(accountid['Account'])
        processes = []
        for regionname in classicregionslist:
            process = Process(target=getclassicresources, args=(executionprefix, regionname,
                                                                datapipelineregionslist, {}))
            processes.append(process)
        for process in processes:
            process.start()
        for process in processes:
            process.join()
        concatenateregions(classicregionslist, datapipelineregionslist, executionprefix)
        return True
    elif 'secretkey' in creds.keys() and 'sessiontoken' in creds.keys() and 'accesskey' in creds.keys():
        session = boto3.session.Session(
            aws_access_key_id=creds['accesskey'],
            aws_secret_access_key=creds['secretkey'],
            aws_session_token=creds['sessiontoken']
        )
        sts = session.client('sts')
        accountid = sts.get_caller_identity()
        executionprefix = accountid['Account'] + '/' + executionprefix
        if not os.path.exists(accountid['Account']):
            os.mkdir(accountid['Account'])
        processes = []
        for regionname in classicregionslist:
            process = Process(target=getclassicresources, args=(executionprefix, regionname,
                                                                datapipelineregionslist,
                                                                creds))
            processes.append(process)
            for process in processes:
                process.start()
            for process in processes:
                process.join()
        concatenateregions(classicregionslist, datapipelineregionslist, executionprefix)
        return True
    elif 'profile' in creds.keys():
        session = boto3.session.Session(
            profile_name=creds['profile']
        )
        sts = session.client('sts')
        accountid = sts.get_caller_identity()
        executionprefix = accountid['Account'] + '/' + executionprefix
        if not os.path.exists(accountid['Account']):
            os.mkdir(accountid['Account'])
        processes = []
        for regionname in classicregionslist:
            process = Process(target=getclassicresources, args=(executionprefix, regionname,
                                                                datapipelineregionslist, creds))
            processes.append(process)
            for process in processes:
                process.start()
            for process in processes:
                process.join()
        concatenateregions(classicregionslist, datapipelineregionslist, executionprefix)
        return True
    else:
        print('We received a partial authentication session but not all attributes included when calling '
              'getclassicresources(). We proceeded using the system configured credentials. The keys included were: '
              '' + str(creds.keys()))
        session = boto3.session.Session()
        sts = session.client('sts')
        accountid = sts.get_caller_identity()
        executionprefix = accountid['Account'] + '/' + executionprefix
        if not os.path.exists(accountid['Account']):
            os.mkdir(accountid['Account'])
        processes = []
        for regionname in classicregionslist:
            process = Process(target=getclassicresources, args=(executionprefix, regionname,
                                                                datapipelineregionslist, {}))
            processes.append(process)
            for process in processes:
                process.start()
            for process in processes:
                process.join()
        concatenateregions(classicregionslist, datapipelineregionslist, executionprefix)
        return True


# Concatenates all regional files into single file per service


def concatenateregions(classicregionslist, datapipelineregionslist, executionprefix):
    platformoutput = open(executionprefix + 'Classic_Platform_Status.csv', 'a')
    eipoutput = open(executionprefix + 'Classic_EIPs.csv', 'a')
    ec2output = open(executionprefix + 'Classic_EC2_Instances.csv', 'a')
    sgoutput = open(executionprefix + 'Classic_SGs.csv', 'a')
    clvpcoutput = open(executionprefix + 'Classic_ClassicLink_VPCs.csv', 'a')
    asgoutput = open(executionprefix + 'Classic_Auto_Scaling_Groups.csv', 'a')
    clboutput = open(executionprefix + 'Classic_CLBs.csv', 'a')
    rdsoutput = open(executionprefix + 'Classic_RDS_Instances.csv', 'a')
    ecoutput = open(executionprefix + 'Classic_ElastiCache_Clusters.csv', 'a')
    rsoutput = open(executionprefix + 'Classic_Redshift_Clusters.csv', 'a')
    eboutput = open(executionprefix + 'Classic_ElasticBeanstalk_Applications_Environments.csv', 'a')
    emroutput = open(executionprefix + 'Classic_EMR_Clusters.csv', 'a')
    owoutput = open(executionprefix + 'Classic_OpsWorks_Stacks.csv', 'a')
    dpoutput = open(executionprefix + 'Classic_DataPipelines.csv', 'a')
    erroroutput = open(executionprefix + 'Errors.txt', 'a')

    for regionname in classicregionslist:

        # Platform Status concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_Platform_Status.csv', platformoutput)

        # EIP Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_EIPs.csv', eipoutput)

        # EC2 Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_EC2_Instances.csv', ec2output)

        # SG Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_SGs.csv', sgoutput)

        # ClassicLink Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_ClassicLink_VPCs.csv', clvpcoutput)

        # ASG Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_Auto_Scaling_Groups.csv', asgoutput)

        # CLB Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_CLBs.csv', clboutput)

        # RDS Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_RDS_Instances.csv', rdsoutput)

        # ElastiCache Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_ElastiCache_Clusters.csv', ecoutput)

        # Redshift Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_Redshift_Clusters.csv', rsoutput)

        # Elastic Beanstalk Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_ElasticBeanstalk_Applications_Environments.csv',
                         eboutput)

        # EMR Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_EMR_Clusters.csv', emroutput)

        # OpsWorks Concatenate
        fileconcatenator(executionprefix, regionname, '_Classic_OpsWorks_Stacks.csv', owoutput)

        # Datapipelines Concatenate
        if regionname in datapipelineregionslist:
            fileconcatenator(executionprefix, regionname, '_Classic_DataPipelines.csv', dpoutput)

        # Errors Concatenate
        fileconcatenator(executionprefix, regionname, '_errors.txt', erroroutput)

    platformoutput.close()
    eipoutput.close()
    ec2output.close()
    sgoutput.close()
    clvpcoutput.close()
    asgoutput.close()
    clboutput.close()
    rdsoutput.close()
    ecoutput.close()
    rsoutput.close()
    eboutput.close()
    emroutput.close()
    owoutput.close()
    dpoutput.close()
    erroroutput.close()


# Main Function
def main(argresult):
    classicregions = ('us-east-1', 'us-west-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1', 'ap-southeast-2',
                      'ap-northeast-1', 'sa-east-1',)
    datapipelineregions = ('us-east-1', 'eu-west-1', 'ap-northeast-1', 'us-west-2', 'ap-southeast-2')

    creddict = {}

    if str(argresult) == 'default':
        loopregions(classicregions, datapipelineregions, {})
    elif type(argresult) is dict:
        orgclient = boto3.client('organizations')
        stsparentclient = boto3.client('sts')
        paginator = orgclient.get_paginator('list_accounts')
        page_iterator = paginator.paginate()
        accountslist = list()
        for page in page_iterator:
            for account in page['Accounts']:
                if account['Status'] == 'ACTIVE':
                    accountslist.append(account['Id'])
        if 'rolename' in argresult.keys():
            rolename = argresult['rolename']
        else:
            rolename = 'ec2-classic-resource-finder'

        if 'externalid' in argresult.keys():
            for account in accountslist:
                try:
                    rolearn = 'arn:aws:iam::' + account + ':role/' + rolename
                    accountstscred = stsparentclient.assume_role(
                        RoleArn=rolearn,
                        RoleSessionName='ec2-classic-resource-finder',
                        DurationSeconds=3600,
                        ExternalId=argresult['externalid']
                    )
                    creddict['accesskey'] = accountstscred['Credentials']['AccessKeyId']
                    creddict['secretkey'] = accountstscred['Credentials']['SecretAccessKey']
                    creddict['sessiontoken'] = accountstscred['Credentials']['SessionToken']
                    loopregions(classicregions, datapipelineregions, creddict)
                except Exception as e:
                    print('Error running for account '+str(account)+'. The error was: '+str(e))
        else:
            for account in accountslist:
                try:
                    rolearn = 'arn:aws:iam::' + account + ':role/' + rolename
                    accountstscred = stsparentclient.assume_role(
                        RoleArn=rolearn,
                        RoleSessionName='ec2-classic-resource-finder',
                        DurationSeconds=3600
                    )
                    creddict['accesskey'] = accountstscred['Credentials']['AccessKeyId']
                    creddict['secretkey'] = accountstscred['Credentials']['SecretAccessKey']
                    creddict['sessiontoken'] = accountstscred['Credentials']['SessionToken']
                    loopregions(classicregions, datapipelineregions, creddict)
                except Exception as e:
                    print('Error running for account '+str(account)+'. The error was: '+str(e))
    else:
        for profile in argresult:
            creddict['profile'] = profile
            loopregions(classicregions, datapipelineregions, creddict)


# Execute the main function

if __name__ == '__main__':
    main(argparser(sys.argv[1:]))
    print('finished')
