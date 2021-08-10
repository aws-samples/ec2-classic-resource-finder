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


while getopts ":r:f:e:" opt; do
    case ${opt} in
        r ) ROLENAME=$OPTARG
        ;;
        f ) FILETOEXEC=$OPTARG
        ;;
        e ) EXTERNALID=$OPTARG
        ;;
        \? ) echo "Usage: cmd [-r ROLE NAME] [-f BASH FILE TO EXECUTE] [-e STS EXTERNAL ID (OPTIONAL)]\n"
            exit 1
        ;;
    esac
done
ROLENAMEREGEX="^[A-Za-z0-9\_\+\=\,\.\@\-]{1,64}$" ## Regex pattern to validate a role name
if [[ ! $ROLENAME =~ $ROLENAMEREGEX ]] ## Validate RoleName input against the regex
    then printf "Please specify an accurate name of the IAM role to utilize in the input using -r.\n" ## If it doesnt match, print an error
    exit 1 ## and exit with a non success (non-zero) exit code
fi
if [ ! -f "$FILETOEXEC" ] || [[ ${#FILETOEXEC} -lt 2 ]] ## Make sure the file name input has a value and the file exists
    then printf "Please specific a file to execute.\n" ## If the file input is not valid, print an error
    exit 1 ## and exit with a non success (non-zero) exit code
fi
ROLESESSIONNAME=`aws sts get-caller-identity --output json 2> /dev/null| jq -r '.UserId' 2> /dev/null`  ##Get the current UserID to use in Role Session Name on STS-Assume Role
ROLESESSIONNAMEREGEX="^[A-Za-z0-9\_\+\=\,\.\@\-]{2,64}$" ## Regex pattern for a properly formatted Role Session Name
if [[ ! $ROLESESSIONNAME =~ $ROLESESSIONNAMEREGEX ]] ## If the Role session name does not fit the regex pattern
    then printf "We failed to get the current UserID or it did not meet the requirements to use in Role Session Name in STS Assume Role.\n" ## Print an error
    exit 1 ## and exit with a non success (non-zero) exit code
fi
for account in `aws organizations list-accounts --query 'Accounts[?Status==\`ACTIVE\`]' --region us-east-1 --output json 2> /dev/null | jq -r '.[] .Id' 2> /dev/null`  ## Get all active accounts in the organization
    do
    printf "\n# -------------------------------------------------------------------------\nRunning commands against account: $account\n# -------------------------------------------------------------------------\n"
    ROLEARN="arn:aws:iam::$account:role/$ROLENAME"  ##Based on the input role name and current account, compile the ARN
    if [[ ${#EXTERNALID} -ge 1 ]] ## If we have an external ID value then
        then ASSUMMEDROLE=`aws sts assume-role --role-arn $ROLEARN --role-session-name $ROLESESSIONNAME --external-id $EXTERNALID --region us-east-1 --output json 2> /dev/null` ## Assume Role with External ID
        else ASSUMMEDROLE=`aws sts assume-role --role-arn $ROLEARN --role-session-name $ROLESESSIONNAME --region us-east-1 --output json 2> /dev/null` ## Else assume role without External ID
    fi ## Finish the assume role process
    unset ROLEARN
    if [[ ${#ASSUMMEDROLE} -gt 10 ]]
        then
            ASSUMEDACCESSKEY=`jq -r '.Credentials .AccessKeyId' <<< $ASSUMMEDROLE 2> /dev/null` ##parse the Access Key
            ASSUMEDSECRETKEY=`jq -r '.Credentials .SecretAccessKey' <<< $ASSUMMEDROLE 2> /dev/null` ##parse the Secret Key
            ASSUMEDTOKEN=`jq -r '.Credentials .SessionToken' <<< $ASSUMMEDROLE 2> /dev/null` ##parse the session token
            unset ASSUMMEDROLE ## Unset the variable storing the full return from STS AssumeRole
            if [[ ${#ASSUMEDACCESSKEY} -gt 10 ]] && [[ ${#ASSUMEDSECRETKEY} -gt 10 ]] && [[ ${#ASSUMEDTOKEN} -gt 10 ]] ## Validate that we have a successfully parsed Access Key, Secret Key and Token
                then
                    accountdir="output"$account
                    if [ ! -d $accountdir ] ## If a directory for the current account doesn't exist:
                        then mkdir $accountdir ## Create a directory for the current account
                    fi
                    cd $accountdir ## Move into the directory for our current account
                    export AWS_ACCESS_KEY_ID=$ASSUMEDACCESSKEY ## Set the environmental variable for the Access Key ID
                    unset ASSUMEDACCESSKEY ## Unset the local variable for the Access Key
                    export AWS_SECRET_ACCESS_KEY=$ASSUMEDSECRETKEY ## Set the environmental variable for the Secret Key
                    unset ASSUMEDSECRETKEY ## Unset the local variable for the Secret Key
                    export AWS_SESSION_TOKEN=$ASSUMEDTOKEN ## Set the environmental variable for the Session Token
                    unset ASSUMEDTOKEN ## Unset the local variable for the Session Token
                    EXACTPATHREGEX="^\/"
                    if [[ $FILETOEXEC =~ $EXACTPATHREGEX ]] ## If the File to Exec input is an exact path (not relational) then:
                        then bash $FILETOEXEC ## Run the script in its exact path syntax
                        else bash ../$FILETOEXEC ## Move up a directory out of the directory we just created and run it from that context
                    fi
                    cd ../ ## Move back up 1 directory out of the directory for the account
                    printf "\n# -------------------------------------------------------------------------\nRunning commands against account: $account... Done \xe2\x9c\x85\n# -------------------------------------------------------------------------\n\n\n\n"
                else printf "\n# -------------------------------------------------------------------------\nAssume role for account account $account Failed \xe2\x9d\x8c\n# -------------------------------------------------------------------------\n\n\n\n"
            fi ## End of inner check for role values and execution
        else printf "\n# -------------------------------------------------------------------------\nAssume role for account account $account Failed \xe2\x9d\x8c\n# -------------------------------------------------------------------------\n\n\n\n"
    fi ## End of outer check for role values and execution
    unset ROLEARN ASSUMMEDROLE ASSUMEDACCESSKEY ASSUMEDSECRETKEY ASSUMEDTOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN ## Unset all variables used in the while loop so they dont carry across either outside of the loop or on an iteration where assume role fails. This may be redundant for some items, but that is ok.
done
unset opt ROLENAME FILETOEXEC EXTERNALID ROLESESSIONNAME ROLEARN ASSUMMEDROLE ASSUMEDACCESSKEY ASSUMEDSECRETKEY ASSUMEDTOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN ## Cleanup all the variables we set in the script. Again there may be redundancy here, but that is ok.
printf "We have completed running your script against all accounts found.\n"