CfhighlanderTemplate do
  Name 'aurora-mysq'
  DependsOn 'vpc'

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true, allowedValues: ['development', 'production']
    ComponentParam 'StackOctet', isGlobal: true
    ComponentParam 'DnsDomain'
    ComponentParam 'SnapshotID'

    if engine_mode == 'provisioned'
      ComponentParam 'WriterInstanceType'
      ComponentParam 'ReaderInstanceType'
      ComponentParam 'EnableReader', 'false'
    end

    if engine_mode == 'serverless'
      ComponentParam 'AutoPause', 'true', allowedValues: ['true', 'false']
      ComponentParam 'MaxCapacity', 2, allowedValues: [2, 4, 8, 16, 32, 64, 128, 256]
      ComponentParam 'MinCapacity', 2, allowedValues: [2, 4, 8, 16, 32, 64, 128, 256]
      ComponentParam 'SecondsUntilAutoPause', 3600
    end

    ComponentParam 'KmsKeyId' if (defined?(kms_key_id) && kms_key_id == true)
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    maximum_availability_zones.times do |az|
      ComponentParam "SubnetPersistence#{az}"
    end

  end
end
