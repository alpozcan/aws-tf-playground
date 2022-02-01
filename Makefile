init:
	terraform init

select-workspace:
	terraform workspace select $(env)

plan: select-workspace
	terraform plan -var-file=envs/$(env).tfvars

apply: select-workspace
	terraform apply -var-file=envs/$(env).tfvars

state-list: select-workspace
	terraform state list

destroy: select-workspace
	terraform destroy -var-file=envs/$(env).tfvars
