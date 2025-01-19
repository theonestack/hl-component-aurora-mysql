CfhighlanderTemplate do
  Name 'aurora-mysql'
  DependsOn 'vpc'
  DependsOn 'lib-iam'

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true, allowedValues: ['development', 'production']
    ComponentParam 'StackOctet', isGlobal: true
    ComponentParam 'NetworkPrefix', '10', isGlobal: true
    ComponentParam 'DnsDomain'
    ComponentParam 'SnapshotID'
    ComponentParam 'ScalableTargetMinCapacity'
    ComponentParam 'ScalableTargetMaxCapacity'
    ComponentParam 'EngineVersion'
    ComponentParam 'StorageEncrypted', false
    ComponentParam 'StorageType', 'aurora', allowedValues: ['aurora', 'aurora-iopt1']
    ComponentParam 'EnableHttpEndpoint', 'false', allowedValues: ['true', 'false']

    if engine_mode == 'provisioned'
      ComponentParam 'WriterInstanceType'
      ComponentParam 'ReaderInstanceType'
      ComponentParam 'EnableReader', 'false'
    end

    if engine_mode == 'serverless' || engine_mode == 'serverlessv2'
      ComponentParam 'MaxCapacity', 2, allowedValues: [1, 2, 4, 8, 16, 32, 64, 128, 192, 256]
      ComponentParam 'MinCapacity', 2, allowedValues: [0, 0.5, 1, 2, 4, 8, 16, 32, 64, 128, 192, 256]
    end

    ComponentParam 'KmsKeyId' if defined? kms_key_id
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'

    ComponentParam 'EnablePerformanceInsights', defined?(performance_insights) ? performance_insights : false
    ComponentParam 'PerformanceInsightsRetentionPeriod', defined?(performance_insights) && defined?(insights_retention)  ? insights_retention.to_i : 7

    ComponentParam 'NamespaceId' if defined? service_discovery

    ComponentParam 'EnableReplicaAutoScaling', 'false'

    ComponentParam 'EnableCloudwatchLogsExports', defined?(log_exports) ? log_exports : ''

    ComponentParam 'EnableLocalWriteForwarding', 'false'
  end
end
