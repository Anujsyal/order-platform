# Policy gate for Terraform plans (Jenkinsfile.infra):
#   terraform show -json env.tfplan > plan.json
#   conftest test plan.json -p policies/terraform
# Any `deny` blocks the apply.
package main

import rego.v1

# t3.* for paid accounts; c7i-flex/m7i-flex are the AWS Free plan equivalents
allowed_instance_types := {"t3.small", "t3.medium", "t3.large", "t3.xlarge", "c7i-flex.large", "m7i-flex.large"}

required_tags := {"Project", "Environment", "ManagedBy"}

taggable_types := {
	"aws_instance",
	"aws_vpc",
	"aws_subnet",
	"aws_security_group",
	"aws_internet_gateway",
	"aws_route_table",
	"aws_eip",
	"aws_cloudwatch_log_group",
	"aws_sns_topic",
}

# Ports that must never be open to the internet.
sensitive_ports := {22, 2379, 2380, 6443, 10250}

# Resources being created or updated by this plan.
changed contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
}

# ---------------------------------------------------------------- EC2

imdsv2_required(after) if {
	some m in after.metadata_options
	m.http_tokens == "required"
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_instance"
	not imdsv2_required(rc.change.after)
	msg := sprintf("%s: IMDSv2 must be enforced (metadata_options.http_tokens = \"required\")", [rc.address])
}

root_volume_encrypted(after) if {
	some v in after.root_block_device
	v.encrypted == true
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_instance"
	not root_volume_encrypted(rc.change.after)
	msg := sprintf("%s: root volume must be encrypted", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_instance"
	not rc.change.after.instance_type in allowed_instance_types
	msg := sprintf("%s: instance type %s is not in the allowed list %v", [rc.address, rc.change.after.instance_type, allowed_instance_types])
}

# ---------------------------------------------------------------- Network

open_to_world(after) if after.cidr_ipv4 == "0.0.0.0/0"

open_to_world(after) if after.cidr_ipv6 == "::/0"

deny contains msg if {
	some rc in changed
	rc.type == "aws_vpc_security_group_ingress_rule"
	open_to_world(rc.change.after)
	rc.change.after.ip_protocol == "-1"
	msg := sprintf("%s: allowing ALL traffic from the internet is forbidden", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_vpc_security_group_ingress_rule"
	open_to_world(rc.change.after)
	some port in sensitive_ports
	rc.change.after.from_port <= port
	port <= rc.change.after.to_port
	msg := sprintf("%s: port %d must not be reachable from the internet", [rc.address, port])
}

# ---------------------------------------------------------------- Tagging

has_tag(after, tag) if after.tags_all[tag]

has_tag(after, tag) if after.tags[tag]

deny contains msg if {
	some rc in changed
	rc.type in taggable_types
	some tag in required_tags
	not has_tag(rc.change.after, tag)
	msg := sprintf("%s: missing required tag %q", [rc.address, tag])
}

# ---------------------------------------------------------------- Monitoring

# Log groups without retention keep data (and cost) forever.
deny contains msg if {
	some rc in changed
	rc.type == "aws_cloudwatch_log_group"
	object.get(rc.change.after, "retention_in_days", 0) == 0
	msg := sprintf("%s: CloudWatch log group must set retention_in_days", [rc.address])
}

# An alarm nobody hears is useless: composite alarms must notify someone.
deny contains msg if {
	some rc in changed
	rc.type == "aws_cloudwatch_composite_alarm"
	count(object.get(rc.change.after, "alarm_actions", [])) == 0
	msg := sprintf("%s: composite alarm must have alarm_actions (e.g. the SNS alerts topic)", [rc.address])
}
