CfhighlanderTemplate do
  DependsOn 'vpc@1.2.0'
  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true, allowedValues: ['development', 'production']
    ComponentParam 'StackOctet', isGlobal: true
    MappingParam('WriterInstanceType') do
      map 'EnvironmentType'
      attribute 'WriterInstanceType'
    end
    MappingParam('ReaderInstanceType') do
      map 'EnvironmentType'
      attribute 'ReaderInstanceType'
    end
    MappingParam('DnsDomain') do
      map 'AccountId'
      attribute 'DnsDomain'
    end
    maximum_availability_zones.times do |az|
      ComponentParam "SubnetPersistence#{az}"
    end
    ComponentParam 'SnapshotID'
    ComponentParam 'EnableReader', 'false'
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
  end
end
