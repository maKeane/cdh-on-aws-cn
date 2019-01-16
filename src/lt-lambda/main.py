#!/usr/bin/python
import logging
import boto3
import json
import random
import string
import cfnresponse

logger = logging.getLogger()
logger.setLevel(logging.INFO)
ec2client = boto3.client('ec2')
responseData = {}

def _decode(o):
    if isinstance(o, str) or isinstance(o, unicode):
        if o.lower() == 'true':
            return True
        elif o.lower() == 'false':
            return False
        else:
            try:
                return int(o)
            except ValueError:
                return o
    elif isinstance(o, dict):
        return {k: _decode(v) for k, v in o.items()}
    elif isinstance(o, list):
        return [_decode(v) for v in o]
    else:
        return o

def _convert_obj(o):
    return json.loads(json.dumps(o), object_hook=_decode)

def create_launch_template(event, context):
    try:
        respro = event['ResourceProperties']
        LaunchTemplate = _convert_obj(respro['LaunchTemplate'])
        LaunchTemplateName = LaunchTemplate['LaunchTemplateName'] + '-'
        LaunchTemplateName += ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(10))

        response = ec2client.create_launch_template(
            LaunchTemplateName=LaunchTemplateName,
            VersionDescription=LaunchTemplate['VersionDescription'],
            LaunchTemplateData=LaunchTemplate['LaunchTemplateData'])
        responseData['LaunchTemplateId'] = response['LaunchTemplate']['LaunchTemplateId']
        responseData['LaunchTemplateName'] = response['LaunchTemplate']['LaunchTemplateName']
        newTemplateId = response['LaunchTemplate']['LaunchTemplateId']
        cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, newTemplateId)
    except Exception as inst:
        logger.error(inst)
        cfnresponse.send(event, context, cfnresponse.FAILED, responseData)

def delete_launch_template(event, context):
    try:
        PhysicalResourceId = event['PhysicalResourceId']
        response = ec2client.delete_launch_template(LaunchTemplateId=PhysicalResourceId)
        templateId = response['LaunchTemplate']['LaunchTemplateId']
        cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, templateId)
    except Exception as inst:
        logger.error(inst)
        cfnresponse.send(event, context, cfnresponse.FAILED, responseData)

def lambda_handler(event, context):
    if event['RequestType'] == 'Delete':
        delete_launch_template(event, context)
    else:
        create_launch_template(event, context)
