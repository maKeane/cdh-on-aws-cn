#!/bin/bash

### get db parameters ###
echo "Get parameters from SSM parameter store ... "
DBEndpoint=`aws ssm get-parameter --name "/cdh/db/endpoint" | jq -r ".Parameter.Value"`
AMonPassword=`aws ssm get-parameter --name "/cdh/db/amon-pwd" | jq -r ".Parameter.Value"`
DBUser=`aws ssm get-parameter --name "/cdh/db/admin-user" | jq -r ".Parameter.Value"`
DBAdminPassword=`aws ssm get-parameter --name "/cdh/db/admin-pwd" | jq -r ".Parameter.Value"`      
DBSCMPassword=`aws ssm get-parameter --name "/cdh/db/scm-pwd" | jq -r ".Parameter.Value"`      
DBHivePassword=`aws ssm get-parameter --name "/cdh/db/hive-pwd" | jq -r ".Parameter.Value"`      
DBHuePassword=`aws ssm get-parameter --name "/cdh/db/hue-pwd" | jq -r ".Parameter.Value"`      
DBOoziePassword=`aws ssm get-parameter --name "/cdh/db/oozie-pwd" | jq -r ".Parameter.Value"`      

### set up scm db ###
echo "Setup scm db ... "
systemctl stop cloudera-scm-agent
systemctl stop cloudera-scm-server
mysql -h${DBEndpoint} -u${DBUser} -p${DBAdminPassword} <<'EOF'
DROP DATABASE cm;
DROP USER scm;
FLUSH PRIVILEGES;
EOF
/usr/share/cmf/schema/scm_prepare_database.sh mysql cm -h${DBEndpoint} -u${DBUser} -p${DBAdminPassword} --scm-host % scm ${DBSCMPassword}

### start cloudera server and agent ###
echo "Start cloudera server and agent ... "
systemctl enable cloudera-scm-server
systemctl enable cloudera-scm-agent
systemctl start cloudera-scm-server
systemctl start cloudera-scm-agent

### wait for cloudera-scm-server ready ###
echo -n "Waiting for cloudera-scm-server ready "
while ! curl --output /dev/null --silent --head --fail http://localhost:7180;
    do sleep 5 && echo -n .;
done;
sleep 10
echo " done"

### update cm-host parameter strore ###
echo "Update cm-host ... "
CMHost=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`
aws ssm put-parameter --name "/cdh/cm/host" --type "String" --value ${CMHost} --overwrite > /dev/null

### setup Cloudera Management Service ###
echo "Setup Cloudera Management Service ... "
curl -s -o /tmp/cm-mgmt-svc-setup.py https://s3.cn-northwest-1.amazonaws.com.cn/whe-pub/cloudera/scripts/cm-mgmt-svc-setup.py
python /tmp/cm-mgmt-svc-setup.py -c ${CMHost} -p 7180 -a admin -m ${DBEndpoint} -w ${AMonPassword}

### launch EC2 fleet for CDH nodes ###
echo "Launch EC2 fleet for CDH nodes ... "
curl -s -o /tmp/ec2-fleet.json https://s3.cn-northwest-1.amazonaws.com.cn/whe-pub/cloudera/scripts/ec2-fleet.json
FleetID=`aws ec2 create-fleet --cli-input-json file:///tmp/ec2-fleet.json | jq -r ".FleetId"`
aws ssm put-parameter --name "/cdh/fleet/id" --type "String" --value ${FleetID} --overwrite > /dev/null

# wait for fleet instance ready ###
echo -n "Waiting for instances ready "
while [ `aws ec2 describe-fleet-instances  --fleet-id ${FleetID} | jq -r '.ActiveInstances | length'` -lt 4 ];
    do sleep 5 && echo -n .;
done
echo " done"

### wait for CDH host ready ###
echo -n "Waiting for CM host ready "
while [ `curl -s http://admin:admin@localhost:7180/api/v12/hosts?view=full | jq -r '[.items[] | select(.healthSummary == "GOOD")] | length'` -lt 4 ];
    do sleep 5 && echo -n .;
done
echo " done"

### get host name of each spot instance ###
echo "Get host name of each spot instance ... "
SpotInstances=(`aws ec2 describe-fleet-instances  --fleet-id ${FleetID} | jq -r '.ActiveInstances[].InstanceId'`)
HostNameNode1=`aws ec2 describe-instances --instance-id ${SpotInstances[0]} --query 'Reservations[].Instances[].PrivateDnsName' --output text`
HostNameNode2=`aws ec2 describe-instances --instance-id ${SpotInstances[1]} --query 'Reservations[].Instances[].PrivateDnsName' --output text`
HostDataNodes=`aws ec2 describe-instances --instance-id ${SpotInstances[2]} ${SpotInstances[3]} --query 'Reservations[].Instances[].PrivateDnsName' --output text | tr "\t" ","`

### create cluster ###
echo "Create cluster ... "
curl -s -o /tmp/cluster_template.json https://s3.cn-northwest-1.amazonaws.com.cn/whe-pub/cloudera/scripts/cluster_template.json
jq -n \
  --arg host_cm $CMHost \
  --arg host_name_node1 $HostNameNode1 \
  --arg host_name_node2 $HostNameNode2 \
  --arg host_data_nodes $HostDataNodes \
  --arg host_database $DBEndpoint \
  --arg hive_db_password $DBHivePassword \
  --arg hue_db_password $DBHuePassword \
  --arg oozie_db_password $DBOoziePassword \
  -f /tmp/cluster_template.json > /tmp/cluster_template_inst.json
curl -s -X POST -H "Content-Type: application/json" -d @/tmp/cluster_template_inst.json http://admin:admin@localhost:7180/api/v12/cm/importClusterTemplate

echo "DONE!"
