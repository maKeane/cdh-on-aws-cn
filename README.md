# 在AWS中国区部署CDH集群
## 在AWS上运行CDH的特点
1. 定时运行，按使用量付费
2. 使用AWS竞价实例节省费用
3. 使用S3作数据湖存储
4. 弹性扩容

## 部署架构
TODO: 架构图
1. S3存储桶，存放业务数据，如Hive表等。
2. RDS Aurora for MySQL，用来存放CDH需要的配置和元数据。
3. Cloudera Manager(CM)节点和CDH节点镜像AMI。
4. CM 节点，为保证集群不会被中断，采用按需实例。
5. CDH 节点，使用EC2 Fleet竞价队列以节省成本。
6. CloudWatch Event，用来定时触发和关闭集群。
7. Lambda函数，执行集群创建，部署，和终止。

## 部署流程
1. 安装Packer并创建CM和CDH节点AMI。
2. 准备VPC及相应的子网。
3. 创建RDS Aurora for MySQL数据库，创建CDH需要的数据库和账户，并将配置信息写入SSM Parameter Store中。
4. 创建CDH节点所需的Launch Template。
5. 创建Lambda函数
6. 创建CloudWatch Event以触发Lambda
