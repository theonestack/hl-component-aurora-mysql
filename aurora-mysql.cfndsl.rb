CloudFormation do

  export = external_parameters.fetch(:export_name, external_parameters[:component_name])

  Description "#{export} - #{external_parameters[:component_version]}"

  Condition("UseUsernameAndPassword", FnEquals(Ref(:SnapshotID), ''))
  Condition("UseSnapshotID", FnNot(FnEquals(Ref(:SnapshotID), '')))
  Condition("EnablePerformanceInsights", FnEquals(Ref(:EnablePerformanceInsights), 'true'))
  Condition("EnableReplicaAutoScaling", FnAnd([FnEquals(Ref(:EnableReplicaAutoScaling), 'true'), FnEquals(Ref(:EnableReader), 'true')]))
  Condition("EnableCloudwatchLogsExports", FnNot(FnEquals(Ref(:EnableCloudwatchLogsExports), '')))

  tags = []
  tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }

  extra_tags = external_parameters.fetch(:extra_tags, {})
  extra_tags.each { |key,value| tags << { Key: FnSub(key), Value: FnSub(value) } }

  secrets_manager = external_parameters.fetch(:secret_username, false)
  if secrets_manager
    SecretsManager_Secret(:SecretCredentials) do
      GenerateSecretString ({
        SecretStringTemplate: "{\"username\":\"#{secrets_manager}\"}",
        GenerateStringKey: "password",
        ExcludeCharacters: "\"@'`/\\"
      })
    end
    Output(:SecretCredentials) {
      Value(Ref(:SecretCredentials))
      Export FnSub("${EnvironmentName}-#{export}-Secret")
    }
  end


  security_group = external_parameters.fetch(:security_group, [])
  ip_blocks = external_parameters.fetch(:ip_blocks, [])
  EC2_SecurityGroup(:SecurityGroup) do
    VpcId Ref('VPCId')
    GroupDescription FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'security group' ])
    SecurityGroupIngress sg_create_rules(security_group, ip_blocks) if (!security_group.empty? && !ip_blocks.empty?)
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'security-group' ])}]
    Metadata({
      cfn_nag: {
        rules_to_suppress: [
          { id: 'F1000', reason: 'plan is to remove these security groups or make them conditional' }
        ]
      }
    })
  end

  Output(:SecurityGroup) {
    Value(Ref(:SecurityGroup))
    Export FnSub("${EnvironmentName}-#{export}-security-group")
  }

  RDS_DBSubnetGroup(:DBClusterSubnetGroup) {
    SubnetIds Ref(:SubnetIds)
    DBSubnetGroupDescription FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'subnet group' ])
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'subnet-group' ])}]
  }

  RDS_DBClusterParameterGroup(:DBClusterParameterGroup) {
    Description FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'cluster parameter group' ])
    Family external_parameters[:family]
    Parameters external_parameters[:cluster_parameters]
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'cluster-parameter-group' ])}]
  }

  db_name = external_parameters.fetch(:db_name, '')
  storage_encrypted = external_parameters.fetch(:storage_encrypted, false)
  kms = external_parameters.fetch(:kms_key_id, false)
  instance_username = secrets_manager ? FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:username}}' ]) : FnJoin('', [ '{{resolve:ssm:', external_parameters[:master_login]['username_ssm_param'], ':1}}' ])
  instance_password = secrets_manager ? FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:password}}' ]) : FnJoin('', [ '{{resolve:ssm-secure:', external_parameters[:master_login]['password_ssm_param'], ':1}}' ])
  engine_version = external_parameters.fetch(:engine_version, nil)
  engine_mode = external_parameters.fetch(:engine_mode, nil)
  maintenance_window = external_parameters.fetch(:maintenance_window, nil)

  RDS_DBCluster(:DBCluster) {
    Engine external_parameters[:engine]
    EngineVersion engine_version unless engine_version.nil?
    
    EngineMode(external_parameters[:engine_mode] == 'serverlessv2' ? 'provisioned' : external_parameters[:engine_mode])

    PreferredMaintenanceWindow maintenance_window unless maintenance_window.nil?
    
    if engine_mode == 'serverless'
      EnableHttpEndpoint Ref(:EnableHttpEndpoint)
      ServerlessV2ScalingConfiguration({
        MinCapacity: Ref('MinCapacity'),
        MaxCapacity: Ref('MaxCapacity')
      })
    end

    if engine_mode == 'serverlessv2'
      ServerlessV2ScalingConfiguration({
        MinCapacity: Ref('MinCapacity'),
        MaxCapacity: Ref('MaxCapacity')
      })
    end
    DatabaseName db_name if !db_name.empty?
    DBClusterParameterGroupName Ref(:DBClusterParameterGroup)
    SnapshotIdentifier FnIf('UseSnapshotID',Ref(:SnapshotID), Ref('AWS::NoValue'))
    DBSubnetGroupName Ref(:DBClusterSubnetGroup)
    VpcSecurityGroupIds [ Ref(:SecurityGroup) ]
    MasterUsername  FnIf('UseUsernameAndPassword', instance_username, Ref('AWS::NoValue'))
    MasterUserPassword  FnIf('UseUsernameAndPassword', instance_password, Ref('AWS::NoValue'))
    StorageEncrypted storage_encrypted
    KmsKeyId Ref('KmsKeyId') if kms
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'cluster' ])}]

    if !external_parameters[:log_exports].nil?
      if (external_parameters[:log_exports].is_a?(Array) and external_parameters[:log_exports].size > 0)
        EnableCloudwatchLogsExports FnIf('EnableCloudwatchLogsExports', external_parameters[:log_exports], Ref('AWS::NoValue'))
      end
      if (external_parameters[:log_exports].is_a?(Hash) and external_parameters[:log_exports].keys[0].start_with?('Ref') and external_parameters[:log_exports].keys.size < 2)
        EnableCloudwatchLogsExports FnIf('EnableCloudwatchLogsExports', FnSplit(',',external_parameters[:log_exports]), Ref('AWS::NoValue'))
      end
    end
    
  }

  if engine_mode == 'serverless' || engine_mode == 'serverlessv2'
    RDS_DBInstance(:ServerlessDBInstance) {
      Engine external_parameters[:engine]
      DBInstanceClass 'db.serverless'
      DBClusterIdentifier Ref(:DBCluster)
      Tags tags
    }

  else
    Condition("EnableReader", FnEquals(Ref("EnableReader"), 'true'))
    RDS_DBParameterGroup(:DBInstanceParameterGroup) {
      Description FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'instance parameter group' ])
      Family external_parameters[:family]
      Parameters external_parameters[:instance_parameters]
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'instance-parameter-group' ])}]
    }

    RDS_DBInstance(:DBClusterInstanceWriter) {
      DBSubnetGroupName Ref(:DBClusterSubnetGroup)
      DBParameterGroupName Ref(:DBInstanceParameterGroup)
      DBClusterIdentifier Ref(:DBCluster)
      Engine external_parameters[:engine]
      PubliclyAccessible 'false'
      DBInstanceClass Ref(:WriterInstanceType)
      EnablePerformanceInsights Ref('EnablePerformanceInsights')
      PerformanceInsightsRetentionPeriod FnIf('EnablePerformanceInsights', Ref('PerformanceInsightsRetentionPeriod'), Ref('AWS::NoValue'))
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'writer-instance' ])}]
    }

    RDS_DBInstance(:DBClusterInstanceReader) {
      Condition(:EnableReader)
      DBSubnetGroupName Ref(:DBClusterSubnetGroup)
      DBParameterGroupName Ref(:DBInstanceParameterGroup)
      DBClusterIdentifier Ref(:DBCluster)
      Engine external_parameters[:engine]
      PubliclyAccessible 'false'
      DBInstanceClass Ref(:ReaderInstanceType)
      EnablePerformanceInsights Ref('EnablePerformanceInsights')
      PerformanceInsightsRetentionPeriod FnIf('EnablePerformanceInsights', Ref('PerformanceInsightsRetentionPeriod'), Ref('AWS::NoValue'))
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'reader-instance' ])}]
    }

    Route53_RecordSet(:DBClusterReaderRecord) {
      Condition(:EnableReader)
      HostedZoneName FnJoin('', [ Ref(:EnvironmentName), '.', Ref(:DnsDomain), '.' ])
      Name FnJoin('', [ external_parameters[:hostname_read_endpoint], '.', Ref(:EnvironmentName), '.', Ref(:DnsDomain), '.' ])
      Type 'CNAME'
      TTL '60'
      ResourceRecords [ FnGetAtt('DBCluster','ReadEndpoint.Address') ]
    }
  end

  Route53_RecordSet(:DBHostRecord) {
    HostedZoneName FnJoin('', [ Ref(:EnvironmentName), '.', Ref(:DnsDomain), '.' ])
    Name FnJoin('', [ external_parameters[:hostname], '.', Ref(:EnvironmentName), '.', Ref(:DnsDomain), '.' ])
    Type 'CNAME'
    TTL '60'
    ResourceRecords [ FnGetAtt('DBCluster','Endpoint.Address') ]
  }

  registry = {}
  service_discovery = external_parameters.fetch(:service_discovery, {})

  unless service_discovery.empty?
    ServiceDiscovery_Service(:ServiceRegistry) {
      NamespaceId Ref(:NamespaceId)
      Name service_discovery['name']  if service_discovery.has_key? 'name'
      DnsConfig({
        DnsRecords: [{
          TTL: 60,
          Type: 'CNAME'
        }],
        RoutingPolicy: 'WEIGHTED'
      })
      if service_discovery.has_key? 'healthcheck'
        HealthCheckConfig service_discovery['healthcheck']
      else
        HealthCheckCustomConfig ({ FailureThreshold: (service_discovery['failure_threshold'] || 1) })
      end
    }

    ServiceDiscovery_Instance(:RegisterInstance) {
      InstanceAttributes(
        AWS_INSTANCE_CNAME: FnGetAtt('DBCluster','Endpoint.Address')
      )
      ServiceId Ref(:ServiceRegistry)
    }

    Output(:ServiceRegistry) {
      Value(Ref(:ServiceRegistry))
      Export FnSub("${EnvironmentName}-#{export}-CloudMapService")
    }
  end

  Output(:DBClusterId) {
    Value(Ref(:DBCluster))
    Export FnSub("${EnvironmentName}-#{export}-dbcluster-id")
  }

  IAM_Role(:RDSReplicaAutoScaleRole) do
    Condition 'EnableReplicaAutoScaling'
    AssumeRolePolicyDocument service_assume_role_policy('application-autoscaling')
    Path '/'
    Policies ([
      PolicyName: FnSub("${EnvironmentName}-rds-replica-scaling"),
      PolicyDocument: {
        Statement: [
          {
            Effect: "Allow",
            Action: "iam:CreateServiceLinkedRole",
            Resource: FnSub("arn:aws:iam::${AWS::AccountId}:role/aws-service-role/rds.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_RDSCluster"),
            Condition: ({
              StringLike: {
                "iam:AWSServiceName":"rds.application-autoscaling.amazonaws.com"
               }
            })
          },
          {
            Effect: "Allow",
            Action: ['cloudwatch:DescribeAlarms','cloudwatch:PutMetricAlarm','cloudwatch:DeleteAlarms'],
            Resource: "*"
          }
        ]
    }])
  end

  scaling_policy = external_parameters.fetch(:scaling_policy, {})

  if scaling_policy['up'].kind_of?(Hash)
    scaling_policy['up'] = [scaling_policy['up']]
  end

  if scaling_policy['down'].kind_of?(Hash)
    scaling_policy['down'] = [scaling_policy['down']]
  end

  if scaling_policy['target'].kind_of?(Hash)
    scaling_policy['target'] = [scaling_policy['target']]
  end

  ApplicationAutoScaling_ScalableTarget(:ServiceScalingTarget) do
    DependsOn 'RDSReplicaAutoScaleRole'
    Condition 'EnableReplicaAutoScaling'
    MaxCapacity Ref(:ScalableTargetMaxCapacity)
    MinCapacity Ref(:ScalableTargetMinCapacity)
    ResourceId FnJoin(':',["cluster",Ref(:DBCluster)])
    RoleARN FnGetAtt(:RDSReplicaAutoScaleRole,:Arn)
    ScalableDimension "rds:cluster:ReadReplicaCount"
    ServiceNamespace "rds"
  end

  scaling_policy['target'].each_with_index do |scale_target_policy, i|
    logical_scaling_policy_name = "ServiceTargetTrackingPolicy" + (i > 0 ? "#{i+1}" : "")
    policy_name = "target-tracking-policy" + (i > 0 ? "-#{i+1}" : "")
    ApplicationAutoScaling_ScalingPolicy(logical_scaling_policy_name) do
      DependsOn 'ServiceScalingTarget'
      Condition 'EnableReplicaAutoScaling'
      PolicyName FnJoin('-', [ Ref('EnvironmentName'), component_name, policy_name])
      PolicyType 'TargetTrackingScaling'
      ScalingTargetId Ref(:ServiceScalingTarget)
      TargetTrackingScalingPolicyConfiguration({
        TargetValue: scale_target_policy['target_value'],
        ScaleInCooldown: scale_target_policy['scale_in_cooldown'].to_s,
        ScaleOutCooldown: scale_target_policy['scale_out_cooldown'].to_s,
        PredefinedMetricSpecification: {
          PredefinedMetricType: scale_target_policy['metric_type'] || 'RDSReaderAverageCPUUtilization'
        }
      })
    end
  end unless scaling_policy['target'].nil?

end
