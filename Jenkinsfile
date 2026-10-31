//final ver
pipeline {
    agent any
    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timestamps()
    }
    parameters {
        choice(name: 'ACTION', choices: ['PLAN', 'VERIFY', 'APPLY', 'ANSIBLE', 'DESTROY'], description: 'Choose pipeline action')
        booleanParam(name: 'CONFIRM_DESTROY', defaultValue: false, description: 'Must be checked to destroy infrastructure')
    }
    // setting the environment like aws creds, ssh key path
    environment {
        // AWS credentials are bound only in stages that need them
        TF_VAR_region = 'us-east-1'
        AWS_DEFAULT_REGION = 'us-east-1'
        TF_IN_AUTOMATION = 'true'
        // S3 backend bucket is configured in backend.tf: sonarqube-terraform-state-1234
        SSH_KEY_PATH = "${WORKSPACE}/.ssh/sonarqube-key.pem"
        // virtual env path
        VENV_PATH = "${WORKSPACE}/venv"
    }

    stages {
        // terraform repo checkout
        stage('Git Checkout - Terraform Repo') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main']],
                    doGenerateSubmoduleConfigurations: false,
                    extensions: [],
                    userRemoteConfigs: [[
                        url: 'https://github.com/Raushan1309/infra-sonarqube.git',
                        //credentialsId: 'github-user-password'
                    ]]
                ])
            }
        }

        // Safe pre-deployment checks. No AWS infrastructure is created by these stages.
        stage('Terraform Init') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        set -eu
                        aws sts get-caller-identity
                        aws s3api head-bucket --bucket sonarqube-terraform-state-1234
                        terraform init -reconfigure -input=false
                    '''
                }
            }
        }

        stage('Terraform Formatting') {
            when { expression { params.ACTION != 'DESTROY' } }
            steps {
                sh 'terraform fmt -check -recursive'
            }
        }

        stage('Terraform Validate') {
            when { expression { params.ACTION != 'DESTROY' } }
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            when { expression { params.ACTION == 'PLAN' || params.ACTION == 'APPLY' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        set -eu
                        mkdir -p "${WORKSPACE}/.ssh"
                        export TF_VAR_ec2_key_location="${WORKSPACE}/.ssh/sonarqube-key.pem"
                        if [ ! -f terraform.tfvars ]; then
                            echo 'ERROR: terraform.tfvars is missing in the Jenkins workspace.'
                            echo 'Required root variables need to be provided before planning.'
                            echo 'Do not run Terraform Apply yet.'
                            exit 1
                        fi
                        terraform plan -input=false -out=tfplan
                    '''
                }
            }
        }

        stage('Terraform Apply') {
            when { expression { params.ACTION == 'APPLY' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    sh '''
                        set -eu
                        export TF_VAR_ec2_key_location="$WORKSPACE/.ssh/sonarqube-key.pem"
                        terraform apply -input=false tfplan
                        test -f "$TF_VAR_ec2_key_location"
                        chmod 400 "$TF_VAR_ec2_key_location"
                    '''
                }
            }
        }

        stage('Confirm Destroy') {
            when { expression { params.ACTION == 'DESTROY' } }
            steps {
                script {
                    if (!params.CONFIRM_DESTROY) {
                        error('DESTROY blocked: check CONFIRM_DESTROY first.')
                    }
                    input message: 'Permanently destroy ALL resources in this Terraform state?', ok: 'Destroy infrastructure'
                }
            }
        }

        stage('Terraform Destroy') {
            when { expression { params.ACTION == 'DESTROY' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    sh '''
                        set -eu
                        export TF_VAR_ec2_key_location="$WORKSPACE/.ssh/sonarqube-key.pem"
                        terraform destroy -input=false -auto-approve
                    '''
                }
            }
        }

        stage('Show Terraform Outputs') {
            when { expression { params.ACTION == 'APPLY' || params.ACTION == 'VERIFY' || params.ACTION == 'ANSIBLE' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    sh '''
                        set -eu
                        terraform output -raw bastion_public_ip; echo
                        terraform output -raw bastion_public_dns; echo
                        terraform output aws_private_instance_ip
                        terraform output -raw alb_dns_name; echo
                        test -f "$SSH_KEY_PATH"
                        chmod 400 "$SSH_KEY_PATH"
                        # Values come from Terraform state, not hardcoded IPs.
                        terraform output -json > "$WORKSPACE/.terraform-outputs.json"
                    '''
                }
            }
        }

        stage('Verify Bastion and Private EC2 SSH Connectivity') {
            when { expression { params.ACTION == 'VERIFY' || params.ACTION == 'ANSIBLE' } }
            steps {
                sh '''
                    set -eu
                    python3 - <<'PYCODE'
import json, os, subprocess
p = os.environ['WORKSPACE']
with open(p + '/.terraform-outputs.json') as f:
    out = json.load(f)
bastion = out['bastion_public_ip']['value']
private_ips = out['aws_private_instance_ip']['value']
key = os.environ['SSH_KEY_PATH']
assert len(private_ips) == 2, 'Expected two private EC2 IPs'
common = ['-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15']
subprocess.run(['ssh', '-i', key, *common, 'ubuntu@'+bastion, 'hostname && whoami'], check=True)
proxy = f'ssh -i {key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -W %h:%p ubuntu@{bastion}'
for ip in private_ips:
    print('Testing private EC2', ip, flush=True)
    subprocess.run(['ssh', '-i', key, *common, '-o', 'ProxyCommand='+proxy, 'ubuntu@'+ip, 'hostname && whoami'], check=True)
print('SUCCESS: Bastion and both private EC2 reachable')
PYCODE
                '''
            }
        }

        stage('Git Checkout - Ansible Repo') {
            when { expression { params.ACTION == 'ANSIBLE' } }
            steps {
                dir('ansible-sonarqube') {
                    git branch: 'main', url: 'https://github.com/Raushan1309/ansible-sonarqube.git'
                }
            }
        }

        stage('Setup Virtualenv & Install Ansible dependencies') {
            when { expression { params.ACTION == 'ANSIBLE' } }
            steps {
                sh '''
                    set -eu
                    python3 -m venv "$VENV_PATH"
                    "$VENV_PATH/bin/pip" install ansible-core boto3 botocore
                    "$VENV_PATH/bin/ansible-galaxy" collection install ansible.posix
                '''
            }
        }

        stage('Install SonarQube on Both Private EC2') {
            when { expression { params.ACTION == 'ANSIBLE' } }
            steps {
                withCredentials([string(credentialsId: 'sonar-db-password', variable: 'SONAR_DB_PASSWORD')]) {
                    dir('ansible-sonarqube') {
                        sh '''
                            set -eu
                            set +x
                            umask 077
                            export ANSIBLE_CONFIG="$PWD/ansible.cfg"
                            # Temporary files are deleted even if Ansible fails.
                            TEMP_DIR=$(mktemp -d)
                            trap 'rm -rf "$TEMP_DIR"' EXIT
                            export TEMP_DIR
                            python3 - <<'PYCODE'
import json, os
out = json.load(open(os.environ['WORKSPACE']+'/.terraform-outputs.json'))
ips = out['aws_private_instance_ip']['value']
bastion = out['bastion_public_ip']['value']
key = os.environ['SSH_KEY_PATH']
assert len(ips) == 2, 'Expected two private EC2 instances'
tmp = os.environ['TEMP_DIR']
with open(tmp+'/inventory.ini', 'w') as f:
    f.write('[sonarqube_servers]\n')
    for ip in ips: f.write(ip+'\n')
    f.write('\n[sonarqube_servers:vars]\nansible_user=ubuntu\nansible_python_interpreter=/usr/bin/python3\n')
with open(tmp+'/ssh_config', 'w') as f:
    f.write('Host '+' '.join(ips)+'\n')
    f.write('    User ubuntu\n    IdentityFile '+key+'\n    IdentitiesOnly yes\n    StrictHostKeyChecking accept-new\n')
    f.write('    ProxyCommand ssh -i '+key+' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -W %h:%p ubuntu@'+bastion+'\n')
with open(tmp+'/secrets.json', 'w') as f:
    json.dump({'sonar_db_password': os.environ['SONAR_DB_PASSWORD']}, f)
PYCODE
                            export ANSIBLE_SSH_ARGS="-F $TEMP_DIR/ssh_config"
                            export ANSIBLE_HOST_KEY_CHECKING=True
                            "$VENV_PATH/bin/ansible" -i "$TEMP_DIR/inventory.ini" sonarqube_servers -m ping
                            "$VENV_PATH/bin/ansible-playbook" -i "$TEMP_DIR/inventory.ini" site.yml \
                                --extra-vars "@$TEMP_DIR/secrets.json"
                        '''
                    }
                }
            }
        }
    }
    post {
        success { echo "Pipeline action ${params.ACTION} completed successfully." }
        failure { echo "Pipeline action ${params.ACTION} failed. Check console output." }
    }
}
