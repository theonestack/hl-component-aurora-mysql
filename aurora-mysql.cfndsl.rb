CloudFormation do

  Description "#{component_name} - #{component_version}"

  az_conditions_resources('SubnetPersistence', maximum_availability_zones)

  Condition("UseUsernameAndPassword", FnEquals(Ref(:SnapshotID), ''))
  Condition("UseSnapshotID", FnNot(FnEquals(Ref(:SnapshotID), '')))


  tags = []
  tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }

  extra_tags.each { |key,value| tags << { Key: key, Value: value } } if defined? extra_tags

  SecretsManager_Secret(:SecretCredentials) do
    GenerateSecretString ({
      SecretStringTemplate: "{\"username\":\"#{secret_username}\"}",
      GenerateStringKey: "password",
      ExcludeCharacters: "\"@'`/\\"
    })
  end if defined? secrets_manager


  case kms_key_id
  when true
    kms_key = Ref('KmsKeyId')
  when 'create'
    kms_key = FnGetAtt('KmsKey', 'Arn')

    KMS_Alias(:KmsAlias) do
      AliasName FnSub("alias/${EnvironmentName}-${ProjectName}aurora-mysql")
      TargetKeyId Ref('KmsKey')
    end

    KMS_Key(:KmsKey) do
      Description 'KMS key for aurora'
      DeletionPolicy 'Retain'
      PendingWindowInDays defined?(key_deletion_time) ? key_deletion_time : 7
      KeyPolicy({
        Version: "2012-10-17",
        Statement: [
          {
            Sid: "Allow administration of the key",
            Effect: "Allow",
            Principal: {"AWS": FnSub("arn:aws:iam::${AWS::AccountId}:root")},
            Action: ([
              "kms:Create*",
              "kms:Describe*",
              "kms:Enable*",
              "kms:List*",
              "kms:Put*",
              "kms:Update*",
              "kms:Revoke*",
              "kms:Disable*",
              "kms:Get*",
              "kms:Delete*",
              "kms:ScheduleKeyDeletion",
              "kms:CancelKeyDeletion"
            ]),
            Resource: "*"
          },
          {
            Sid: "Allow use of the key",
            Effect: "Allow",
            Principal: {"AWS": FnSub("arn:aws:iam::${AWS::AccountId}:role/*/*/*")},
            Condition: {
              StringEquals: {
                "kms:ViaService": FnSub("rds.${AWS::Region}.amazonaws.com")
              }
            },
            Action: ([
              "kms:Encrypt",
              "kms:Decrypt",
              "kms:ReEncrypt*",
              "kms:GenerateDataKey*",
              "kms:DescribeKey"
            ]),
            Resource: "*"
          }
        ]
      })
    end

  end if defined? kms_key_id

  EC2_SecurityGroup(:SecurityGroup) do
    VpcId Ref('VPCId')
    GroupDescription FnJoin(' ', [ Ref(:EnvironmentName), component_name, 'security group' ])
    SecurityGroupIngress sg_create_rules(security_group, ip_blocks) if defined? security_group
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'security-group' ])}]
    Metadata({
      cfn_nag: {
        rules_to_suppress: [
          { id: 'F1000', reason: 'plan is to remove these security groups or make them conditional' }
        ]
      }
    })
  end

  RDS_DBSubnetGroup(:DBClusterSubnetGroup) {
    SubnetIds az_conditional_resources('SubnetPersistence', maximum_availability_zones)
    DBSubnetGroupDescription FnJoin(' ', [ Ref(:EnvironmentName), component_name, 'subnet group' ])
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'subnet-group' ])}]
  }

  RDS_DBClusterParameterGroup(:DBClusterParameterGroup) {
    Description FnJoin(' ', [ Ref(:EnvironmentName), component_name, 'cluster parameter group' ])
    Family family
    Parameters cluster_parameters if defined? cluster_parameters
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'cluster-parameter-group' ])}]
  }

  instance_username = defined?(secrets_manager) ? FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:username}}' ]) : FnJoin('', [ '{{resolve:ssm:', master_login['username_ssm_param'], ':1}}' ])
  instance_password = defined?(secrets_manager) ? FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:password}}' ]) : FnJoin('', [ '{{resolve:ssm-secure:', master_login['password_ssm_param'], ':1}}' ])

  RDS_DBCluster(:DBCluster) {
    Engine engine
    if engine_mode == 'serverless'
      EngineMode engine_mode
      ScalingConfiguration({
        AutoPause: Ref('AutoPause'),
        MinCapacity: Ref('MinCapacity'),
        MaxCapacity: Ref('MaxCapacity'),
        SecondsUntilAutoPause: Ref('SecondsUntilAutoPause')
      })
    end
    DatabaseName db_name if defined? db_name
    DBClusterParameterGroupName Ref(:DBClusterParameterGroup)
    SnapshotIdentifier FnIf('UseSnapshotID',Ref(:SnapshotID), Ref('AWS::NoValue'))
    DBSubnetGroupName Ref(:DBClusterSubnetGroup)
    VpcSecurityGroupIds [ Ref(:SecurityGroup) ]
    MasterUsername  FnIf('UseUsernameAndPassword', instance_username, Ref('AWS::NoValue'))
    MasterUserPassword  FnIf('UseUsernameAndPassword', instance_password, Ref('AWS::NoValue'))
    StorageEncrypted storage_encrypted if defined? storage_encrypted
    KmsKeyId kms_key if defined? kms_key_id
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'cluster' ])}]
  }

  if engine_mode == 'provisioned'
    Condition("EnableReader", FnEquals(Ref("EnableReader"), 'true'))
    RDS_DBParameterGroup(:DBInstanceParameterGroup) {
      Description FnJoin(' ', [ Ref(:EnvironmentName), component_name, 'instance parameter group' ])
      Family family
      Parameters instance_parameters if defined? instance_parameters
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'instance-parameter-group' ])}]
    }

    RDS_DBInstance(:DBClusterInstanceWriter) {
      DBSubnetGroupName Ref(:DBClusterSubnetGroup)
      DBParameterGroupName Ref(:DBInstanceParameterGroup)
      DBClusterIdentifier Ref(:DBCluster)
      Engine engine
      PubliclyAccessible 'false'
      DBInstanceClass Ref(:WriterInstanceType)
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'writer-instance' ])}]
    }

    RDS_DBInstance(:DBClusterInstanceReader) {
      Condition(:EnableReader)
      DBSubnetGroupName Ref(:DBClusterSubnetGroup)
      DBParameterGroupName Ref(:DBInstanceParameterGroup)
      DBClusterIdentifier Ref(:DBCluster)
      Engine engine
      PubliclyAccessible 'false'
      DBInstanceClass Ref(:ReaderInstanceType)
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), component_name, 'reader-instance' ])}]
    }

    Route53_RecordSet(:DBClusterReaderRecord) {
      Condition(:EnableReader)
      HostedZoneName FnJoin('', [ Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.'])
      Name FnJoin('', [ hostname_read_endpoint, '.', Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.' ])
      Type 'CNAME'
      TTL '60'
      ResourceRecords [ FnGetAtt('DBCluster','ReadEndpoint.Address') ]
    }
  end

  Route53_RecordSet(:DBHostRecord) {
    HostedZoneName FnJoin('', [ Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.'])
    Name FnJoin('', [ hostname, '.', Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.' ])
    Type 'CNAME'
    TTL '60'
    ResourceRecords [ FnGetAtt('DBCluster','Endpoint.Address') ]
  }



end
