# aurora (MySQL) CfHighlander component
## Parameters

| Name | Use | Default | Global | Type | Allowed Values |
| ---- | --- | ------- | ------ | ---- | -------------- |
| EnvironmentName | Tagging | dev | true | string
| EnvironmentType | Tagging | development | true | string | ['development','production']
| VPCId | Security Groups | None | false | AWS::EC2::VPC::Id
| DnsDomain | DNS domain to use | None | true | string
| SubnetIds | List of subnets | None | false | CommaDelimitedList
| KmsKeyId | KMS ID | None | false | string (arn)
| NamespaceId | Service discovery namespace ID | None | false | string
| SnapshotId | Snapshot ID to provision from | None | false | string
| WriterInstanceType | Writer instance type *if engine is set to provisioned* | None | false | string
| ReaderInstanceType | Reader instance type *if engine is set to provisioned* | None | false | string
| AutoPause | Whether to auto-pause *if engine is set to serverless* | true | false | bool
| MaxCapacity | Maximum serverless instances *if engine is set to serverless* | 2 | false | int
| MinCapacity | Minimum serverless instances *if engine is set to serverless* | 2 | false | int
| SecondsUntilAutoPause | Seconds until autopause *if engine is set to serverless* | 3600 (1 hour) | false | int

## Outputs/Exports

| Name | Value | Exported |
| ---- | ----- | -------- |
| SecretCredentials | Secret password if set to auto generate | true
| SecurityGroup | Security Group name | true
| ServiceRegistry | CloudMap service registry ID | true
| DBClusterId | Database Cluster ID | true

## Included Components

[lib-ec2](https://github.com/theonestack/hl-component-lib-ec2)

## Example Configuration
### Highlander
```
  Component name:'database', template: 'aurora-mysql' do
    parameter name: 'DnsDomain', value: root_domain
    parameter name: 'DnsFormat', value: FnSub("${EnvironmentName}.#{root_domain}")
    parameter name: 'SubnetIds', value: cfout('vpcv2', 'PersistenceSubnets')
    parameter name: 'WriterInstanceType', value: writer_instance
    parameter name: 'ReaderInstanceType', value: reader_instance
    parameter name: 'EnableReader', value: 'true'
    parameter name: 'StackOctet', value: '80'
    parameter name: 'NamespaceId', value: cfout('servicediscovery', 'NamespaceId')
  end
```

### Aurora MySQL Configuration
```
hostname: db
db_name: appdb
dns_format: ${DnsFormat}

storage_encrypted: true
engine: aurora-mysql
engine_version: '5.7.mysql_aurora.2.09.2'

writer_instance: db.r3.large
reader_instance: db.r3.large

deletion_policy: Snapshot

secret_username: appuser

security_group:
  -
    rules:
      -
        IpProtocol: tcp
        FromPort: 3306
        ToPort: 3306
    ips:
      - stack
      - company_office
      - company_client_vpn

service_discovery:
  name: db
```

## Cfhighlander Setup

install cfhighlander [gem](https://github.com/theonestack/cfhighlander)

```bash
gem install cfhighlander
```

or via docker

```bash
docker pull theonestack/cfhighlander
```
## Testing Components

Running the tests

```bash
cfhighlander cftest aurora-mysql
```