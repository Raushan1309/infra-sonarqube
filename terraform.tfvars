
region = "us-east-1"

vpc_cidr_block = "10.0.0.0/16"

public_subnet_a_az  = "us-east-1a"
public_subnet_b_az  = "us-east-1b"
private_subnet_a_az = "us-east-1a"
private_subnet_b_az = "us-east-1b"

public_subnet_a_cidr_block  = "10.0.1.0/24"
public_subnet_b_cidr_block  = "10.0.2.0/24"
private_subnet_a_cidr_block = "10.0.3.0/24"
private_subnet_b_cidr_block = "10.0.4.0/24"

# Replace with your actual public IP /32
whitelisted_ip = ["47.31.95.244/32"]

all_hosts = ["0.0.0.0/0"]

key_pair_name = "sonarqube-key"

# Jenkins will override this using TF_VAR_ec2_key_location
ec2_key_location = ".ssh/sonarqube-key.pem"

instance_size_small             = "t3.micro"
instance_size_big_for_sonarqube = "t3.large"

desired_number = 0
min_number     = 0
max_number     = 0

alb_listener = []

# Existing VPC peering disabled for initial deployment
existing_vpc_id = ""
peered_vpc_cidr = "172.31.0.0/16"
new_vpc_id      = ""
