# Order Platform: Complete Setup Guide (Manual + Terraform)

Ye document isliye hai ki tujhe **har cheez haath se karni aaye**: EC2 kaise banana, Jenkins kaise install karna, docker group kyun add karna, Kubernetes cluster kaise banana, Argo CD kaise lagana. Saath mein ye bhi samjhaata hai ki **pura project ka flow kaise kaam karta hai**.

Plan simple hai:

- **Part A (Manual):** pehle sab kuch haath se, AWS Console aur SSH se. Isse samajh aayega ki andar kya ho raha hai.
- **Part B (Terraform):** wahi sab kuch code se, jo is project ka asli tareeka hai.
- **Part C onwards:** flow, approval gates, policies, rollback, monitoring, troubleshooting.

> Tip: Part A ek baar poora kar le, phir sab `terraform destroy`/delete kar ke Part B se bana. Interview mein dono bata payega.

---

## Index

0. [Big picture: kya ban raha hai](#0-big-picture-kya-ban-raha-hai)
1. [Prerequisites](#1-prerequisites)
2. **Part A: Manual**
   - [A1. Key pair](#a1-key-pair-banana)
   - [A2. Security group (Jenkins)](#a2-security-group-jenkins-ke-liye)
   - [A3. EC2 launch karna](#a3-ec2-launch-karna-console-se)
   - [A4. SSH karna](#a4-ssh-karna)
   - [A5. Java install](#a5-java-install)
   - [A6. Jenkins install](#a6-jenkins-install)
   - [A7. Docker install + docker group](#a7-docker-install--jenkins-ko-docker-group-mein-add-karna)
   - [A8. Baaki tools](#a8-baaki-tools-maven-trivy-kustomize-conftest-terraform)
   - [A9. Jenkins first login + plugins](#a9-jenkins-first-login--plugins)
   - [A10. Jenkins credentials](#a10-jenkins-credentials)
   - [A11. Jenkins global env vars](#a11-jenkins-global-environment-variables)
   - [A12. Jenkins jobs + GitHub webhook](#a12-jenkins-jobs--github-webhook)
   - [A13. Kubernetes cluster manually (kubeadm)](#a13-kubernetes-cluster-manually-kubeadm)
   - [A14. Argo CD manually](#a14-argo-cd-manually-install-karna)
3. **Part B: Terraform**
   - [B1. Placeholders bharna](#b1-placeholders-bharna)
   - [B2. State bucket](#b2-terraform-state-bucket)
   - [B3. Shared stack (VPC + Jenkins)](#b3-shared-stack-vpc--jenkins)
   - [B4. GitHub pe 2 repos push](#b4-github-pe-2-repos-push-karna)
   - [B5. Jenkins configure](#b5-jenkins-configure)
   - [B6. Clusters banana](#b6-clusters-banana-dev--staging--prod)
   - [B7. Cluster check karna](#b7-cluster-check-karna)
4. [C. Pura flow: commit se prod tak](#c-pura-flow-commit-se-prod-tak)
5. [D. Approval gates](#d-approval-gates)
6. [E. Policy-as-code](#e-policy-as-code-3-layers)
7. [F. Automated rollback demo](#f-automated-rollback-demo) + [F2. Drift + self-healing drill](#f2-drift--self-healing-drill)
8. [G. Monitoring + smart alerting](#g-monitoring--smart-alerting)
   - [G1. URLs + login](#g1-urls-aur-login) · [G2. Slack setup](#g2-slack-setup-alertmanager--jenkins) · [G3. CloudWatch email](#g3-cloudwatch-email-alerts-sns) · [G4. Alert ka safar](#g4-alert-ka-safar-metric-se-slack-tak)
   - [G5. SLO + burn rate](#g5-slo-aur-burn-rate-alerting-ye-smart-part-hai) · [G6. Noise control](#g6-alertmanager-ke-noise-control-features) · [G7. Alerts list](#g7-saare-alerts-ki-list) · [G8. Dashboards](#g8-grafana-dashboards)
   - [G9. CloudWatch](#g9-cloudwatch-layer-terraform-kya-banata-hai) · [G10. Manual tareeka](#g10-manual-tareeka-seekhne-ke-liye-bina-terraformargo-cd) · [G11. Alerts test](#g11-alerts-test-karna-zaruri-jo-test-nahi-hua-wo-kaam-nahi-karta) · [G12. Kharcha](#g12-monitoring-ka-kharcha-approx-per-envmonth)
9. [H. Hardening checklist](#h-hardening-checklist)
10. [I. Infra changes promote karna](#i-infra-changes-promote-karna)
11. [J. Troubleshooting](#j-troubleshooting)
12. [K. Cleanup + cost](#k-cleanup--cost)
13. [L. Cheat sheet](#l-cheat-sheet)

---

## 0. Big picture: kya ban raha hai

```
 Tu (developer)
   │ git push
   ▼
 GitHub repo #1: order-platform  (Java app, Jenkinsfile, Terraform, policies)
   │ webhook
   ▼
 ┌──────────────── Jenkins (EC2) ────────────────┐
 │ 1. mvn verify          (build + unit tests)    │
 │ 2. docker build        (image banao)           │
 │ 3. trivy scan          (CVE check)             │
 │ 4. docker push         (Docker Hub)            │
 │ 5. GitOps repo mein dev ka image tag update    │
 │ 6. verify dev  ── fail? ⇒ git revert           │
 │ 7. ⏸ APPROVAL ⇒ staging tag update ⇒ verify   │
 │ 8. ⏸ APPROVAL ⇒ prod tag update ⇒ verify      │
 └───────────────┬───────────────────────────────┘
                 │ git commit (sirf image tag badalta hai)
                 ▼
 GitHub repo #2: order-platform-gitops  (Kubernetes YAML = "desired state")
     │                      │                      │
     ▼ Argo CD pull         ▼                      ▼
 ┌ dev cluster ┐    ┌ staging cluster ┐    ┌ prod cluster ┐
 │ 1 master +  │    │ 1 master +      │    │ 1 master +   │
 │ 2 workers   │    │ 2 workers       │    │ 3 workers    │
 └─────────────┘    └─────────────────┘    └──────────────┘
   Har cluster mein: Argo CD, Argo Rollouts (canary), Kyverno (policies),
   Prometheus + Grafana (monitoring), Calico (network policies)
```

### Har tool ka kaam (ek line mein)

| Tool | Kaam | Kahan chalta hai |
|---|---|---|
| **EC2** | Virtual machines | AWS |
| **Terraform** | AWS infra code se banana (VPC, EC2, SG) | Laptop + Jenkins |
| **Jenkins** | CI: build, test, scan, image push, promotion | EC2 |
| **Docker** | Image build karna | Jenkins EC2 |
| **Docker Hub** | Images store karna | Cloud |
| **kubeadm** | Kubernetes cluster EC2 pe banana | Har cluster node |
| **Calico** | Pod networking + NetworkPolicy | Cluster |
| **Argo CD** | CD: Git se cluster sync karna (GitOps) | Har cluster |
| **Argo Rollouts** | Canary deploy + auto rollback | Har cluster |
| **Kyverno** | Cluster ke andar policy enforce karna | Har cluster |
| **conftest/OPA** | CI mein policy check (Terraform plan + YAML) | Jenkins |
| **Trivy** | Image vulnerability scan | Jenkins |
| **Prometheus/Grafana** | Metrics, SLO alerts, dashboards | Har cluster |
| **Alertmanager** | Alerts ko group/dedupe karke Slack pe bhejna | Har cluster |
| **CloudWatch + SNS** | Cluster ke bahar se EC2 health, memory/disk, logs → email | AWS |
| **Slack** | Alerts + pipeline notifications (approval, rollback) | Cloud |

### 2 repos kyun?

- **order-platform**: code repo (app, Jenkinsfile, Terraform, policies).
- **order-platform-gitops**: sirf Kubernetes YAML. Isme jo likha hai, wahi cluster mein chalega.

Agar dono ek hi repo mein hote to Jenkins jab image tag commit karta, wo commit dobara Jenkins trigger karta, aur infinite loop ban jaata. Alag repo rakhne se ye problem nahi hoti, aur access bhi alag control kar sakte hain. Industry mein yahi standard hai.

> Is folder mein `gitops/` directory hai. Wo **alag repo** ke roop mein push hogi (B4 dekh). Main repo ka `.gitignore` usko ignore karta hai.

**Repo map: kya kahan hai** (poori file-by-file detail Interview-Prep doc §19 mein):

| Repo | Folder / file | Kaam |
|---|---|---|
| **order-platform** (Private) | `Jenkinsfile` | App pipeline: test → Docker → Trivy → push → promote dev/staging/prod (approvals, verify, auto-rollback, Slack) |
| | `Jenkinsfile.infra` | Infra pipeline: terraform plan → conftest → apply, dev → staging → prod |
| | `app/` | Java 21 Spring Boot order-service (`/api/orders`, `/api/version`, metrics, fault injection demo) |
| | `terraform/` | `bootstrap` (state bucket), `stacks/shared` (VPC + Jenkins), `stacks/cluster` (1 cluster per env via tfvars), `modules/` (vpc, jenkins, k8s-cluster, cloudwatch-alarms) |
| | `policies/` | Rego: `terraform/aws.rego` (plan pe), `kubernetes/workloads.rego` (promote se pehle) |
| | `scripts/` | `promote.sh` (tag commit), `verify-deployment.sh` (10 lagatar OK), `rollback.sh` (git revert), `configure.sh`, `get-kubeconfig.sh` |
| | `docs/RUNBOOKS.md` | Har alert ka runbook (Slack "Runbook" link) |
| **order-platform-gitops** (Public) | `bootstrap/root-<env>.yaml` | App-of-apps: ek baar apply, baaki sab ye banata hai |
| | `clusters/<env>/addons.yaml` | kube-prometheus-stack, argo-rollouts, kyverno, kyverno-policies, monitoring-config (pinned versions, sync waves) |
| | `clusters/<env>/apps.yaml` | AppProject + order-service Application |
| | `apps/order-service/base/` | Rollout (canary), AnalysisTemplate, Service, NetworkPolicies, PDB, ServiceMonitor, PrometheusRule (SLO), dashboard, traffic-generator |
| | `apps/order-service/overlays/<env>/` | **Image tag** (sirf Jenkins badalta hai), replicas, prod ka slow canary |
| | `platform/kyverno-policies/` | 5 policies; dev Audit, staging/prod Enforce |
| | `platform/monitoring/` | Platform alerts (Argo CD, RolloutAborted, Kyverno), Argo CD scrape, overview dashboard |

### Ek important concept: Push vs Pull deployment

- **Purana tareeka (push):** Jenkins `kubectl apply` karta hai cluster pe. Iske liye Jenkins ke paas cluster ka admin access chahiye, jo risky hai.
- **GitOps (pull):** Jenkins sirf Git mein commit karta hai. Cluster ke andar baitha Argo CD Git dekhta hai aur khud apply karta hai. Jenkins ko cluster access ki zarurat hi nahi.
- **Fayda:** Git = single source of truth. Rollback = `git revert`. Kisne kya deploy kiya, sab Git history mein dikhta hai.

---

## 1. Prerequisites

### 1.1 Accounts
- **AWS account.** Root user se kaam mat kar. Ek IAM user bana (AdministratorAccess) aur MFA laga.
- **GitHub account** (2 repos banenge).
- **Docker Hub account.** Account Settings → Personal access tokens → **Read & Write** token bana aur save kar le.
- **Slack workspace** (free). Alerts aur pipeline notifications ke liye. Setup: section G2.
- **Ek email** jahan CloudWatch alerts aayenge (`--alert-email`, B1).

### 1.2 Billing alarm (pehle ye kar!)
AWS Console → **Billing and Cost Management → Budgets → Create budget** → "Monthly cost budget" → amount jaise $20 → apna email daal. Isse paisa bachega agar kuch on reh gaya.

### 1.3 Laptop pe tools (Windows)
PowerShell (admin) mein:
```powershell
winget install Git.Git
winget install Amazon.AWSCLI
winget install Hashicorp.Terraform
winget install Kubernetes.kubectl
```
Naya terminal khol ke check kar:
```bash
git --version; aws --version; terraform version; kubectl version --client
```
Terraform **1.10+** chahiye (S3 native locking ke liye).

### 1.4 AWS CLI configure
IAM → Users → tera user → Security credentials → **Create access key** (CLI).
```bash
aws configure
# AWS Access Key ID:     AKIA....
# AWS Secret Access Key: ....
# Default region name:   ap-south-1      (Mumbai)
# Default output format: json
aws sts get-caller-identity     # tera account/user dikhna chahiye
```

### 1.5 Apna public IP
Security groups mein sirf tera IP allow hoga:
```bash
curl https://checkip.amazonaws.com     # e.g. 49.36.12.34  →  CIDR: 49.36.12.34/32
```
> Ghar ka IP badalta rehta hai (dynamic). Agar kal SSH/Jenkins na khule, sabse pehle check kar ki IP badla to nahi. Terraform wale setup mein tfvars update kar ke `apply` kar de.

### 1.6 Kharcha (approx, ap-south-1, on-demand)
| Cheez | Instances | ~ $/hour |
|---|---|---|
| Jenkins | 1 × c7i-flex.large | ~0.09 |
| Dev cluster | 3 × c7i-flex.large | ~0.27 |
| Staging cluster | 3 × c7i-flex.large | ~0.27 |
| Prod cluster | 1 × c7i-flex.large + 3 × m7i-flex.large | ~0.40 |
| Public IPv4 | ~12 | 0.06 |
| EBS disks (30 GB har EC2) | ~12 | ~0.045 |
| CloudWatch (alarms, agent metrics, logs) | per env | ~$5–10/month (G12) |

**Sab kuch 24×7 = roughly $27/day.** Seekhte waqt sirf Jenkins + dev chala (~$10/day) aur kaam khatam hote hi destroy/stop kar. Smart tareeke se poora project ~$35–45 mein ho jaata hai. Rates approx hain, exact ke liye AWS Pricing Calculator dekh.

### 1.7 ⚠️ AWS Free plan account? Ye 2 cheezein pehle check kar

**(a) Instance types.** Naye AWS accounts (July 2025 ke baad) aksar **Free plan** pe hote hain. Usme sirf "free tier eligible" instance types launch hote hain, **t3.medium/t3.large nahi**. Check:
```bash
aws ec2 describe-instance-types --region ap-south-1 --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB]' --output table
```
Isliye is project mein ye use hote hain (code aur guide dono mein):

| Kaam | Paid account | **Free plan (default ab yahi)** |
|---|---|---|
| Jenkins, K8s master, dev/staging workers | t3.medium (2 vCPU, 4 GB) | **c7i-flex.large** (2 vCPU, 4 GB) |
| Prod workers | t3.large (2 vCPU, 8 GB) | **m7i-flex.large** (2 vCPU, 8 GB) |

Free plan ka fayda: credits khatam hone pe card se paisa nahi katta. Credits check: `aws freetier get-account-plan-state` (naya AWS CLI chahiye), ya Billing → Credits.

**(b) vCPU limit.** Naye accounts mein "Running On-Demand Standard instances" ka limit **5 vCPU** jitna kam ho sakta hai. Har instance 2 vCPU leta hai, to sirf 2 EC2 chalenge. Check aur increase:
```bash
aws service-quotas get-service-quota --region ap-south-1 --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value'
```
Service Quotas → Amazon EC2 → **Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances** → Request increase → **16** (Jenkins + dev + staging) ya **24** (teeno envs). Approval mein kuch ghante se 1–2 din lagte hain.

---

# PART A: MANUAL (haath se, seekhne ke liye)

Is part mein hum AWS Console se Jenkins server aur ek Kubernetes cluster banayenge.

## A1. Key pair banana

Key pair = SSH ke liye private key (`.pem`). AWS public key apne paas rakhta hai, private key tere paas.

1. Console → **EC2** → left menu **Network & Security → Key Pairs** → **Create key pair**.
2. Name: `order-platform-key`, Type: **RSA**, Format: **.pem** → Create.
3. File download hogi. Usko `C:\Users\<tu>\.ssh\order-platform-key.pem` mein rakh.

Windows pe SSH "permissions too open" error deta hai, isliye permission fix kar (PowerShell):
```powershell
$k = "$env:USERPROFILE\.ssh\order-platform-key.pem"
icacls.exe $k /reset
icacls.exe $k /grant:r "$($env:USERNAME):(R)"
icacls.exe $k /inheritance:r
```
(Git Bash/Linux/Mac pe: `chmod 400 order-platform-key.pem`)

## A2. Security group (Jenkins ke liye)

Security Group (SG) = EC2 ka firewall. By default sab inbound band hota hai; jo rule add karo wahi khulta hai.

1. EC2 → **Security Groups** → **Create security group**.
2. Name: `jenkins-sg`, VPC: default VPC (manual part ke liye default hi theek hai).
3. **Inbound rules:**

| Type | Port | Source | Kyun |
|---|---|---|---|
| SSH | 22 | **My IP** | Sirf tu SSH kar sake |
| Custom TCP | 8080 | **My IP** | Jenkins UI |
| Custom TCP | 8080 | 192.30.252.0/22, 185.199.108.0/22, 140.82.112.0/20, 143.55.64.0/20 | GitHub webhooks (4 alag rules) |

4. **Outbound rules: "All traffic → 0.0.0.0/0" hona ZARURI hai.** Naya SG ye rule default mein deta hai, par edit karte waqt galti se delete ho sakta hai. Save karne se pehle **Outbound rules tab khol ke check kar**. Bina iske EC2 internet se kuch download nahi kar payega (apt, Jenkins, Docker), aur `apt-get update` "connection timed out" dega, jabki **SSH phir bhi chalta rahega**.

> 🧠 **SSH kyun chalta hai par apt nahi?** Security groups **stateful** hote hain: jo connection andar aaya (tera SSH), uska reply bahar jaane ki permission apne aap milti hai. Par EC2 khud se **naya** connection bahar (Ubuntu mirrors) tabhi khol sakta hai jab outbound rule ho. NACLs **stateless** hote hain, unme dono taraf ke rules alag likhne padte hain.

> ❌ Kabhi bhi SSH ke liye `0.0.0.0/0` (Anywhere) mat daal. Bots minutes mein brute-force start kar dete hain. Hamari Terraform policy (`policies/terraform/aws.rego`) bhi isko block karti hai.

## A3. EC2 launch karna (Console se)

EC2 → **Instances → Launch instances**:

> ⚠️ **Order zaruri hai: pehle Name + AMI chun, phir baaki sab.** AMI badalne pe "Some of your current settings will be changed" popup aata hai, aur security group + storage settings **reset** ho jaati hain.

| Field | Value | Kyun |
|---|---|---|
| Name | `jenkins` | |
| AMI | **Ubuntu Server 24.04 LTS** (64-bit x86) | Saare commands Ubuntu ke hain |
| Instance type | **c7i-flex.large** (2 vCPU, 4 GB). Paid account pe t3.medium bhi chalega (section 1.7) | Jenkins + Maven + Docker build ke liye 4 GB minimum. micro/small pe hang hoga |
| Key pair | `order-platform-key` | |
| Network settings → Edit | Auto-assign public IP: **Enable**. Firewall: ◉ **Select existing security group** → **jenkins-sg** | ⚠️ Default option "Create security group" ek `launch-wizard-N` SG banata hai jisme **SSH 0.0.0.0/0** (poori duniya) khula hota hai. Galti se ban jaye to instance pe Actions → Security → Change security groups se `jenkins-sg` laga, aur wizard wala SG delete kar |
| Storage | **30 GiB gp3**. "Advanced" khol ke **Encrypted: Yes** | Docker images jagah khaati hain; encryption = hardening |
| Advanced details → **Metadata version** | **V2 only (token required)** | IMDSv2: SSRF attacks se instance credentials churaana mushkil |
| Advanced details → Metadata response hop limit | **1** | Containers metadata tak nahi pahunch payenge |

**Launch instance** → Instances list mein state **Running** aur status checks **2/2 passed** hone de (1–2 min). Uska **Public IPv4 address** copy kar.

> Optional: **Elastic IP** (EC2 → Elastic IPs → Allocate → Associate with jenkins). Bina iske stop/start pe IP badal jaata hai aur GitHub webhook toot jaata hai.

## A4. SSH karna

```bash
ssh -i ~/.ssh/order-platform-key.pem ubuntu@<JENKINS_PUBLIC_IP>
```
- Ubuntu AMI ka default user **ubuntu** hai (Amazon Linux mein `ec2-user` hota hai).
- Pehli baar "Are you sure you want to continue connecting" → `yes`.

Andar aate hi system update kar:
```bash
sudo apt-get update && sudo apt-get upgrade -y
```

**Swap add kar** (4 GB RAM pe Maven build kabhi kabhi OOM se mar jaata hai):
```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h      # Swap: 2.0Gi dikhna chahiye
```

## A5. Java install

Jenkins aur hamara app Java 25 LTS use karte hain. Ubuntu 24.04 ke default repo mein Java 25 nahi hai, isliye Eclipse Temurin ka official repo add kar:
```bash
sudo apt-get install -y ca-certificates curl gnupg fontconfig
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
  | sudo gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
  | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt-get update
sudo apt-get install -y temurin-25-jdk
java -version        # openjdk version "25..."
```

## A6. Jenkins install

Jenkins Ubuntu ke default repo mein nahi hai, isliye Jenkins ka apt repo add karte hain:
```bash
# 1. Jenkins ki GPG key (packages verify karne ke liye)
#    Jenkins ne key rotate ki hai: ab 2026 wali chalti hai (2023 wali se "Unable to locate package jenkins")
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

# 2. Repo add
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list

# 3. Install
sudo apt-get update
sudo apt-get install -y jenkins

# 4. Start + boot pe auto-start
sudo systemctl enable --now jenkins
sudo systemctl status jenkins      # "active (running)"  → q dabake bahar
```
> Agar `apt-get update` pe **GPG / NO_PUBKEY error** aaye to Jenkins ne key rotate kar di hai. https://pkg.jenkins.io/debian-stable/ pe jaa ke current key ka URL le aur step 1 dobara chala.

Jenkins port **8080** pe chalta hai, user **jenkins** ke naam se, aur iska home `/var/lib/jenkins` hai.

## A7. Docker install + Jenkins ko docker group mein add karna

### Docker install (official repo se)
```bash
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world        # "Hello from Docker!"
```

### 🔑 docker group: ye sabse common interview/debug question hai

**Problem:** Jenkins pipeline mein `docker build` chalega to ye error aayega:
```
permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock
```

**Kyun aata hai?**
- Docker CLI daemon se baat karta hai ek Unix socket ke through: `/var/run/docker.sock`.
- Is socket ki permission dekh:
  ```bash
  ls -l /var/run/docker.sock
  # srw-rw---- 1 root docker 0 ... /var/run/docker.sock
  ```
  Matlab sirf **root** user aur **docker group** ke members isko read/write kar sakte hain.
- Jenkins `jenkins` user ke roop mein chalta hai, jo docker group mein nahi hai, isliye permission denied.

**Fix:**
```bash
sudo usermod -aG docker jenkins     # -a = append (baaki groups mat hatao!), -G = group
sudo usermod -aG docker ubuntu      # taaki tu bhi bina sudo ke docker chala sake
sudo systemctl restart jenkins      # ⚠ ZARURI
```

**Restart kyun zaruri hai?** Linux mein process ke groups process start hote waqt hi set hote hain. Jenkins pehle se chal raha tha (purani group list ke saath), isliye restart karna padta hai. `ubuntu` user ke liye logout karke dobara SSH kar (ya `newgrp docker`).

**Check:**
```bash
id jenkins                         # ... groups=...,docker  dikhna chahiye
sudo -u jenkins docker ps          # bina error ke empty list
```

> ⚠ **Security note:** docker group = practically root access (koi bhi `docker run -v /:/host` karke poora host padh sakta hai). Isliye Jenkins server pe sirf trusted logon ko access de. Real production mein Jenkins agents alag machines/pods pe chalte hain, ya rootless Docker / Kaniko use hota hai.

## A8. Baaki tools: Maven, Trivy, kustomize, conftest, Terraform

```bash
# Maven + git + jq + unzip
sudo apt-get install -y maven git jq unzip
mvn -version

# Trivy (image scanner)
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/trivy.gpg
echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
trivy --version

# Terraform (infra pipeline ke liye)
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo $VERSION_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
terraform version

# kustomize (GitOps repo mein image tag badalne ke liye)
curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.3/kustomize_v5.4.3_linux_amd64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin kustomize
kustomize version

# conftest (policy-as-code checks)
curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v0.56.0/conftest_0.56.0_Linux_x86_64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin conftest
conftest --version
```

### Sab tools install hue ya nahi: ek command se check
```bash
for t in java mvn git jq docker trivy terraform kustomize conftest; do printf "%-10s " $t; command -v $t >/dev/null && echo OK || echo MISSING; done
```
Har tool ke aage **OK** aana chahiye. **MISSING** aaye to us tool ka install step dobara chala.

**Command ka matlab:**
- `for t in ...; do ... done`: list ke har naam ke liye loop chalao.
- `printf "%-10s " $t`: naam ko 10 characters ki jagah mein left-align karke print karo, taaki output column jaisa seedha dikhe.
- `command -v $t`: batata hai ki ye command system pe kahan hai. Mili to exit code 0, nahi mili to non-zero.
- `>/dev/null`: path wala output chhupa do, humein sirf haan/na chahiye.
- `&& echo OK || echo MISSING`: command mili to "OK", nahi to "MISSING".

### Jenkins server pe har tool kya karta hai

| Tool | Kya hai | Is project mein kahan use hota hai | Real-world use case |
|---|---|---|---|
| **Java 25 LTS (Eclipse Temurin)** | Java runtime + compiler | Jenkins khud Java pe chalta hai, aur Maven isi JDK se app compile karta hai | Har Java/Spring app ka build aur run; Jenkins, Kafka, Elasticsearch jaise tools bhi Java pe chalte hain |
| **Jenkins** | CI/CD automation server | Dono pipelines chalata hai: `Jenkinsfile` (build → scan → push → promote) aur `Jenkinsfile.infra` (Terraform) | Har commit pe automatic build/test/deploy, approval gates, scheduled jobs |
| **Maven** (`mvn`) | Java build tool + dependency manager | Stage *Build & Unit Test*: `mvn -B -ntp clean verify`. Dependencies download, compile, JUnit tests, `order-service.jar` banana | Java projects ka standard build: dependencies (`pom.xml`), tests, packaging (jar/war) |
| **Git** | Version control | Jenkins code repo clone karta hai; `promote.sh`/`rollback.sh` GitOps repo clone, commit, push karte hain | Code history, branching, PRs; GitOps mein deploy = git commit |
| **jq** | Command-line JSON processor | `verify-deployment.sh` mein `/api/version` ke JSON se `.version` nikalna | API responses, AWS CLI output, config files se value nikalna (`aws ... \| jq '.Reservations[]'`) |
| **unzip** | Zip extract | Kuch tool releases zip mein aate hain (helper tool) | Downloads/artifacts extract karna |
| **Docker** (`docker-ce`) | Container engine | Stage *Docker Build*: app ki image banana; *Push Image*: Docker Hub pe push. Trivy bhi image yahin se padhta hai | Apps ko container mein pack karna, taaki "mere laptop pe chalta hai" wali problem khatam ho; local testing |
| **containerd.io** | Docker ke neeche ka container runtime | Docker isi se containers chalata hai (automatic) | Kubernetes nodes pe seedha containerd chalta hai (A13) |
| **docker-buildx-plugin** | Advanced image builder (BuildKit) | Fast, cache-friendly builds | Multi-platform images (amd64 + arm64), build cache |
| **Trivy** | Security scanner | Stage *Image Scan*: image mein CVEs dhoondhta hai; **fixable CRITICAL mile to pipeline fail**, image push nahi hoti | Images, filesystems, IaC (Terraform/K8s YAML) aur SBOM scan; supply-chain security |
| **Terraform** | Infrastructure as Code | `Jenkinsfile.infra`: har env ke cluster ka plan → policy check → apply | AWS/Azure/GCP infra code se banana, review karna (plan), reproducible environments |
| **kustomize** | K8s YAML customiser (base + overlays) | `promote.sh`: `kustomize edit set image` se env overlay mein naya image tag; `kustomize build` se final YAML render karke conftest ko dena | Ek base YAML se dev/staging/prod ke alag versions (replicas, image, config) bina copy-paste |
| **conftest** (OPA/Rego) | Policy-as-code tester | (1) Terraform plan JSON check (IMDSv2, encryption, open ports, tags). (2) Rendered K8s YAML check (latest tag, root user, limits, probes). Fail = deploy/apply ruk jaata hai | Company rules ko code mein likhna aur CI mein automatically enforce karna (security/compliance) |
| **curl** *(Ubuntu mein pehle se)* | HTTP client | Verify script app ko hit karta hai; Slack notifications bhejna | APIs test karna, health checks, webhooks |

### Kaun sa tool pipeline ke kis stage mein

```
Jenkinsfile (app):
  Checkout ............ git
  Build & Unit Test ... java + mvn
  Docker Build ........ docker (+ buildx, containerd)
  Image Scan .......... trivy
  Push Image .......... docker
  Deploy dev/stg/prod . git + kustomize + conftest (promote.sh)
                        curl + jq (verify-deployment.sh)
                        git (rollback.sh, sirf fail hone pe)
  Notifications ....... curl (Slack)

Jenkinsfile.infra:
  Validate ............ terraform fmt/validate
  Plan ................ terraform plan + show -json
  Policy check ........ conftest
  Apply ............... terraform apply
```

> Ye pura A5–A8 Terraform wale setup mein automatically hota hai: [terraform/modules/jenkins/user_data.sh](terraform/modules/jenkins/user_data.sh). Dono ko side-by-side padh, same commands milenge.

## A9. Jenkins first login + plugins

1. Browser: `http://<JENKINS_PUBLIC_IP>:8080`
2. "Unlock Jenkins" password:
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
3. **Install suggested plugins** → wait.
4. Admin user bana. **Username `admin` rakh** kyunki Jenkinsfile mein `APPROVERS = 'admin'` hai.
5. Jenkins URL: `http://<JENKINS_PUBLIC_IP>:8080/` → Save.

**Extra plugins:** Manage Jenkins → Plugins → Available:
- **Pipeline: Stage View** (stages ka visual)
- **GitHub** (webhook trigger; suggested mein aksar hota hai)
- **Timestamper**, **Workspace Cleanup**, **Credentials Binding**, **JUnit**: suggested mein aa jaate hain, check kar le

Install → "Restart Jenkins when installation is complete".

## A10. Jenkins credentials

Manage Jenkins → **Credentials** → System → Global credentials → **Add Credentials**:

| ID (exact yahi) | Kind | Username | Password | Kis liye |
|---|---|---|---|---|
| `dockerhub-creds` | Username with password | Docker Hub username | Docker Hub **access token** | Image push |
| `github-creds` | Username with password | GitHub username | GitHub **PAT** | GitOps repo mein commit/push |
| `slack-webhook` *(optional)* | **Secret text** | — | Slack incoming webhook URL (G2) | Pipeline notifications: approval pending, rollback, prod live, failure |

**GitHub PAT kaise banaye:** GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate → Repository access: `order-platform-gitops` (aur private ho to `order-platform` bhi) → Permissions: **Contents: Read and write** → Generate.

> Password ki jagah token kyun? Token scope-limited hota hai aur revoke ho sakta hai. Jenkins logs mein credentials `****` ho jaate hain.

## A11. Jenkins global environment variables

Pipeline ko har env ka app URL chahiye, taaki deploy ke baad verify kar sake. Manage Jenkins → **System** → Global properties → ✅ **Environment variables** → Add:

| Name | Value (example) |
|---|---|
| `DEV_APP_URL` | `http://10.0.1.25:30080` |
| `STAGING_APP_URL` | `http://10.0.0.48:30080` |
| `PROD_APP_URL` | `http://10.0.1.77:30080` |

Value = us cluster ke **kisi worker ka PRIVATE IP** + port `30080` (app ka NodePort). Terraform setup mein `terraform output app_url_for_jenkins` yahi deta hai.

**🧠 Ye variable karta kya hai? (interview ke liye)**
| Sawal | Jawab |
|---|---|
| Kaun use karta hai? | Jenkinsfile: `promoteAndVerify('dev', env.DEV_APP_URL, 900)`. Khaali ho to turant `DEV_APP_URL is not set in Jenkins global properties` error (mere build #5 mein yahi hua tha). |
| Kya karta hai? | Git commit (`promote.sh`) ke baad `scripts/verify-deployment.sh <URL> <IMAGE_TAG> 900` chalta hai. Har few second `<URL>/api/version` (version == naya tag?) aur `<URL>/api/orders` (HTTP 200?) check karta hai. |
| Pass kab? | **10 lagatar** sahi responses. Ek bhi galat hua to streak 0 se shuru, isliye aadha rolled-out ya aborted canary "success" nahi ginta. 900s mein na ho → FAILED → `rollback.sh` GitOps commit revert. |
| Jenkinsfile mein hardcode kyun nahi? | URL environment ka **data** hai, code nahi. Cluster dobara bana aur IP badla, to sirf Jenkins setting badlo, code commit nahi. Same Jenkinsfile har env ke liye. |
| 3 variables kyun? | Har env ka apna cluster aur URL. Pehle sirf `DEV_APP_URL` chahiye; `STAGING_APP_URL` / `PROD_APP_URL` tab, jab wo clusters banenge. |
| Credentials mein kyun nahi? | Ye secret nahi hai (sirf URL). Global properties ki env vars har build ko `env.X` ki tarah milti hain. |

Mera dev: `DEV_APP_URL = http://172.31.0.118:30080` (worker-1 private IP + order-service NodePort 30080).

> Private IP kyun? Jenkins aur clusters same VPC mein hain, aur cluster SG Jenkins SG se NodePorts allow karta hai. Public internet pe expose karne ki zarurat nahi.
>
> (Manual setup mein agar Jenkins default VPC mein hai aur cluster bhi, to bhi private IP chalega, bas cluster SG mein `jenkins-sg` se 30000-32767 allow karna (A13.1).)

## A12. Jenkins jobs + GitHub webhook

### Job 1: `order-platform-app`
New Item → name `order-platform-app` → **Pipeline** → OK:
- ✅ **GitHub project**: `https://github.com/<you>/order-platform/`
- Build Triggers: ✅ **GitHub hook trigger for GITScm polling**
- Pipeline → Definition: **Pipeline script from SCM**
  - SCM: Git, Repository URL: `https://github.com/<you>/order-platform.git`
  - Credentials: `github-creds` (repo private ho to)
  - Branch: `*/main`
  - Script Path: `Jenkinsfile`
- Save.

### Job 2: `order-platform-infra`
Same, lekin:
- Build Triggers: kuch nahi (infra manually trigger karna safer hai)
- Script Path: `Jenkinsfile.infra`

> Infra job ko AWS access chahiye. Terraform wale Jenkins mein ye **IAM instance profile** se aata hai (koi keys store nahi). Manual Jenkins pe: IAM → Roles → Create role → EC2 → `AmazonEC2FullAccess` + state bucket ki S3 access → EC2 → jenkins instance → Actions → Security → **Modify IAM role**.

### GitHub webhook
GitHub → `order-platform` repo → Settings → **Webhooks → Add webhook**:
- Payload URL: `http://<JENKINS_PUBLIC_IP>:8080/github-webhook/` (**last `/` zaruri hai**)
- Content type: `application/json`
- Events: Just the push event → Add.

Recent Deliveries mein green ✅ dikhna chahiye. Red ❌ aaye to SG mein GitHub CIDRs check kar (A2).

> Pehla build **manually "Build Now"** kar. Jenkins pehli run ke baad hi webhook trigger "yaad" rakhta hai. Pehla build "parameters" bhi register karta hai, to agle se **Build with Parameters** dikhega.

---

## A13. Kubernetes cluster manually (kubeadm)

Hum 1 master (control plane) + 2 workers banayenge. EKS nahi, **apna khud ka cluster EC2 pe**, taaki pata chale andar kya hota hai.

```
 ┌──────── master (control plane) ────────┐       ┌─ worker-0 ─┐ ┌─ worker-1 ─┐
 │ kube-apiserver  etcd  scheduler         │◄─────►│ kubelet     │ │ kubelet    │
 │ controller-manager  kubelet  calico     │       │ kube-proxy  │ │ kube-proxy │
 └─────────────────────────────────────────┘       │ calico      │ │ calico     │
                                                   │ YOUR PODS   │ │ YOUR PODS  │
                                                   └─────────────┘ └────────────┘
```

### A13.1 Security group: `k8s-sg`
| Type | Port | Source | Kyun |
|---|---|---|---|
| All traffic | All | **k8s-sg khud (self)** | Nodes aapas mein: kubelet 10250, etcd, Calico IPIP (protocol 4), BGP 179 |
| SSH | 22 | My IP | |
| Custom TCP | 6443 | My IP | kubectl laptop se |
| Custom TCP | 30000-32767 | My IP | NodePorts: app, Argo CD UI, Grafana |
| Custom TCP | 30000-32767 | **jenkins-sg** | Jenkins post-deploy verification |

> "Self" rule kaise: pehle SG bina us rule ke bana (SG bana hi nahi to khud ko select kaise karega), phir Edit inbound → Add rule → All traffic → Source **Custom** → `k8s-sg` ka hi `sg-...` ID select kar.

**🧠 Kyun (interview ke liye):**
- **Self rule kyun?** Ye rule kehta hai ki is SG wali machines aapas mein kuch bhi baat kar sakti hain. Nodes ko bahut saare ports chahiye: kubelet 10250, API 6443, Calico BGP 179. **Calico IPIP to TCP/UDP hai hi nahi, wo IP protocol 4 hai.** Har port alag kholna mushkil hai aur galti ka chance zyada hai. "All traffic sirf apne SG se" safe bhi hai, kyunki bahar ki duniya ke liye sab band hi rehta hai.
- **Source mein IP ki jagah SG kyun?** Node ka IP stop/start pe badal sakta hai, aur naya node bhi add ho sakta hai. SG reference ka matlab hai "jis bhi machine pe ye SG laga hai", to rule kabhi purana nahi hota.
- **`jenkins-sg` → 30000-32767:** Jenkins deploy ke baad `verify-deployment.sh` se app ka `/actuator/health` aur version check karta hai, NodePort pe. Jenkins kabhi cluster API (6443) ko touch nahi karta. Uska kaam sirf image push karna aur GitOps commit karna hai.
- **6443 aur 22 sirf My IP se:** API server aur SSH internet pe khule hon to bots minutes mein brute-force shuru kar dete hain.
- **Outbound "All traffic" zaroori hai:** SG stateful hai, lekin naya bahar jaane wala connection (apt, image pull, pkgs.k8s.io) outbound rule ke bina nahi jaata (Problem #5).

**Check (laptop Git Bash, read-only):**
```bash
aws ec2 describe-security-group-rules --region ap-south-1   --filters Name=group-id,Values=<k8s-sg-id>   --query "SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId]" --output table
# 5 inbound (IsEgress=False) + 1 outbound (True, -1, 0.0.0.0/0)
```

### A13.2 3 EC2 launch kar
A3 jaisa hi, bas: Name `k8s-master` (1) aur `k8s-worker` (Number of instances: 2), **c7i-flex.large** (paid account: t3.medium), SG `k8s-sg`, 30 GB encrypted, IMDSv2.

| Field | Value |
|---|---|
| Name | `k8s-master` (Number of instances 1), phir doosra launch `k8s-worker` (Number of instances **2**) → baad mein ✏️ se `k8s-worker-1` / `k8s-worker-2` |
| AMI | Ubuntu Server 24.04 LTS, **64-bit (x86)** (ARM nahi) |
| Instance type | **c7i-flex.large** (Free plan pe t3 block, Problem #1) |
| Key pair | `order-platform-key` |
| Network → Edit | Auto-assign public IP: Enable · **Select existing SG → `k8s-sg`** (launch-wizard nahi) |
| Storage | 30 GiB · gp3 · Advanced → **Encrypted: Yes** |
| Advanced details | Metadata version **V2 only (token required)** · hop limit **1** |

> **c7i-flex.large / t3.medium kyun?** kubeadm ko master pe minimum 2 CPU + 2 GB chahiye. micro instances pe `kubeadm init` preflight mein hi fail ho jaata hai.

> **vCPU hisaab (Free plan quota 8):** Jenkins 2 + master 2 + 2 workers × 2 = **8**. 9th vCPU wali machine `VcpuLimitExceeded` degi. Terminate ki hui machine "terminated" hone tak (1–2 min) quota gherti hai.

> ⚠️ **Encryption bhool gaye?** (Mere saath hua: pehla master `Encrypted: False` bana.) EBS encryption launch ke baad ON nahi hoti (snapshot → encrypted copy → naya volume, jhanjhat). Khaali machine hai to **terminate karke dobara launch** karna sabse aasaan hai. Aage ke liye: **EC2 → Account attributes → Data protection and security → EBS encryption → Manage → ☑ Always encrypt new EBS volumes**. Isse region ke saare naye disks apne aap encrypted banenge.
>
> **Kyun zaroori?** Disk/snapshot leak ho jaye to bhi data KMS key ke bina padha nahi ja sakta. Ye compliance (CIS benchmark) ka basic check hai, aur performance pe koi asar nahi.

**Check (read-only):**
```bash
aws ec2 describe-instances --region ap-south-1   --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress,SecurityGroups[0].GroupName,MetadataOptions.HttpTokens]" --output table
aws ec2 describe-volumes --region ap-south-1 --query "Volumes[].[Attachments[0].InstanceId,Size,VolumeType,Encrypted]" --output table
# sab nodes: c7i-flex.large, k8s-sg, required · sab volumes: 30 gp3 True
```

### A13.3 SAARE 3 nodes pe (master + workers)

Har node pe SSH karke ye chala (ya 3 terminals khol ke):

```bash
# --- 1. Swap off (kubelet swap ke saath chalne se mana karta hai) ---
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# --- 2. Kernel modules ---
#  overlay      : container filesystems ke liye
#  br_netfilter : bridge traffic ko iptables se pass karwane ke liye (Service routing)
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# --- 3. sysctl: IP forwarding + bridge iptables ---
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# --- 4. containerd (container runtime) ---
sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
# kubelet systemd cgroup driver use karta hai, to containerd ko bhi wahi chahiye.
# Mismatch hua to pods random restart hote hain.
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd
containerd --version                                  # 2.x hona chahiye (k8s 1.36+ containerd 1.x support nahi karta)
grep -n 'SystemdCgroup' /etc/containerd/config.toml   # "SystemdCgroup = true" dikhna chahiye

# --- 5. kubeadm, kubelet, kubectl ---
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl   # galti se upgrade na ho
sudo systemctl enable kubelet
```

**🧠 Har step kyun (interview ke liye):**

| Step | Kyun |
|---|---|
| **Swap off** | kubelet memory ka hisaab RAM ke hisaab se karta hai. Swap ho to pod ki memory limits ka matlab bigad jaata hai, isliye kubelet by default swap pe start hi nahi hota. |
| **overlay** | Container images ki layers ek ke upar ek jodne wala filesystem. |
| **br_netfilter + bridge-nf-call-iptables** | Pod ka traffic Linux bridge se jaata hai. Ye setting usko iptables se guzaarti hai, taaki **Service (ClusterIP)** ke rules lagein. |
| **ip_forward = 1** | Node ko router banne deta hai, taaki doosre node ke pod ka packet aage bhej sake. |
| **containerd 2.x** | Kubernetes 1.36 se containerd 1.x support khatam ho gaya hai. Ubuntu 24.04 ke updates mein containerd 2.2 aata hai, isliye ye sahi baith jaata hai. |
| **SystemdCgroup = true** | kubelet aur containerd dono ek hi cgroup manager (systemd) use karein. Mismatch ho to pods random restart hote hain. |
| **apt-mark hold** | `apt upgrade` galti se Kubernetes ka version na badal de. Cluster upgrade hamesha soch-samajh ke, `kubeadm upgrade` se hota hai. |

**Check (har node pe):**
```bash
free -h | grep -i swap                                          # Swap: 0B
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables   # dono = 1
containerd --version; systemctl is-active containerd            # 2.x, active
grep -n 'SystemdCgroup' /etc/containerd/config.toml             # = true
kubeadm version -o short                                        # v1.36.x
apt-mark showhold                                               # kubeadm kubectl kubelet
```

> **Docker kyun nahi?** Kubernetes 1.24 se dockershim hat gaya. Ab kubelet seedha **containerd** se CRI ke through baat karta hai. Docker sirf Jenkins pe image *build* karne ke liye hai.

### A13.4 Sirf MASTER pe
```bash
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)

sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=$PRIVATE_IP \
  --apiserver-cert-extra-sans=$PUBLIC_IP,$PRIVATE_IP
```
- `--pod-network-cidr=192.168.0.0/16`: Calico ka default pod range.
- `--apiserver-cert-extra-sans`: API server certificate mein public IP bhi daalta hai, taaki laptop se kubectl kaam kare.

> ⚠️ **Sirf `kubeadm init` likha (bina `sudo`, bina flags)?** Output: `[ERROR IsPrivilegedUser]: user is not running as root` aur `remote version is much newer: v1.37.1; falling back to: stable-1.36`. Preflight pehle hi ruk gaya, kuch bana nahi, to koi cleanup nahi chahiye. Upar wala **poora** command `sudo` ke saath chala. Bina flags ke pod CIDR set nahi hota (Calico ka IP pool galat banta) aur certificate mein public IP nahi jaata (laptop kubectl x509 error deta).
> - **`falling back to stable-1.36` ka matlab:** kubeadm internet pe latest stable (1.37.1) dekhta hai. Wo installed kubeadm (1.36) se zyada naya hai, isliye apne minor version (1.36.x ka latest patch) pe hi rehta hai. kubeadm apne se naya control plane install nahi karta.

- `--apiserver-advertise-address=$PRIVATE_IP`: API server ko VPC ke andar wale IP pe announce karta hai. Workers isi pe join karte hain. Private IP stop/start pe nahi badalta, public IP badal jaata hai.

**🧠 `kubeadm init` andar kya karta hai (interview ke liye):**
| Phase | Kya hota hai |
|---|---|
| preflight | CPU ≥ 2, RAM, swap off, ports free, containerd chal raha hai, sab check karta hai |
| certs | `/etc/kubernetes/pki` mein cluster ka **CA** aur apiserver/etcd/kubelet ke certificates banata hai |
| kubeconfig | `admin.conf`, `kubelet.conf`, `controller-manager.conf`, `scheduler.conf` banata hai |
| control-plane | `/etc/kubernetes/manifests/` mein **static pod** YAML likhta hai (apiserver, controller-manager, scheduler, etcd). kubelet in files ko dekh ke khud pods chala deta hai, API server ke bina bhi. |
| bootstrap-token | Workers ke join ke liye ek token (24h valid) |
| addons | **CoreDNS** (cluster DNS) aur **kube-proxy** (Service → pod routing) install karta hai |

- **CoreDNS `Pending` kyun dikhta hai?** CNI (Calico) lagne tak pod network hai hi nahi, isliye node `NotReady` rehta hai aur CoreDNS schedule nahi hota. Ye normal hai.
- **`admin.conf` = cluster-admin ki chaabi.** Isme client certificate hai jiske paas poore cluster ka full access hai. Ise kabhi GitHub/chat mein mat daalna.
- **Join command (token + hash) chat ya screenshot mein share mat kar.** Token 24h valid hai. Port 6443 sirf tere IP se khula hai, phir bhi secret ko secret hi rakh.

Output ke end mein ek **`kubeadm join ...`** command aayegi. **Copy karke rakh.**

kubectl setup (ubuntu user ke liye):
```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes      # master "NotReady" dikhega, kyunki network plugin abhi nahi laga
```

**Calico (pod network) install:**
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
kubectl get pods -n kube-system -w      # calico-node Running → Ctrl+C
kubectl get nodes                       # ab "Ready"
```
**Output kaise padhe (`kubectl get pods -n kube-system`):**
| Pod | Kya hai | Kitne |
|---|---|---|
| `etcd-*`, `kube-apiserver-*`, `kube-controller-manager-*`, `kube-scheduler-*` | Control plane **static pods**. Naam mein node ka naam hota hai, kyunki ye usi node ki manifest files se bane hain. | 1 each (sirf master) |
| `kube-proxy-*` | **DaemonSet**: har node pe ek (Service → pod iptables rules) | nodes jitne |
| `calico-node-*` | **DaemonSet**: har node pe ek (pod IPs, routes, NetworkPolicy) | nodes jitne |
| `calico-kube-controllers-*` | Deployment: Calico ka cluster-level controller | 1 |
| `coredns-*` | Deployment: cluster DNS (`svc-name.namespace.svc.cluster.local`) | 2 (HA) |

`kubectl get nodes -o wide` mein dekh: `STATUS Ready`, `VERSION v1.36.x`, `INTERNAL-IP` = private IP, `CONTAINER-RUNTIME containerd://2.x`. `EXTERNAL-IP <none>` normal hai, kyunki kubeadm ko AWS ka public IP pata nahi hota (cloud-controller-manager nahi hai).

> Calico kyun (Flannel nahi)? Flannel **NetworkPolicy support nahi karta**. Hamare project mein default-deny network policies hain, wo Calico hi enforce karega.

### A13.5 Har WORKER pe
Master se copy ki hui command `sudo` ke saath:
```bash
sudo kubeadm join 172.31.x.x:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234...
```
- **token**: worker ko cluster join karne ki permission (24h valid).
- **ca-cert-hash**: worker verify karta hai ki wo *asli* master se baat kar raha hai (MITM protection).

> ⚠️ **`<token>` / `<hash>` waise hi paste kar diya?** Output: `-bash: syntax error near unexpected token 'newline'`. Bash mein `<` / `>` **redirection** hain, isliye command chali hi nahi (koi nuksaan nahi). Asli values chahiye. Join command kho gayi ho to master pe `sudo kubeadm token create --print-join-command` chala. Ye poori ready line deta hai. Worker pe `sudo ` likh ke paste kar.

**Join ke baad token delete kar (achhi aadat):** sab workers join ho gaye to token ka koi kaam nahi. Agar wo galti se screenshot/chat mein dikh gaya ho (mere saath hua), to aur bhi zaroori hai:
```bash
kubeadm token list                          # master pe (kubectl wala user)
sudo kubeadm token delete <token-id>        # token-id = token ka pehla hissa (dot se pehle, 6 characters)
```

**Output kaise padhe (`kubeadm init`):**
- `Creating static Pod manifest`: etcd/apiserver/controller-manager/scheduler ki YAML `/etc/kubernetes/manifests` mein likhi gayi.
- `kube-apiserver is healthy`: API server zinda hai.
- `taints [node-role.kubernetes.io/control-plane:NoSchedule]`: master pe app ke pods schedule nahi honge, sirf workers pe. Isse control plane ko resources ki kami nahi hoti.
- `[bootstrap-token] ... csrapprover`: worker token se apna client certificate maangta hai (CSR), aur wo auto-approve hota hai.
- `[addons] CoreDNS, kube-proxy`: cluster DNS + Service routing.

Token expire ho gaya? Master pe naya bana:
```bash
kubeadm token create --print-join-command
```

Master pe check:
```bash
kubectl get nodes -o wide
# NAME              STATUS   ROLES           VERSION
# ip-172-31-1-10    Ready    control-plane   v1.36.x
# ip-172-31-1-11    Ready    <none>          v1.36.x
# ip-172-31-1-12    Ready    <none>          v1.36.x
```

### A13.6 Laptop se kubectl
```bash
scp -i ~/.ssh/order-platform-key.pem ubuntu@<MASTER_PUBLIC_IP>:~/.kube/config ~/.kube/order-platform-dev
# file mein server: https://<private-ip>:6443 ko public IP se replace kar:
sed -i "s|server: https://.*:6443|server: https://<MASTER_PUBLIC_IP>:6443|" ~/.kube/order-platform-dev
export KUBECONFIG=~/.kube/order-platform-dev
kubectl get nodes
```
(Terraform setup mein ye kaam `scripts/get-kubeconfig.sh` karta hai.)

> Ye pura A13 Terraform mein [templates/common.sh](terraform/modules/k8s-cluster/templates/common.sh), [master.sh.tpl](terraform/modules/k8s-cluster/templates/master.sh.tpl) aur [worker.sh.tpl](terraform/modules/k8s-cluster/templates/worker.sh.tpl) mein automated hai. Terraform version extra hardening bhi karta hai: API audit logs, profiling off, aur pehle se generated CA jisse workers hash pin karte hain.

## A14. Argo CD manually install karna

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml
kubectl get pods -n argocd -w        # sab Running → Ctrl+C
```
> `--server-side` kyun? Argo CD ke CRDs bahut bade hain. Normal `kubectl apply` "annotation too long" error de deta hai.
>
> `--force-conflicts` kyun? Server-side apply har field ka "owner" (field manager) yaad rakhta hai. Re-install/upgrade pe agar koi field kisi aur manager ne set ki thi to conflict aata hai. Ye flag bolta hai "is file ki value jeete".

> **Versions (Oct 2026, k8s v1.36 ke liye):** Argo CD **v3.5.6** (official docs: 3.5 tested on k8s 1.33–1.36; purana v2.12 1.36 pe tested nahi tha). GitOps add-ons bhi update kiye: kube-prometheus-stack **92.11.0** (65.1.1 tha), argo-rollouts chart **2.43.8** (app v1.10.1), kyverno chart **3.9.2** (Kyverno v1.19.2). Upgrade se pehle `helm template --kube-version 1.36.5` se purana vs naya render karke check kiya ki hamari values (NodePorts 30090/30300, grafana-admin secret, alertmanager-slack secret, ServiceMonitors) dono mein lag rahi hain. Kyverno 1.19 mein `spec.validationFailureAction` **deprecated** hai (rule-level `failureAction` naya tareeka), lekin abhi bhi chalta hai.

**UI expose (NodePort 30443):**
```bash
kubectl -n argocd patch svc argocd-server \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30443,"protocol":"TCP"}]}}'
```
Browser: `https://<WORKER_PUBLIC_IP>:30443`. Self-signed cert warning aayegi → Advanced → Proceed.

**🧠 Kyun (interview ke liye):**
| Cheez | Kyun |
|---|---|
| Argo CD | GitOps controller: cluster ke andar se Git repo dekhta hai aur cluster ko Git jaisa banata hai. Jenkins cluster ko kabhi touch nahi karta, sirf Git mein tag likhta hai (**pull model**). Cluster credentials CI mein nahi rehte. |
| 7 pods | application-controller (Git vs cluster compare + sync), repo-server (git clone + helm/kustomize render), server (UI/API), redis (cache), dex (SSO), applicationset-controller, notifications-controller |
| NodePort 30443 | Har node ke 30443 pe service khulti hai; k8s-sg mein 30000-32767 sirf My IP se khula hai |
| Self-signed cert warning | Connection encrypted hai, bas kisi public CA ne sign nahi kiya. Production: Ingress + cert-manager/Let's Encrypt |
| `base64 -d` | Secret values base64 **encoding** hain, encryption nahi. Asli suraksha = Secret padhne ka RBAC (+ etcd encryption at rest) |
| Initial secret delete | Password badalne ke baad purana password ek faltu secret ban jaata hai. Argo CD docs bhi delete karne ko kehte hain |

**Check:** `kubectl get pods -n argocd` → 7 pods Running (application-controller-0 StatefulSet hai, baaki Deployments). `kubectl -n argocd get svc argocd-server` → `443:30443/TCP`.

**Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
Username: `admin`. Login ke baad User Info → **Update password**, phir initial secret delete kar de:
```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

**Monitoring secrets pehle bana** (Git mein nahi jaate; Terraform wala bootstrap ye khud karta hai). Inke bina Grafana aur Alertmanager pods start nahi honge:
```bash
kubectl create namespace monitoring
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 18)"
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/REPLACE/ME/PLEASE'   # asli URL: G2
```

**Root app (app-of-apps) apply kar.** Ye ek Application hai jo `clusters/dev/` folder ki saari Applications banata hai (Prometheus stack, Rollouts, Kyverno, policies, monitoring-config, order-service):
```bash
# gitops repo already GitHub pe push hona chahiye (B4)
kubectl apply -f gitops/bootstrap/root-dev.yaml
```
**🧠 Kyun (interview ke liye):**
- **App-of-apps:** haath se sirf 1 Application (`root`) bani. Wo `clusters/dev/` padhti hai jisme baaki Applications ki YAML hai. Naya addon = Git mein file. Pura cluster Git se rebuild ho sakta hai (disaster recovery).
- **Sync waves:** `-4` kube-prometheus-stack (ServiceMonitor/PrometheusRule CRDs), `-3` argo-rollouts (Rollout CRD) + kyverno, `-1` kyverno-policies + monitoring-config, `0` order-service. CRD pehle na ho to uske objects apply hi nahi hote.
- **Secrets Git mein nahi:** Git history se ek baar commit hua secret kabhi nahi mitta. Production: External Secrets / Sealed Secrets / Vault. `openssl rand -base64 18` = 24-char random password jo kahin likha hi nahi; zaroorat pe Secret se padho: `kubectl -n monitoring get secret grafana-admin -o jsonpath="{.data.admin-password}" | base64 -d; echo`
- **`automated: prune + selfHeal`:** selfHeal = koi `kubectl edit` kare to Argo CD wapas Git jaisa kar deta hai (drift correction); prune = Git se file hatao to cluster se resource bhi hatega.

Argo CD UI mein dekh: `root` → phir `kube-prometheus-stack`, `argo-rollouts`, `kyverno`, `kyverno-policies`, `monitoring-config`, `order-service` apne aap bante jayenge. 5–10 minute lagenge. `order-service` tab tak **ImagePullBackOff/Degraded** dikhega jab tak Jenkins pehla image push na kare. Ye normal hai (tag `0.0.0` exist nahi karta).

**Manual part complete! 🎉** Ab tujhe pata hai andar kya hota hai. Ab sab delete kar (EC2 terminate, SGs delete) aur Part B se code ke through bana.

---

# PART B: TERRAFORM (asli project ka tareeka)

## B1. Placeholders bharna

Code mein `YOUR_GITHUB_USER`, `YOUR_DOCKERHUB_USER`, `YOUR_TF_STATE_BUCKET`, `YOUR_KEY_PAIR_NAME`, `YOUR_ADMIN_CIDR`, `YOUR_ALERT_EMAIL` jaise placeholders hain. Ek command se sab bhar (**Git Bash** mein, project folder se):

```bash
cd /e/Project2
bash scripts/configure.sh \
  --github-user     <tera-github-username> \
  --dockerhub-user  <tera-dockerhub-username> \
  --state-bucket    <unique-naam>-order-platform-tfstate \
  --key-name        order-platform-key \
  --alert-email     <tera-email@example.com>
# --admin-cidr optional hai; nahi diya to tera current IP/32 khud detect karega
```
- Saare flags zaruri hain (`--admin-cidr` chhod ke). Ek bhi missing hua to script usage dikha ke ruk jayegi.
- S3 bucket naam **poori duniya mein unique** hona chahiye (lowercase, no underscores).
- Key pair (A1) us region (ap-south-1) mein exist karna chahiye.
- `--alert-email` pe CloudWatch alarms ke emails aayenge (G3).
- `.md` files (ye guide, README, runbooks) mein placeholders **replace nahi hote**. Runbook links alert YAML mein hain, wahan replace ho jaate hain.

## B2. Terraform state bucket

**State kya hai?** Terraform yaad rakhta hai ki usne kya banaya, `terraform.tfstate` file mein. Team/Jenkins sab same state use karein, isliye usko S3 mein rakhte hain (remote backend). Versioning on hai (purana state recover ho sake), aur `use_lockfile` se do log ek saath apply nahi kar sakte.

```bash
cd terraform/bootstrap
terraform init
terraform plan       # padh: 5 resources banenge
terraform apply      # "yes"
```
> Ye bucket `prevent_destroy` se protected hai. Galti se delete nahi hoga.

## B3. Shared stack (VPC + Jenkins)

```bash
cd ../stacks/shared
terraform init -backend-config=../../backend.hcl
terraform plan
terraform apply
```
Kya banta hai:
- **VPC** `10.0.0.0/16`, 2 public subnets, internet gateway, aur default SG locked (koi rule nahi).
- **Jenkins EC2** (c7i-flex.large, IMDSv2, encrypted disk) + **Elastic IP** + SG (22/8080 sirf tera IP, 8080 GitHub hooks) + **IAM role**. Role mein: EC2, state bucket, aur cluster stack ke liye `order-platform-*` naam wale IAM roles, CloudWatch alarms/dashboards aur log groups banane ki permission, taaki Jenkins Terraform chala sake.
- User-data script A5–A8 ka sab kuch install karta hai, plus **CloudWatch agent** (memory/disk metrics + logs → `/order-platform-shared/jenkins`).
- **SNS topic** `order-platform-alerts` + tera email subscription. Saare CloudWatch alarms yahin notify karte hain.
- **Jenkins ke CloudWatch alarms** + dashboard `order-platform-shared-nodes` (G9).

Output:
```bash
terraform output
# jenkins_url          = "http://13.x.x.x:8080"
# jenkins_ssh          = "ssh -i <path>.pem ubuntu@13.x.x.x"
# alerts_topic_arn     = "arn:aws:sns:ap-south-1:...:order-platform-alerts"
# cloudwatch_dashboard = "https://ap-south-1.console.aws.amazon.com/cloudwatch/..."
```
> 📧 **Abhi email check kar** aur SNS subscription **Confirm** kar (G3). Warna CloudWatch alerts kabhi nahi aayenge.
**3–5 minute ruk** (user-data chal raha hai). Progress dekhni ho:
```bash
ssh -i ~/.ssh/order-platform-key.pem ubuntu@<ip> 'sudo tail -f /var/log/user-data.log'
```
Last line "Bootstrap complete" ke baad initial admin password bhi wahi log mein print hota hai.

## B4. GitHub pe 2 repos push karna

GitHub pe 2 **empty** repos bana (README mat add kar):
1. `order-platform` (private bhi chalega)
2. `order-platform-gitops` (**public** rakh: isme koi secret nahi hai aur Argo CD bina credentials ke padh lega. Private chahiye to Argo CD mein repo credentials add karne padenge: Settings → Repositories.)

```bash
# Repo 1: main code (gitops/ folder .gitignore mein hai, wo isme nahi jayega)
cd /e/Project2
git init -b main
git add .
git commit -m "Initial commit: order platform"
git remote add origin https://github.com/<you>/order-platform.git
git push -u origin main

# Repo 2: gitops
cd gitops
git init -b main
git add .
git commit -m "Initial GitOps state"
git remote add origin https://github.com/<you>/order-platform-gitops.git
git push -u origin main
```
> `.gitattributes` saari files ko LF line endings mein rakhta hai. Windows ka CRLF EC2 pe bash scripts tod deta hai (`$'\r': command not found`).

## B5. Jenkins configure

Tools already install hain, bas UI wala kaam:
- **A9** (unlock, plugins, admin user)
- **A10** (credentials; `slack-webhook` bhi daal de, G2)
- **A12** (dono jobs + webhook)
- **A11** (APP_URLs): ye cluster banne ke baad (B6) bharega.

## B6. Clusters banana (dev → staging → prod)

### Option 1: Jenkins infra pipeline (recommended, yahi "infra promotion" hai)
Jenkins → `order-platform-infra` → **Build Now**:
1. `Validate`: fmt + validate
2. `Plan: dev` → conftest policy check → `Apply: dev` (dev ko auto-apply)
3. `Plan: staging` → policy → **⏸ Approval** → `Apply: staging`
4. `Plan: prod` → policy → **⏸ Approval** → `Apply: prod`

Approve karne se pehle build ke **Artifacts** mein `staging.plan.txt` khol ke padh ki kya change hoga. Sirf dev chahiye to staging approval pe **Abort** daba de.

### Option 2: Laptop se (sirf dev, seekhne ke liye)
```bash
cd terraform/stacks/cluster
terraform init -reconfigure -backend-config=../../backend.hcl \
               -backend-config=key=cluster/dev/terraform.tfstate
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```
> **Ek code, 3 environments:** `stacks/cluster` ka code same hai. Farq sirf `envs/<env>.tfvars` (size, worker count) aur state key (`cluster/<env>/...`) ka hai. `-reconfigure` zaruri hai jab env badlo, warna galat state use ho sakta hai.

### Cluster banne mein kya hota hai (automatically)
1. Terraform: CA certificate + join token generate, SG, **node IAM role** (CloudWatch agent ke liye), **log groups**, master + workers EC2.
2. Master user-data: containerd + kubeadm (A13.3), **CloudWatch agent**, `kubeadm init` (audit logging ke saath), Calico, **monitoring secrets** (Grafana random password + Slack placeholder), **Argo CD install**, **root app apply**.
3. Worker user-data: same base setup + CloudWatch agent, master ka wait, `kubeadm join` (CA hash pinned).
4. Terraform: har node ke **CloudWatch alarms** + 2 composite alarms + dashboard `order-platform-<env>-nodes`.
5. Argo CD: `clusters/<env>/` padhta hai. Pehle kube-prometheus-stack, phir Rollouts + Kyverno (metrics on), phir Kyverno policies + monitoring-config (alerts, dashboards), phir order-service.

**~10–15 minute** lagte hain.

### Option 3: VPC aur Jenkins haath se bane hain (shared stack nahi) — hamne yahi kiya (Batch 12)

Part A ki tarah agar Jenkins aur VPC (default VPC) **manually** bane hain, to shared stack ki state hai hi nahi, aur cluster stack use padh nahi payega. Tab tfvars mein ye **override** variables do (set hone pe shared state padhi hi nahi jaati):

```hcl
# envs/staging.tfvars (prod same)
worker_instance_type      = "m7i-flex.large"   # 8 GB: add-ons ~3.6 GB + app
worker_count              = 1                  # 16 vCPU quota: Jenkins 2 + dev 6 + staging 4 + prod 4
vpc_id                    = "vpc-xxxxxxxx"     # default VPC
subnet_ids                = ["subnet-xxxxxxxx"]
jenkins_security_group_id = "sg-xxxxxxxx"      # jenkins-sg (NodePorts allow → Jenkins verify)
# alerts_topic_arn nahi diya → CloudWatch alarms banenge, email nahi
```

```bash
# 1. Ek baar: state bucket (local state; anda-murgi: bucket abhi bana hi nahi)
cd terraform/bootstrap
aws sts get-caller-identity --query Arn --output text
terraform init && terraform plan          # 5 to add: bucket, versioning, AES256, public block, ownership
terraform apply                            # bootstrap/terraform.tfstate delete MAT karna

# 2. Har env (staging, phir prod)
cd ../stacks/cluster
terraform init -reconfigure -backend-config=../../backend.hcl -backend-config=key=cluster/staging/terraform.tfstate
terraform plan -var-file=envs/staging.tfvars -out=staging.tfplan   # 29 to add, 0 destroy
terraform apply staging.tfplan                                     # saved plan = yes nahi poochta

# 3. Bina SSH progress (CloudWatch Logs; Git Bash mein path conversion band)
export MSYS_NO_PATHCONV=1
aws logs get-log-events --log-group-name /order-platform-staging/nodes \
  --log-stream-name <master-instance-id>/bootstrap --limit 5 --query 'events[].message'
# → "Control plane bootstrap complete" (~3 min); worker → "Worker joined"

# 4. Kubeconfig + check
cd /e/Project2 && bash scripts/get-kubeconfig.sh staging ~/.ssh/order-platform-key.pem
export KUBECONFIG=~/.kube/order-platform-staging
kubectl get nodes && kubectl -n argocd get applications

# 5. Jenkins: STAGING_APP_URL / PROD_APP_URL = terraform output app_url_for_jenkins (private IP)
```

| Kyun | |
|---|---|
| `-out` + `apply <file>` | Jo plan review kiya wahi apply; beech mein state badli to apply fail |
| Prod plan mein `0 to destroy` | Destroy dikhe = backend abhi bhi staging pe (`-reconfigure` / key check) |
| Har env apna SG | Dev/staging/prod network level pe alag |
| `.terraform.lock.hcl` commit nahi | Laptop wali file mein sirf Windows hashes; Jenkins (Linux) pe fail |
| Staging/prod order-service `ImagePullBackOff` | Placeholder `0.0.0`; Jenkins pehla promote karega tab theek |

## B7. Cluster check karna

```bash
cd terraform/stacks/cluster
terraform output        # argocd_url, grafana_url, app_url, app_url_for_jenkins, cloudwatch_dashboard

# kubeconfig laptop pe
bash ../../../scripts/get-kubeconfig.sh dev ~/.ssh/order-platform-key.pem
export KUBECONFIG=~/.kube/order-platform-dev

kubectl get nodes                       # 3 Ready
kubectl get applications -n argocd      # sab Synced (order-service Degraded until first build)
kubectl get pods -A
```
Bootstrap ka log dekhna ho:
```bash
ssh -i ~/.ssh/order-platform-key.pem ubuntu@<master-ip> 'sudo tail -50 /var/log/k8s-bootstrap.log'
```
Argo CD password (A14 jaisa):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
Grafana password (G1):
```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```
**Slack webhook lagana mat bhoolna.** Bootstrap ne placeholder daala hai, asli URL G2 step 2 se daal. Phir G11 ka test alert bhej ke confirm kar ki Slack pe message aa raha hai.

Ab **Jenkins → A11** mein `DEV_APP_URL = <app_url_for_jenkins>` daal (staging/prod ke liye bhi).

Phir app job chala: Jenkins → `order-platform-app` → **Build with Parameters** → Build. 🚀

---

## C. Pura flow: commit se prod tak

Maan le tune `OrderController.java` mein change karke `git push` kiya:

| # | Kahan | Kya hota hai | Fail hua to? |
|---|---|---|---|
| 1 | GitHub | Push event → webhook → Jenkins | |
| 2 | Jenkins `Init` | Tag banta hai `<build>-<sha7>` e.g. `42-a1b2c3d` | |
| 3 | `Build & Unit Test` | `mvn clean verify`: compile + JUnit tests. Reports Jenkins mein | Pipeline ruk jaati hai |
| 4 | `Docker Build` | `app/Dockerfile` se image; `APP_VERSION=42-a1b2c3d` image mein bake | |
| 5 | `Image Scan (Trivy)` | HIGH/CRITICAL report; **fixable CRITICAL CVE = fail** | Ruk jaati hai, image push nahi hogi |
| 6 | `Push Image` | `docker.io/<you>/order-service:42-a1b2c3d` | |
| 7 | `Deploy: dev` → `promote.sh` | gitops repo clone → `kustomize edit set image` (overlays/dev) → **conftest policy check** on rendered YAML → commit + push | Policy fail = commit hi nahi hoga |
| 8 | Argo CD (dev cluster) | Har ~3 min Git poll karta hai, naya tag dekha, sync | |
| 9 | Argo Rollouts (dev) | **Canary**: 25% pods naye → 2 min → 50% → 2 min → 100%. Background mein **AnalysisRun** har 30s Prometheus se success rate check karta hai | Success < 95% (2 baar) ⇒ **auto abort**, stable version wapas 100% |
| 10 | Kyverno (admission) | Har naya pod policies se check (dev = Audit, sirf report) | staging/prod mein pod reject |
| 11 | `verify-deployment.sh` | `/api/version` == naya tag **aur** `/api/orders` == 200, **10 baar lagataar** | Timeout ⇒ `rollback.sh` = **git revert** ⇒ pipeline FAIL |
| 12 | `Approval: staging` | ⏸ Jenkins mein "Promote" button, sirf `APPROVERS` daba sakte hain. 4 ghante timeout | Abort = yahin ruk jayega |
| 13 | `Deploy: staging` | Step 7–11 staging overlay ke liye (Kyverno **Enforce**) | Same |
| 14 | `Approval: prod` | ⏸ 24 ghante timeout | |
| 15 | `Deploy: prod` | Step 7–11 prod overlay ke liye. Canary dheere: 20% → 5m → 50% → 5m → 80% → 2m → 100% | Same |

**Is flow mein Slack pe kya aata hai** (`slack-webhook` credential ho to):
- ⏳ "`42-a1b2c3d` is healthy in dev and waiting for staging approval" + **Approve/Abort link** (approver ko Jenkins mein dhoondhna nahi padta)
- ⏪ "dev rejected `42-a1b2c3d` - GitOps commit reverted" (rollback hua)
- 🚀 "`42-a1b2c3d` is live in prod" / ❌ build failed / 🚫 aborted
- Aur cluster ke Alertmanager se: `RolloutAborted`, SLO burn alerts, etc. (G6)

**Key idea: "Build once, deploy many."** Image ek hi baar banti hai. Dev, staging, prod teeno mein **exactly wahi image** (same tag) jaati hai. Bas config (replicas, APP_ENV) env ke hisaab se alag hoti hai (kustomize overlays). Isliye jo dev/staging mein test hua, wahi prod mein jaata hai.

### GitOps repo ka structure (Argo CD kya padhta hai)
```
order-platform-gitops/
├── bootstrap/root-<env>.yaml         ← cluster mein sirf YE haath se/Terraform se apply hota hai
├── clusters/<env>/
│   ├── addons.yaml                   ← argo-rollouts, kyverno, prometheus, kyverno-policies (versions pinned)
│   └── apps.yaml                     ← AppProject + order-service Application
├── apps/order-service/
│   ├── base/                         ← Rollout, Service, Analysis, ServiceMonitor, NetworkPolicy, PDB...
│   └── overlays/<env>/               ← image tag (Jenkins badalta hai), replicas, APP_ENV
└── platform/kyverno-policies/
    ├── base/                         ← 5 ClusterPolicies (Audit)
    └── overlays/<env>/               ← dev: Audit, staging/prod: Enforce
```

**App of Apps pattern:** `root` app ek folder (`clusters/dev`) point karta hai jisme aur Applications hain. Ek cheez apply karo, poora cluster khud ban jaata hai. Naya add-on chahiye? `clusters/dev/addons.yaml` mein ek Application add kar, push kar, done.

**Sync waves:** `argocd.argoproj.io/sync-wave` annotation order decide karta hai: AppProject (-5) → add-ons (-3) → policies (-1) → app (1). CRDs pehle aane chahiye (Rollout CRD argo-rollouts se aata hai).

---

## D. Approval gates

| Gate | Kahan | Kaun approve kar sakta hai |
|---|---|---|
| App → staging | `Jenkinsfile` stage `Approval: staging` | `APPROVERS` (default `admin`) |
| App → prod | `Jenkinsfile` stage `Approval: prod` | `APPROVERS` |
| Infra → staging | `Jenkinsfile.infra` (plan artifact padh ke) | `APPROVERS` |
| Infra → prod | `Jenkinsfile.infra` | `APPROVERS` |

Kaise kaam karta hai: `input` step pipeline ko pause karta hai. Jenkins UI (Stage View) mein stage pe hover → **Promote/Abort**. `submitter` se sirf allowed users approve kar sakte hain. Doosre user ko button dikhega par error aayega.

**Approver team setup:** Manage Jenkins → Security → Authorization: **Matrix-based security** (plugin: *Matrix Authorization Strategy*) → users bana (e.g. `release-manager`), aur Jenkinsfile mein `APPROVERS = 'admin,release-manager'`.

> Real world: GitHub branch protection (PR + review required) bhi gate hai. gitops repo mein `main` protect kar aur Jenkins bot ko bypass allow kar. Isse koi haath se prod tag change nahi kar sakta.

---

## E. Policy-as-code (3 layers)

"Defence in depth": ek layer chook jaaye to doosri pakad le.

| Layer | Tool | Kab | Kya check | File |
|---|---|---|---|---|
| 1. Infra (CI) | conftest + Rego | `terraform plan` ke baad, apply se pehle | IMDSv2, encrypted disk, allowed instance types, SG mein 22/6443/etcd/kubelet 0.0.0.0/0 pe nahi, required tags | `policies/terraform/aws.rego` |
| 2. Manifests (CI) | conftest + Rego | Git commit se pehle (`promote.sh`) | Image tag pinned, requests/limits, non-root, readOnlyRootFilesystem, no privilege escalation, no privileged, probes, no LoadBalancer | `policies/kubernetes/workloads.rego` |
| 3. Cluster (runtime) | Kyverno + Pod Security Admission | Pod create hote waqt (admission webhook) | latest tag nahi, resources, allowed registries, non-root, labels; PSA `restricted` | `gitops/platform/kyverno-policies/`, namespace labels |

### Khud try kar (policy fail karwa)

**Terraform policy:** `terraform/modules/k8s-cluster/main.tf` mein master ka `http_tokens = "required"` ko `"optional"` kar → infra pipeline chala → `Plan: dev` stage pe:
```
FAIL - dev.plan.json - main - module.cluster.aws_instance.master: IMDSv2 must be enforced ...
```
(Wapas theek kar dena!)

**Kubernetes policy (CI):** `gitops/apps/order-service/base/rollout.yaml` mein `readOnlyRootFilesystem: true` hata ke gitops repo push kar, phir app pipeline chala. `Deploy: dev` mein conftest fail hoga.

**Kyverno (cluster):**
```bash
# staging/prod (Enforce) cluster pe:
kubectl run test --image=nginx:latest -n order-service
# Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
#   disallow-latest-tag: ... Using the mutable tag 'latest' is not allowed.
# (PSA bhi block karega kyunki nginx root chalta hai)

# dev (Audit) mein block nahi hoga, report mein dikhega:
kubectl get policyreport -n order-service
```

### Dev cluster pe poora policy drill (Batch 11 mein asal mein kiya)

**Pehle concept: admission chain.** `kubectl run` → API server: authentication (kaun?) → authorization/RBAC (permission?) → mutating admission → schema validation → **validating admission** (PSA built-in + Kyverno webhook) → etcd. Validating step mein **koi bhi ek "No"** = pod reject.

| Tool | Kya hai | Kahan laga |
|---|---|---|
| **Pod Security Admission (PSA)** | Kubernetes built-in (1.25+ stable). Levels: privileged / baseline / restricted | `order-service` namespace label `pod-security.kubernetes.io/enforce: restricted` |
| **Kyverno** | Policy engine (validating webhook); Audit = report, Enforce = reject | 5 ClusterPolicies; sirf label `policy.order-platform.io/enforce=true` wale namespaces pe |
| **Argo CD** | selfHeal: cluster ko Git jaisa rakhta hai | kyverno-policies app (`prune` + `selfHeal`) |

```bash
export KUBECONFIG=~/.kube/order-platform-dev

# B1: app compliant hai?  → order-service ke saare reports PASS 7, FAIL 0
kubectl get polr -A

# B2: test namespace: Kyverno label haan, PSA nahi (warna PSA pehle hi rok deta, Audit dikhta nahi)
kubectl create namespace policy-test
kubectl label namespace policy-test policy.order-platform.io/enforce=true

# B3: Kyverno AUDIT test → "pod/bad-nginx created" (block nahi), ~20s baad PASS 1 FAIL 6
kubectl run bad-nginx -n policy-test --image=nginx:latest
kubectl get polr -n policy-test
kubectl get polr -n policy-test -o jsonpath='{range .items[*].results[*]}{.policy}{" -> "}{.result}{": "}{.message}{"\n"}{end}'
kubectl get events -n policy-test --field-selector reason=PolicyViolation   # turant dikhta hai

# B4: PSA test (app namespace) → Forbidden: violates PodSecurity "restricted:latest"
kubectl run bad-nginx -n order-service --image=nginx:latest

# B5a: policy ko haath se Enforce karo → Argo CD selfHeal ~1s mein wapas Audit (bad-2 ban jaata hai)
kubectl patch clusterpolicy disallow-latest-tag --type=merge -p '{"spec":{"validationFailureAction":"Enforce"}}'; sleep 3; kubectl run bad-2 -n policy-test --image=nginx:latest; sleep 20; kubectl get clusterpolicy disallow-latest-tag -o jsonpath='{.spec.validationFailureAction}{"\n"}'
kubectl get events -n argocd --field-selector involvedObject.name=kyverno-policies   # Synced -> OutOfSync -> automated sync -> Synced

# B5b: asli Enforce dekhna: alag policy jo Git mein NAHI hai (Argo CD use nahi chhuta)
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: demo-enforce-latest
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: no-latest
      match:
        any:
          - resources:
              kinds: ["Pod"]
              namespaces: ["policy-test"]
      validate:
        message: "DEMO Enforce: the 'latest' tag is blocked."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
EOF
sleep 5; kubectl run bad-3 -n policy-test --image=nginx:latest
# → admission webhook "validate.kyverno.svc-fail" denied the request ... DEMO Enforce

# Cleanup
kubectl delete clusterpolicy demo-enforce-latest
kubectl delete namespace policy-test
```

**B3 ke 6 FAIL:** `latest` tag · `app.kubernetes.io/name` label nahi (`kubectl run` sirf `run=` lagata hai) · runAsNonRoot · allowPrivilegeEscalation · requests/limits · registry `docker.io/maverick8826` nahi. PASS: tag diya tha.

**Kyun aisa dikha:**
- **Report der se:** Kyverno pehle EphemeralReport banata hai, reports-controller ~10–30s mein PolicyReport mein jodta hai. Events turant aate hain.
- **Har violation 2 baar (events):** admission pe + **background scan** pe (`background: true`). Background scan purane (policy se pehle bane) resources bhi pakadta hai.
- **B4:** dev mein Kyverno Audit hai, phir bhi PSA ne roka = **defense in depth**. PSA sirf pod security dekhta hai; registry/labels/limits jaise org rules Kyverno ke.
- **B5a:** Git = source of truth. Policy kamzor karne ka manual badlav bhi wapas. Policy badalni ho to Git → PR → merge.

| Mode | Pod banega? | Kahan dikhta | Kahan use |
|---|---|---|---|
| Audit | ✅ | PolicyReport, Events, metric → `KyvernoPolicyViolations` | dev |
| Enforce | ❌ | kubectl / Argo CD sync error turant | staging, prod |

Pattern: nayi policy pehle Audit → reports padho → violations theek karo → Enforce.

### Locally policies test karna
```bash
# Terraform
terraform show -json dev.tfplan > plan.json
conftest test plan.json -p policies/terraform

# Kubernetes
kustomize build gitops/apps/order-service/overlays/dev > r.yaml
conftest test r.yaml -p policies/kubernetes
```

---

## F. Automated rollback demo

Do levels pe rollback hota hai:

**Level 1: Argo Rollouts (seconds–minutes, cluster ke andar)**
- Naya version canary pods mein aata hai (25%).
- `AnalysisTemplate success-rate` har 30s Prometheus se poochta hai: non-5xx requests / total requests.
- 2 baar < 95% ⇒ AnalysisRun **Failed** ⇒ Rollout **Aborted** ⇒ canary pods hata diye, purana version 100%.
- `traffic-generator` deployment lagatar requests bhejta hai taaki measure karne ko data ho.

**Level 2: Jenkins + Git (desired state theek karna)**
- Abort ke baad Git mein abhi bhi bad tag likha hai (Argo CD app "Degraded" dikhega).
- `verify-deployment.sh` timeout ⇒ `rollback.sh` ⇒ `git revert <promotion commit>` ⇒ Git = last good version ⇒ Argo CD sync ⇒ sab Healthy.
- Build **FAILED**, staging/prod tak kabhi nahi pahuncha.

### Demo steps
1. Pehle ek normal build successfully dev tak pahuncha (good version chal raha ho).
2. Jenkins → `order-platform-app` → **Build with Parameters** → ✅ `SIMULATE_BAD_RELEASE` → Build. Image mein `FAULT_ERROR_RATE=0.5` bake hota hai (50% `/api/orders` = 500 error).
3. Dekh:
   ```bash
   # Rollouts kubectl plugin (ek baar install):
   curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
   chmod +x kubectl-argo-rollouts-linux-amd64 && sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
   # (Windows: kubectl-argo-rollouts-windows-amd64 download karke PATH mein daal)

   kubectl argo rollouts get rollout order-service -n order-service --watch
   kubectl get analysisrun -n order-service
   ```
   ~2–3 min mein: `Status: ✖ Degraded`, `Message: RolloutAborted: Rollout aborted update to revision N: Metric "success-rate" assessed Failed`.
4. Jenkins log: `FAILED: ... did not become healthy` → `Rolled back dev: reverted <sha>` → build red.
5. gitops repo ki history mein `rollback(dev): revert ...` commit dikhega.

> Manually rollback karna ho (bina Jenkins): `kubectl argo rollouts abort order-service -n order-service`, ya gitops repo mein `git revert` karke push kar. **Hamesha Git se karna best hai**, warna Argo CD selfHeal tera manual change wapas palat dega.

### Asal mein kya hua (Batch 11, build #10 `10-90d02cd`)

**Plugin ke bina dekhna** (Windows Git Bash): `-w` sirf **ek** resource type leta hai (`kubectl get rollout,analysisrun -w` → "you may only specify a single resource type"):
```bash
kubectl get rollout -n order-service -w          # terminal 1
kubectl get analysisrun -n order-service -w      # terminal 2
# ya ek terminal mein (Git Bash mein `watch` nahi hota):
while true; do clear; date; kubectl get rollout,analysisrun -n order-service; sleep 10; done

# Fault sach mein laga? (pehle confirm, phir result pe bharosa)
kubectl exec -n order-service <canary-pod> -- env | grep -E "APP_VERSION|FAULT"   # FAULT_ERROR_RATE=0.5
```

| Time (IST) | Kya hua |
|---|---|
| 18:23 | Build start; CI stages normal |
| ~18:24 | `promote(dev): order-service 10-90d02cd` commit |
| 18:25 | Argo CD ne ~3 min poll ke baad sync kiya → 25% → 1 kharab pod + 2 purane |
| 18:26:50 / 18:27:20 / 18:27:50 | Success rate **0.881 / 0.889 / 0.857** (< 0.95) → "failed (3) > failureLimit (2)" → **RolloutAborted** |
| 18:38 | Slack `ArgoCDAppDegraded` (for 10m) |
| 18:40 | Slack `RolloutAborted` (rule fix ke baad, J table dekho) |
| 18:40 | `verify-deployment.sh` 15min 10s timeout → `rollback.sh` → `rollback(dev): revert ...` → Slack #deployment ⏪ + ❌ |
| 18:42 | Argo CD sync → Synced/Healthy |

- **~88% kyun, 50% kyun nahi:** 3 mein se 1 pod kharab → ~1/3 traffic × 50% errors. Yahi canary ka fayda hai: blast radius chhota.
- **Jenkins 15 min kyun ruka:** Jenkins ke paas cluster access nahi (design). Sirf URL dekhta hai, to abort ka pata timeout se chalta hai. Alternatives: Jenkins mein `kubectl argo rollouts status` (credentials dene padenge) ya Rollouts notifications → webhook.
- ⚠️ **`SIMULATE_BAD_RELEASE` tick zaroor karna.** Default false hai. Build ke neeche "SIMULATED BAD RELEASE" dikhna chahiye, warna normal release banegi aur analysis pass ho jayega.

## F2. Drift + self-healing drill

Do levels: **Kubernetes** controllers etcd ke hisaab se theek karte hain; **Argo CD selfHeal** Git ke hisaab se.

```bash
# C1 (Kubernetes): pod delete → ReplicaSet 1s mein naya pod banata hai
kubectl delete pod -n order-service $(kubectl get pods -n order-service -o name | grep order-service- | head -1 | cut -d/ -f2)

# C2 (Argo CD): replicas haath se → DESIRED 4, 10s baad wapas 2 (Git mein replicas: 2)
kubectl scale rollout order-service -n order-service --replicas=4; kubectl get rollout order-service -n order-service; sleep 10; kubectl get rollout order-service -n order-service

# C3 (Argo CD): managed object delete → PDB wapas (AGE ~10s). Kubernetes khud deleted object nahi banata.
kubectl delete pdb order-service -n order-service; sleep 10; kubectl get pdb -n order-service

# C4: saboot
kubectl get events -n argocd --field-selector involvedObject.name=order-service --sort-by=.lastTimestamp | tail -8
# Synced -> OutOfSync | Initiated automated sync | Partial sync operation ... succeeded | OutOfSync -> Synced
```
- `kubectl scale` etcd hi badal deta hai, to Kubernetes maan leta hai. Sirf Argo CD pakadta hai. Asli autoscaling = HPA + Argo CD `ignoreDifferences` on `/spec/replicas`.
- **Partial sync:** selfHeal sirf OutOfSync resources apply karta hai (~1s), baaki pods ko nahi chhedta.
- `selfHeal: false` → app OutOfSync (peela) dikhega, manual Sync tak. `prune: false` → Git se hati file ka resource orphan.

---

## G. Monitoring + smart alerting

Monitoring 3 layers mein hai. Har layer ek alag sawaal ka jawab deti hai:

```
 ┌────────────── Layer 1: CLUSTER KE ANDAR (har cluster) ───────────────┐
 │ App /actuator/prometheus ─► Prometheus ─► rules (SLO, burn-rate) ─►  │
 │                              │            Alertmanager ─► Slack      │
 │                              └──► Grafana dashboards                 │
 │  "App aur platform theek chal rahe hain? Users ko dikkat hai?"       │
 └──────────────────────────────────────────────────────────────────────┘
 ┌────────────── Layer 2: CLUSTER KE BAHAR (AWS CloudWatch) ────────────┐
 │ EC2 status checks + CloudWatch agent (memory, disk, logs) ─►         │
 │ metric alarms ─► composite alarms ─► SNS ─► Email                    │
 │  "Machines zinda hain? Poora cluster hi gir gaya to?"                │
 └──────────────────────────────────────────────────────────────────────┘
 ┌────────────── Layer 3: PIPELINE (Jenkins) ───────────────────────────┐
 │ Approval chahiye / rollback hua / prod live / build fail ─► Slack    │
 │  "Release mein kya ho raha hai, kisko kya karna hai?"                │
 └──────────────────────────────────────────────────────────────────────┘
```

> **Layer 2 kyun zaruri hai?** Prometheus cluster ke andar chalta hai. Agar master ya saare nodes gir gaye, to Prometheus bhi gir gaya, aur alert bhejne wala koi nahi bacha. Isliye bahar se dekhne wala chahiye ("who watches the watchers"). CloudWatch AWS ka hai, cluster ke saath nahi marta.

### G1. URLs aur login

| UI | URL | Login |
|---|---|---|
| Grafana | `http://<worker-public-ip>:30300` | `admin` / random password (neeche command) |
| Prometheus | `http://<worker-public-ip>:30090` | none (sirf tera IP SG mein allowed) |
| Alertmanager | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093` → `http://localhost:9093` | none |
| Argo CD | `https://<worker-public-ip>:30443` | admin / (A14) |
| CloudWatch dashboard | `terraform output cloudwatch_dashboard` | AWS console |
| App | `http://<worker-public-ip>:30080/api/orders` | none |

**Grafana password:** ye Git mein nahi hai. Cluster bootstrap ke waqt random bana ke secret `grafana-admin` mein rakha jaata hai:
```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```
> 💡 **Screen pe dikhaye bina copy:** `... | base64 -d | clip` (Windows clipboard; Git Bash mein chalta hai). Screenshot mein password leak hone ka chance khatam. "Invalid password" aaye to aksar browser ka purana auto-fill hota hai: box khaali karke paste kar.
>
> **Password leak ho gaya? Rotate:**
> ```bash
> kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin >   --from-literal=admin-password="$(openssl rand -base64 18)" --dry-run=client -o yaml | kubectl apply -f -
> kubectl -n monitoring rollout restart deploy kube-prometheus-stack-grafana
> ```
> Grafana ka DB `emptyDir` mein hai, to restart pe naya DB banta hai aur admin password Secret se dobara padha jaata hai.

**🧠 Kyun (interview ke liye):**
- **Prometheus pull model:** har 15s apps ke `/metrics` se data kheenchta hai. Kahan se, ye **ServiceMonitor** batata hai (app ke saath Git mein).
- **`rate(counter[5m])`:** counter hamesha badhta hai. `rate` = pichhle 5 min ki per-second badhat. Raw counter pe graph/alert nahi banate. Quick check: `sum(rate(orders_placed_total[5m]))` (traffic-generator ~1/s).
- **Grafana sirf dikhata hai.** Data Prometheus ka, dashboards Git mein (`dashboards/*.json`), sidecar apne aap load karta hai.
- **Watchdog** hamesha firing = alerting pipeline zinda hai (dead man's switch).

### G2. Slack setup (Alertmanager + Jenkins)

Alerts Slack pe aayenge. Slack free hai.

**Step 1: Slack mein webhook bana**
1. https://slack.com pe free workspace bana (ya existing use kar).
2. Channels bana: `#alerts-dev`, `#alerts-staging`, `#alerts-prod`, `#deployments`.
3. https://api.slack.com/apps → **Create New App** → From scratch → naam `order-platform-alerts` → workspace select.
4. Left menu **Incoming Webhooks** → On → **Add New Webhook to Workspace** → channel `#alerts-dev` → Allow.
5. URL copy kar: `https://hooks.slack.com/services/T000/B000/XXXX`. Har channel ke liye step 4 repeat kar (ek webhook = ek channel).

> ⚠ Webhook URL = password. Jiske paas URL hai wo tere channel mein message bhej sakta hai. Git mein kabhi commit mat kar.

**Step 2: Cluster ke Alertmanager ko webhook de.** Cluster bootstrap ek **placeholder** secret banata hai. Usko asli URL se replace kar (har env ke cluster pe uska apna channel):
```bash
export KUBECONFIG=~/.kube/order-platform-dev
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/T000/B000/XXXX' \
  --dry-run=client -o yaml | kubectl apply -f -

# Alertmanager pod restart kar taaki naya URL turant use ho
kubectl -n monitoring delete pod -l app.kubernetes.io/name=alertmanager
```
> 💡 **URL screen pe dikhaye bina (behtar tareeka):**
> ```bash
> read -rs SLACK_URL          # paste + Enter; kuch nahi dikhega (-s silent, -r backslash as-is)
> echo "length: ${#SLACK_URL}"
> kubectl -n monitoring create secret generic alertmanager-slack --from-literal=webhook-url="$SLACK_URL" >   --dry-run=client -o yaml | kubectl apply -f -
> unset SLACK_URL
> ```
> `--from-literal='https://...'` seedha likhne se URL terminal aur bash history mein reh jaata hai.
>
> `Warning: ... missing the kubectl.kubernetes.io/last-applied-configuration annotation`: harmless. Secret `kubectl create` se bana tha; apply khud annotation jod deta hai.
>
> **Check delivery:** Prometheus mein `sum(alertmanager_notifications_total{integration="slack"})` badhna chahiye aur `sum(alertmanager_notifications_failed_total{integration="slack"})` = 0. Pehle messages aksar `AlertmanagerFailedToSendAlerts` hote hain (placeholder URL wale time ke); thodi der mein RESOLVED.
>
> Slack ka "app is ready" popup (Slack CLI, `slack login`, `slack create`) **ignore** kar: humein sirf Incoming Webhook chahiye (Go to App Settings → Incoming Webhooks).

> Secret ka naam aur key (`alertmanager-slack` / `webhook-url`) exactly yahi rakhna. Alertmanager config file `/etc/alertmanager/secrets/alertmanager-slack/webhook-url` se URL padhta hai (`gitops/clusters/<env>/addons.yaml` mein `api_url_file`).

**Step 3: Jenkins ko webhook de (pipeline notifications).** Manage Jenkins → Credentials → Add:
- Kind: **Secret text**
- Secret: `#deployments` channel ka webhook URL
- ID: `slack-webhook` (exactly yahi)

> ⚠️ Form ka title **"Add Secret text"** hona chahiye. "Username with password" mein bhara to Jenkins hint deta hai *"did you mean secret text?"*, aur Jenkinsfile ka `string(credentialsId: 'slack-webhook')` use padh nahi payega.
>
> **Kyun:** Secret text Jenkins mein encrypted rehta hai, aur log mein galti se print ho to bhi `****` (masking). `notifySlack()` best-effort hai (`try/catch`), to Slack down ho tab bhi deploy nahi rukta. Alag channel (`#deployment` vs `#alerts-dev`): jaankari vs action. Mix kiya to alert fatigue.

Ye optional hai. Credential nahi hoga to pipeline chalti rahegi, bas log mein "Slack notification skipped" aayega.

### G3. CloudWatch email alerts (SNS)

`terraform apply` (shared stack) ke baad AWS tere `alert_email` pe **"AWS Notification - Subscription Confirmation"** mail bhejta hai. **"Confirm subscription" link pe click kar**, warna ek bhi email nahi aayega. Spam folder bhi check kar.

Check:
```bash
aws sns list-subscriptions --query "Subscriptions[?contains(TopicArn,'order-platform-alerts')].[Endpoint,SubscriptionArn]" --output table
# SubscriptionArn "PendingConfirmation" hai to abhi confirm nahi hua
```

### G4. Alert ka safar: metric se Slack tak

```
1. App har request ka metric expose karta hai  →  http_server_requests_seconds_count{status="500",...}
2. Prometheus har 15s scrape karta hai (ServiceMonitor batata hai kahan se)
3. Recording rules har 30s SLI calculate karte hain  →  slo:sli_error:ratio_rate5m, ..._1h, ..._6h ...
4. Alert rule condition true + "for" time poora  →  alert FIRING
5. Prometheus alert Alertmanager ko bhejta hai (label cluster=dev/staging/prod jud jaata hai)
6. Alertmanager: GROUP (milte-julte alerts ek message mein) → INHIBIT (duplicate/noise dabao)
                 → ROUTE (severity ke hisaab se receiver) → Slack
7. Problem theek hui  →  RESOLVED message (send_resolved: true)
```

### G5. SLO aur burn-rate alerting (ye "smart" part hai)

**Purana tareeka:** "error rate > 5% ho to alert". Isme do problems hain:
- 1 minute ka chhota blip aaya, to raat 3 baje page aa gaya (false alarm).
- 1% errors poore hafte chalte rahe, to kabhi alert nahi aaya, jabki users pareshaan the.

**SRE tareeka:** pehle decide kar ki "kitna kharab chalega", phir alert kar jab wo budget tezi se khatam ho raha ho.

| Term | Matlab | Is project mein |
|---|---|---|
| **SLI** (indicator) | Jo measure karte hain | Non-5xx requests / total requests; requests < 300ms / total |
| **SLO** (objective) | Target | Availability **99.5%**, latency: **99%** requests 300ms se fast. Window: **7 din** |
| **Error budget** | Kitni galti allowed hai | 100% − 99.5% = **0.5%** requests fail ho sakti hain |
| **Burn rate** | Budget kitni tezi se khatam ho raha hai | 1x = theek 7 din mein khatam. 14.4x = 14.4 guna tez |

**Multi-window, multi-burn-rate alerts** (`gitops/apps/order-service/base/prometheusrule.yaml`):

| Burn rate | Long window | Short window | Budget kab tak khatam (7d window) | Severity |
|---|---|---|---|---|
| 14.4x | 1h | 5m | ~12 ghante | 🔴 critical (abhi uth) |
| 6x | 6h | 30m | ~28 ghante | 🔴 critical |
| 3x | 1d | 2h | ~2.3 din | 🟠 warning (aaj dekh lena) |
| 1x | 3d | 6h | 7 din (SLO miss hoga) | 🟠 warning |

- **Long window** pakka karta hai ki problem asli hai, blip nahi.
- **Short window** pakka karta hai ki problem *abhi bhi* chal rahi hai. Fix hone ke baad alert jaldi resolve hota hai, ghanton latka nahi rehta.

**Baaki "smart" alerts:**
- `OrderServiceTrafficDrop`: traffic **kal isi time** se aadha ho gaya (`offset 1d`). Fixed number nahi, pattern se compare karta hai, to raat ko kam traffic pe false alarm nahi deta.
- `OrderServiceMemoryNearLimit`: pod OOM-kill hone **se pehle** warning (90% of limit).
- kube-prometheus-stack ke built-in alerts, jaise `NodeFilesystemSpaceFillingUp`: ye `predict_linear` se *predict* karta hai ki disk kitne ghante mein full hogi, aur pehle bata deta hai.

### G6. Alertmanager ke noise-control features

Config: `gitops/clusters/<env>/addons.yaml` → `alertmanager.config`

| Feature | Kya karta hai | Example |
|---|---|---|
| **Grouping** (`group_by: [alertname, namespace, severity]`) | Milte-julte alerts ek message mein | 3 pods restart hue → 3 nahi, 1 Slack message |
| **group_wait** (30s; critical 10s) | Pehla message bhejne se pehle thoda ruko, taaki saath wale alerts bhi aa jayein | |
| **repeat_interval** | Problem chalti rahi to dobara yaad dilao | warning: 6h. critical: prod 1h, staging 2h, dev 4h |
| **Inhibition** | Bade alert ke chalte chhote alerts chup | (1) critical burn chal raha → usi alert ki warning chup. (2) `OrderServiceDown` → latency/traffic alerts chup (service hi down hai). (3) `KubeNodeNotReady` → us node ke pod/target alerts chup |
| **Routing by severity** | critical → `slack-critical`, warning → `slack-warning`, info/Watchdog → `null` (drop) | |
| **Env-aware** | Har alert pe `cluster=dev/staging/prod`, aur title mein env ka naam | Prod critical pe `@channel` mention; dev pe nahi |
| **Runbook link** | Har alert mein `📖 Runbook` link → `docs/RUNBOOKS.md` | Raat 3 baje sochna nahi padta ki kya karna hai |

> **Watchdog** alert hamesha FIRING rehta hai, deliberately. Ye proof hai ki pura alerting pipeline zinda hai. Hum isko `null` pe bhejte hain. Pro setup mein isko healthchecks.io / PagerDuty "dead man's switch" pe bhejte hain. Agar Watchdog aana *band* ho jaye, matlab Prometheus ya Alertmanager mar gaya, aur wo service tujhe alert karti hai.

### G7. Saare alerts ki list

| Alert | Severity | Kahan defined |
|---|---|---|
| `OrderServiceErrorBudgetBurn` | critical / warning | app `prometheusrule.yaml` |
| `OrderServiceLatencyBudgetBurn` | warning | app |
| `OrderServiceDown` | critical | app |
| `OrderServiceTrafficDrop` | warning | app |
| `OrderServiceMemoryNearLimit` | warning | app |
| `OrderServicePodRestarting` | warning | app |
| `ArgoCDAppDegraded`, `ArgoCDAppOutOfSync`, `ArgoCDSyncFailing` | warning | `gitops/platform/monitoring/platform-alerts.yaml` |
| `RolloutAborted`, `RolloutStuck` | warning | platform |
| `KyvernoPolicyViolations` | warning | platform |
| ~100 built-in (`KubeNodeNotReady`, `KubePodCrashLooping`, `NodeFilesystemSpaceFillingUp`, `TargetDown` ...) | mixed | kube-prometheus-stack chart |
| CloudWatch `node-health`, `node-pressure` | email | Terraform `modules/cloudwatch-alarms` |

Har alert ka "kya karna hai" → [docs/RUNBOOKS.md](docs/RUNBOOKS.md).

### G8. Grafana dashboards

Dashboards **code mein** hain (JSON files), haath se banane ki zarurat nahi. Grafana ka "sidecar" har namespace mein `grafana_dashboard: "1"` label wale ConfigMaps dhoondhta hai aur load kar deta hai. Grafana → Dashboards → folder **Order Platform**:

**1. Order Service - SLO & RED** (`gitops/apps/order-service/base/dashboards/order-service.json`)
- Top row: Availability (1h), **Error budget left (7d)**, Requests/s, p95 latency, Ready pods, Canary phase
- RED: requests by status, 5xx ratio vs SLO line, latency p50/p95/p99 vs 300ms line
- **Burn rate graph** with 6x / 14.4x lines (alert kyun aaya, ye dikhta hai)
- Business: orders/min. JVM heap, CPU, memory vs limit, restarts. Firing alerts table.
- 🟠 **Deployment markers**: har naye ReplicaSet (= naya release) pe graph pe orange line. Error spike release ke turant baad aaya? Ek nazar mein pata chal jaata hai.
- 🔴 **Alert markers**: alert kab fire hua, wo bhi graph pe

**2. Platform Overview** (`gitops/platform/monitoring/dashboards/platform-overview.json`)
- Firing critical/warning count, nodes ready, Kyverno violations (24h)
- Argo CD apps table (health + sync, colored), rollout phase timeline (canary kab abort hua)
- Argo CD syncs, Kyverno failures per policy, node CPU/memory/disk

**3. Built-in (chart ke saath):** "Kubernetes / Compute Resources / Namespace (Pods)", "Node Exporter / Nodes", etc.

> Dashboard change karna hai? Grafana UI mein edit kar → Share → Export → **Save to file** → JSON ko repo ki file mein paste kar → commit. UI mein kiya change pod restart pe chala jaata hai, Git wala hamesha rehta hai (dashboards-as-code).

**Kuch PromQL khud try kar** (Prometheus UI → Graph):
```promql
sum by (status) (rate(http_server_requests_seconds_count{namespace="order-service"}[1m]))
slo:sli_error:ratio_rate1h                          # SLI recording rules
slo:error_budget_remaining:ratio7d                  # kitna budget bacha
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="order-service"}[5m])))
orders_placed_total
ALERTS{alertstate="firing"}
```

### G9. CloudWatch layer (Terraform kya banata hai)

**CloudWatch agent** (har EC2 pe user-data install karta hai: Jenkins + saare nodes):
- EC2 khud sirf CPU, network aur status check deta hai. **Memory aur disk usage AWS ko andar se dikhta hi nahi**, isliye agent chahiye.
- Agent `CWAgent` namespace mein `mem_used_percent` aur `disk_used_percent` bhejta hai.
- Logs bhi bhejta hai:

| Log group | Kya hai | Retention |
|---|---|---|
| `/order-platform-<env>/nodes` | bootstrap log + syslog (kubelet, containerd) | 14 din |
| `/order-platform-<env>/k8s-audit` | Kubernetes API audit log (kisne kya kiya) | 14 din |
| `/order-platform-shared/jenkins` | Jenkins user-data + syslog (Jenkins logs) | 14 din |

> Audit log off-host kyun? Agar koi master pe root ban gaya, to wo local audit file delete kar sakta hai. CloudWatch mein gaya hua log wo nahi mita sakta. Ye security best practice hai.

- Agent ko nodes ka IAM role (`CloudWatchAgentServerPolicy`) permission deta hai. IMDS hop limit 1 hai, isliye sirf host pe chalne wala agent role use kar sakta hai, pods nahi.

**Alarms** (`terraform/modules/cloudwatch-alarms`), har instance pe 4:

| Alarm | Condition |
|---|---|
| `<env>-<node>-status-check` | EC2 status check fail (3 mein se 2 minute) |
| `<env>-<node>-cpu-high` | CPU > 85% for 15 min |
| `<env>-<node>-memory-high` | Memory > 90% for 10 min |
| `<env>-<node>-disk-high` | Root disk > 85% |

**Smart part: composite alarms.** Upar wale individual alarms **koi email nahi bhejte**. Sirf 2 composite alarms bhejte hain:
- `order-platform-<env>-node-health` = koi bhi status-check alarm → **critical email**
- `order-platform-<env>-node-pressure` = koi bhi CPU/memory/disk alarm → **warning email**
- **Actions suppressor:** jab `node-health` fire ho raha ho (node hi mar gaya), tab `node-pressure` chup rehta hai. Ek dead node = 1 email, 5 nahi.

**CloudWatch dashboard** `order-platform-<env>-nodes`: alarm status, CPU %, memory %, disk %, status checks, sab nodes ek jagah. Link: `terraform output cloudwatch_dashboard`.

**Logs Insights** (CloudWatch → Logs Insights → log group `/order-platform-dev/k8s-audit`):
```
fields @timestamp, user.username, verb, objectRef.resource, objectRef.namespace, objectRef.name
| filter verb in ["delete", "create", "patch"] and objectRef.namespace = "order-service"
| sort @timestamp desc
| limit 50
```

### G10. Manual tareeka (seekhne ke liye, bina Terraform/Argo CD)

**(a) Prometheus + Grafana + Alertmanager, Helm se (Part A wale cluster pe):**
```bash
# Helm install (master pe ya laptop pe)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring
# Secrets pehle (Grafana password + Slack webhook)
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 18)"
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/T000/B000/XXXX'

# Values: gitops/clusters/dev/addons.yaml ke kube-prometheus-stack wale "valuesObject" ka
# content ek file mein copy kar (yq se nikal sakta hai):
yq 'select(.metadata.name=="kube-prometheus-stack") | .spec.source.helm.valuesObject' \
   gitops/clusters/dev/addons.yaml > kps-values.yaml

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 92.11.0 -n monitoring -f kps-values.yaml
kubectl get pods -n monitoring -w
```
Phir app ke rules/dashboard: `kubectl apply -k gitops/apps/order-service/overlays/dev` (ye pura app deploy karta hai, ServiceMonitor + PrometheusRule + dashboard ke saath).

> Argo CD wale setup mein ye sab `clusters/<env>/addons.yaml` ki Application khud karti hai. Sirf secrets pehle banane hote hain, jo Terraform bootstrap kar deta hai (ya A14 mein haath se).

**(b) CloudWatch agent ek EC2 pe haath se (e.g. Jenkins):**
1. **IAM:** IAM → Roles → (Jenkins ka role, ya naya EC2 role) → Add permissions → `CloudWatchAgentServerPolicy`. EC2 → instance → Actions → Security → Modify IAM role.
2. **Install** (SSH karke):
   ```bash
   curl -fsSL -o /tmp/cwagent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
   sudo dpkg -i -E /tmp/cwagent.deb
   ```
3. **Config:** wizard chala (`sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard`), ya `terraform/modules/jenkins/user_data.sh` wala JSON `/opt/aws/amazon-cloudwatch-agent/etc/config.json` mein daal.
4. **Start:**
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
     -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status   # "running"
   ```
5. 2–3 min baad: CloudWatch → Metrics → All metrics → **CWAgent** → InstanceId → `mem_used_percent` dikhna chahiye.

**(c) SNS topic + alarm, console se:**
1. **SNS** → Topics → Create topic → Standard → naam `order-platform-alerts` → Create.
2. Topic → **Create subscription** → Protocol: Email → apna email → Create → mail mein **Confirm** click.
3. **CloudWatch** → Alarms → **Create alarm** → Select metric → EC2 → Per-Instance → apna instance → `CPUUtilization` → Statistic Average, Period 5 min → Threshold: Greater than **85** → Datapoints **3 out of 3** → Next.
4. Notification: In alarm → SNS topic `order-platform-alerts` → Next → naam `jenkins-cpu-high` → Create.
5. **Composite alarm:** Alarms → select 2+ alarms (checkbox) → **Create composite alarm** → rule `ALARM("jenkins-cpu-high") OR ALARM("jenkins-status-check")` → SNS action. Individual alarms se actions hata de, taaki ek hi email aaye.

### G11. Alerts test karna (zaruri! jo test nahi hua wo kaam nahi karta)

**1. Slack pipeline test (fake alert direct Alertmanager ko):**
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093 &
curl -XPOST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname":"TestAlert","severity":"critical","namespace":"order-service"},
  "annotations": {"summary":"Test alert - ignore","runbook_url":"https://example.com"}
}]'
```
~10 sec mein Slack pe 🚨 message. ~5 min baad (alert dobara nahi bheja to) RESOLVED aayega.

**2. Real SLO alert:** Jenkins → `SIMULATE_BAD_RELEASE` ✅ (section F). Canary abort hoga aur `RolloutAborted` warning aayega. Agar bad version pe zyada der traffic chala, to `OrderServiceErrorBudgetBurn` bhi aa sakta hai.

**3. Service down:**
```bash
kubectl argo rollouts abort order-service -n order-service   # ya
kubectl -n order-service scale rollout order-service --replicas=0   # Argo CD selfHeal ise 1-3 min mein wapas kar dega
```
2 min baad `OrderServiceDown` critical aata hai. Notice kar: latency/traffic alerts **nahi** aaye (inhibition kaam kar raha hai).

**4. CloudWatch email test (bina kuch tode):**
```bash
aws cloudwatch set-alarm-state --alarm-name order-platform-dev-worker-0-cpu-high \
  --state-value ALARM --state-reason "manual test"
```
→ `order-platform-dev-node-pressure` composite fire → email aayega. Agle evaluation (5 min) pe khud OK ho jayega.

**5. Asli CPU load (optional):**
```bash
ssh ubuntu@<worker-ip> 'sudo apt-get install -y stress-ng && stress-ng --cpu 2 --timeout 20m'
```
15 min baad CPU alarm aayega. Grafana "Node CPU" graph mein bhi dikhega.

### G12. Monitoring ka kharcha (approx per env/month)
| Cheez | ~ Cost |
|---|---|
| Prometheus/Grafana/Alertmanager | Free (cluster ke andar, bas node RAM) |
| CloudWatch alarms (4 × nodes + 2 composite) | ~$1.5–2 (pehle 10 standard alarms free) |
| Agent custom metrics (2 × nodes) | ~$2 |
| Logs (syslog + audit) | ~$1–5, traffic pe depend (₹/GB ingestion) |
| CloudWatch dashboard | pehle 3 free, phir $3 each |
| SNS email | Free tier mein |

> **Note:** Prometheus data `emptyDir` mein hai (kubeadm cluster pe EBS storage class nahi hai). Prometheus pod restart = purana metrics data gaya, aur 7 din ka error budget dobara shuru. Production mein EBS CSI driver + PersistentVolume, ya Amazon Managed Prometheus / Thanos use karte hain.

---

## H. Hardening checklist

✅ = is project mein done, ⬜ = real production ke liye next steps

**AWS / EC2**
- ✅ IMDSv2 required, hop limit 1 (pods instance credentials nahi chura sakte)
- ✅ EBS root volumes encrypted
- ✅ SSH / 6443 / NodePorts sirf admin IP se, Jenkins se sirf NodePorts
- ✅ Default SG locked (koi rule nahi)
- ✅ Jenkins ke paas IAM role (static keys nahi)
- ✅ Terraform state: S3 private, encrypted, versioned, locked
- ✅ Out-of-band monitoring: CloudWatch alarms + SNS (cluster gir jaye tab bhi alert)
- ✅ Kubernetes audit log + syslog CloudWatch Logs mein (off-host, tamper-resistant), 14 din retention
- ✅ Jenkins ke IAM permissions `order-platform-*` naam wale IAM roles/profiles tak limited
- ⬜ Nodes private subnets mein + NAT gateway + bastion / SSM Session Manager (SSH band)
- ⬜ VPC Flow Logs, CloudTrail, GuardDuty (GuardDuty findings → same SNS topic)
- ⬜ Jenkins ke IAM role ko aur least-privilege (abhi `AmazonEC2FullAccess` hai)
- ⬜ CloudWatch log groups KMS key se encrypt

**Kubernetes**
- ✅ kubeadm CA pre-generated, workers CA hash pin karte hain (no `--discovery-token-unsafe-skip-ca-verification`)
- ✅ API server audit logging, profiling disabled, kubelet read-only port 0
- ✅ Pod Security Admission `restricted` on app namespace
- ✅ Kyverno policies (Enforce in staging/prod)
- ✅ Default-deny NetworkPolicies (Calico)
- ✅ Containers: non-root UID 10001, read-only root FS, drop ALL caps, seccomp RuntimeDefault, no SA token
- ✅ Argo CD AppProject: order-service sirf apne namespace mein deploy ho sakta hai
- ✅ Grafana admin password random, secret mein (default `prom-operator` nahi); Slack webhook bhi secret mein, Git mein nahi
- ⬜ Grafana/Prometheus/Alertmanager ke aage auth + TLS (abhi sirf SG se protected), Grafana SSO
- ⬜ Prometheus ke liye persistent storage (abhi `emptyDir`, restart pe data jaata hai)
- ⬜ etcd encryption at rest for Secrets (`EncryptionConfiguration`)
- ⬜ kube-bench (CIS benchmark) run: `kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml`
- ⬜ Ingress + TLS (cert-manager) instead of NodePorts
- ⬜ Image signing (cosign) + Kyverno `verifyImages`
- ⬜ Argo CD SSO + RBAC, admin user disable

**CI/CD**
- ✅ Immutable image tags, build once promote many
- ✅ Trivy gate, conftest gates, approval gates
- ✅ Secrets Jenkins credentials store mein, logs mein masked
- ⬜ Jenkins agents (controller pe builds nahi), HTTPS for Jenkins (Nginx + Let's Encrypt)
- ⬜ SBOM (`trivy image --format cyclonedx`), SonarQube

---

## I. Infra changes promote karna

Do tarah ka "infra" hai, aur dono dev → staging → prod jaate hain:

**1. AWS infra (Terraform):** e.g. prod workers 3 se 4 karne hain:
- `terraform/stacks/cluster/envs/prod.tfvars` mein `worker_count = 4` → commit → `order-platform-infra` job chala.
- Module code change (sab envs ko affect karta hai)? Pipeline pehle dev apply karegi, phir staging plan + approval, phir prod plan + approval.

**2. Cluster add-ons (Argo CD):** e.g. Kyverno chart upgrade:
- `gitops/clusters/dev/addons.yaml` mein `targetRevision` bump → push → Argo CD dev mein upgrade.
- 1–2 din dev mein chala, sab theek → same change `clusters/staging/addons.yaml` → phir `clusters/prod/addons.yaml`.
- Isliye versions har env mein **alag pinned** hain (copy-paste jaisa lagta hai, par yahi promotion ka control hai).

**Policies bhi aise hi:** nayi Kyverno policy pehle `base/` mein Audit mode mein → dev mein PolicyReports dekh (`kubectl get polr -A`), koi violation nahi → staging/prod overlays Enforce kar dete hain.

---

## J. Troubleshooting

| Problem | Wajah | Fix |
|---|---|---|
| SSH: `Permission denied (publickey)` | Galat user/key | User `ubuntu`, sahi `.pem`, `-i` path check |
| SSH: `UNPROTECTED PRIVATE KEY FILE` | .pem permissions open | A1 ke icacls / `chmod 400` |
| SSH/Jenkins UI timeout | Tera IP badal gaya | `curl checkip.amazonaws.com` → SG / tfvars `admin_cidr` update → `terraform apply` |
| Jenkins: `permission denied ... docker.sock` | jenkins docker group mein nahi / restart nahi kiya | A7: `usermod -aG docker jenkins` + `systemctl restart jenkins` |
| Jenkins apt: `NO_PUBKEY` / `Unable to locate package jenkins` | Jenkins ne signing key rotate ki (2023 → **2026**), ya outbound rule missing (neeche) | A6 wali `jenkins.io-2026.key`; https://pkg.jenkins.io/debian-stable/ pe latest dekh |
| Launch wizard mein **t3.medium select hi nahi hota** | Account **Free plan** pe hai, sirf free-tier-eligible types | Section 1.7: **c7i-flex.large** / m7i-flex.large |
| `apt-get update`: `connection timed out` / `Network is unreachable` har mirror pe, **par SSH chal raha hai** | SG mein **outbound rule nahi** (stateful SG: SSH ka reply jaata hai, naya bahar connection nahi) | SG → Outbound rules → All traffic → 0.0.0.0/0 (A2). Pehle route table (0.0.0.0/0 → igw) aur NACL check karke rule out kar |
| `jenkins.service` failed, `Start request repeated too quickly` | Java install nahi (Jenkins Java pe chalta hai), ya port 8080 busy | `java -version`; `sudo journalctl -u jenkins -n 30`; Java 25 install → `sudo systemctl reset-failed jenkins && sudo systemctl restart jenkins` |
| Jenkins login: `Invalid username or password` | Username galat (case-sensitive) / password bhool gaye | `sudo ls /var/lib/jenkins/users/` (folder ka pehla hissa = username). Reset: `/var/lib/jenkins/init.groovy.d/` mein reset script → restart → **script delete** |
| `Sudo is disabled on this machine` | EC2 wali command **laptop (Git Bash)** pe chala di | Prompt dekh: `syala@...MINGW64` = laptop, `ubuntu@ip-...` = EC2. Pehle SSH kar |
| Token/password screenshot ya chat mein share ho gaya | — | Leaked maan: turant revoke/delete, naya **least-privilege** token bana, sirf Jenkins credentials mein rakh |
| `mvn` build killed / exit 137 | RAM khatam | Swap (A4), ya m7i-flex.large (8 GB) |
| Trivy stage fail | Fixable CRITICAL CVE: base image (OS) mein ya `app.jar` ki Java libraries mein | Report mein **Target** dekh: `ubuntu` row = base image update; `app.jar` row = **Library / Installed / Fixed Version** padh ke `app/pom.xml` mein Spring Boot upgrade ya `<tomcat.version>` jaisi property se pin. Patch se fix na ho (Fixed Version sirf naye major mein) to major upgrade |
| Push Image ke baad agla build **Docker Build** pe `401 Unauthorized: incorrect username or password` (public base image pull pe!) | Purane build ka `docker login` jenkins user ke `~/.docker/config.json` mein pada reh gaya, aur wo token revoke ho chuka hai | EC2 pe `sudo -u jenkins docker logout`. Jenkinsfile ka Push stage ab temporary `DOCKER_CONFIG` + `trap` use karta hai, isliye dobara nahi hoga |
| Jenkins checkout: `couldn't find any revision to build` | Job mein branch `*/master` reh gaya | Job → Configure → Branch Specifier `*/main` |
| Grafana "Orders/min" panel khaali, `orders_created_total` nahi milta | Prometheus `_created` suffix reserve rakhta hai, counter `orders_total` ban jaata tha | Counter ab `orders.placed` → `orders_placed_total`. Metric naam hamesha `/actuator/prometheus` se verify kar |
| `promote.sh`: `kustomize: command not found` | Tool missing | A8 |
| `promote.sh`: git push 403 | PAT ki permission kam / expire | PAT: Contents Read & Write on gitops repo |
| Verify stage: `xxx_APP_URL is not set` | A11 nahi kiya | Global env vars add kar |
| Verify: `version=unreachable` hamesha | Jenkins → NodePort blocked / galat IP | Cluster SG mein jenkins-sg allowed? Worker **private** IP use kar. Jenkins se `curl http://<ip>:30080/api/version` |
| Webhook red ❌ | 8080 GitHub ke liye band / URL ka last `/` missing | A2 SG, `.../github-webhook/` |
| `kubeadm init` preflight: `NumCPU` | micro/small instance | c7i-flex.large (ya t3.medium) |
| Node `NotReady` | CNI (Calico) nahi laga / pods crash | `kubectl get pods -n kube-system`; Calico apply |
| Worker join nahi ho raha | Token expire / SG self rule missing | `kubeadm token create --print-join-command`; SG self-rule; log: `/var/log/k8s-bootstrap.log` |
| Pods random restart, `CrashLoopBackOff` in kube-system | containerd `SystemdCgroup` false | A13.3 step 4 |
| laptop kubectl: `x509: certificate is valid for 10.x, not 13.x` | Public IP SAN mein nahi | `kubeadm init` mein `--apiserver-cert-extra-sans` (Terraform mein already hai) |
| Argo app `Unknown`/`ComparisonError: repository not found` | gitops repo private / galat URL | Repo public kar ya Argo CD mein repo creds; URL check |
| Argo app `OutOfSync` with "CRD not found" | Add-on (CRDs) abhi install ho raha | Wait. Retry policy khud try karegi. Nahi to UI → Sync |
| order-service `ImagePullBackOff` | Tag `0.0.0` (abhi tak koi build nahi) / Docker Hub repo private | Pehla Jenkins build chala; Docker Hub repo public rakh |
| Pods create hi nahi ho rahe (staging/prod) | Kyverno/PSA ne reject kiya | `kubectl get events -n order-service`, `kubectl describe rs -n order-service` |
| Rollout `Paused` / analysis `Inconclusive` | Prometheus mein data nahi | traffic-generator chal raha? `kubectl get pods -n order-service`; Prometheus Targets mein order-service UP? |
| Grafana/Prometheus pods `Pending` | Node pe memory kam | `kubectl describe pod` → Insufficient memory → worker_count badha ya m7i-flex.large |
| `terraform init`: backend config changed | Env switch kiya bina `-reconfigure` | `-reconfigure` laga |
| `Error acquiring the state lock` | Doosra apply chal raha / crash hua | Wait; pakka koi nahi chala raha to `terraform force-unlock <ID>` |
| Jenkins `terraform init`: `doesn't match any of the checksums previously recorded in the dependency lock file` | `.terraform.lock.hcl` laptop (Windows) pe bana, usme Linux hashes nahi | Commit se pehle: `terraform providers lock -platform=linux_amd64 -platform=windows_amd64` (har stack folder mein) |
| `$'\r': command not found` on EC2 | Windows CRLF | `.gitattributes` (already hai); `git add --renormalize .` |
| `configure.sh` sirf usage print karke ruk jaata hai | Koi flag missing (`--alert-email` bhi zaruri hai) | B1 wali poori command |
| Alertmanager / Grafana pod `ContainerCreating` hi rehta hai | Secret `alertmanager-slack` / `grafana-admin` nahi hai | `kubectl describe pod -n monitoring <pod>` → "secret not found" → A14 / G2 ke commands se secret bana |
| Slack pe koi alert nahi aata | Placeholder webhook abhi bhi laga hai / galat URL | G2 step 2; Alertmanager logs: `kubectl -n monitoring logs -l app.kubernetes.io/name=alertmanager \| grep -i slack`; G11 test alert |
| Slack pe pipeline messages nahi aate | Jenkins credential `slack-webhook` nahi / galat type | Kind **Secret text**, ID exactly `slack-webhook`; build log mein "Slack notification skipped: ..." reason dikhta hai |
| Grafana login fail | Default password try kar raha hai | G1 command se secret wala password |
| Grafana mein "Order Platform" dashboards nahi dikhe | ConfigMap nahi bana / label missing | `kubectl get cm -A -l grafana_dashboard=1`; Argo CD mein `monitoring-config` aur `order-service` Synced? |
| Dashboard panels "No data" | Metrics abhi aaye nahi / app deploy nahi hua | Prometheus → Status → Targets mein `order-service` UP? SLO/burn panels ko kuch minute ka data chahiye; 7d budget panel ko 7 din |
| `RolloutAborted`/Argo/Kyverno alerts kabhi nahi aate | Unke metrics scrape nahi ho rahe | Prometheus Targets mein `argo-rollouts`, `kyverno`, `argocd-*` dekh; ServiceMonitor CRD baad mein aaya ho to app ko Argo CD se Sync kar |
| CloudWatch email nahi aata | SNS subscription confirm nahi kiya | G3; spam folder; `aws sns list-subscriptions` |
| CloudWatch memory/disk alarm "Insufficient data" | CloudWatch agent nahi chal raha / IAM role nahi | Node pe `sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status`; log: `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log`; instance pe IAM role attached? |
| Prometheus restart ke baad error budget "reset" | Data `emptyDir` mein tha | Expected (G12 note); production mein persistent volume |
| Argo CD mein `kyverno` hamesha **OutOfSync**, "Last Sync" har kuch second | Kyverno 3.9.x ke `policies.kyverno.io` CRDs mein khaali `labels: {}` / `annotations: {}`; API server empty map save nahi karta → permanent diff → auto-sync loop | Pehle dekh kaun se resources: `kubectl -n argocd get app kyverno -o jsonpath='{range .status.resources[?(@.status=="OutOfSync")]}{.kind} {.name}{"
"}{end}'`. Fix: kyverno Application mein `ignoreDifferences` (CRD, jsonPointers `/metadata/labels`, `/metadata/annotations`) Git se push |
| Jenkins `ERR_CONNECTION_REFUSED`, SSH chal raha | `jenkins.service` **start-limit-hit**: boot ke ~20 min baad unattended-upgrades + needrestart ne Jenkins 5+ baar restart kiya | Refused = service down (timeout = SG). `journalctl -u jenkins`, `/var/log/unattended-upgrades/unattended-upgrades.log`. `sudo systemctl reset-failed jenkins && sudo systemctl start jenkins`; permanent: `echo '$nrconf{override_rc}{qr(^jenkins)} = 0;' \| sudo tee /etc/needrestart/conf.d/50-jenkins.conf` |
| `order-service` **Degraded**, pods `ImagePullBackOff` (`...:0.0.0: not found`) | GitOps mein placeholder tag `0.0.0`; Jenkins ne abhi promote nahi kiya | Expected. `DEV_APP_URL` set karke Jenkins build → `promote.sh` asli tag commit karega |
| Jenkins admin password bhool gaye | - | `/var/lib/jenkins/init.groovy.d/reset-admin.groovy` (HudsonPrivateSecurityRealm.Details.fromPlainPassword) → restart → login → **folder turant delete** |
| Grafana Availability / Error budget **"No data"**, baaki panels theek | 5xx series exist hi nahi (koi error nahi aaya); PromQL mein `sum(khaali)` = khaali, 0 nahi | Prometheus API pe rule query: `slo:sli_error:ratio_rate1h` → `[]`. Fix: SLI rules mein `(sum(rate(...5xx...)) or vector(0)) / sum(rate(...))` |
| Abort dabaya, phir Slack: "failed post-deploy verification" + GitOps revert | Jenkinsfile `catch (err)` ne abort (`FlowInterruptedException`) bhi pakad liya | Console: `Sending interrupt signal to process` = abort. Fix: `catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) { throw e }` generic catch se pehle. Canary (~8–9 min) ke beech abort mat daba |
| Gitops `git push` → `rejected (non-fast-forward)` | Jenkins ne beech mein `promote(dev)` commit kiya | `git pull --rebase && git push` (gitops repo mein do likhne wale: tu + Jenkins) |
| `git pull --rebase` → "cannot pull with rebase: You have unstaged changes" | Badli file abhi commit nahi hui | Order: **commit → `git pull --rebase` → push** (ya `git pull --rebase --autostash`) |
| `git pull --rebase` → "Cannot rebase onto multiple branches" | Koi doosra process (script/IDE auto-fetch) usi waqt `git fetch` kar raha tha → `.git/FETCH_HEAD` race | `git fetch origin && git rebase origin/main && git push` |
| Canary abort hua, Slack mein `ArgoCDAppDegraded` aaya par **`RolloutAborted` kabhi nahi** | Rule `rollout_info{phase="Degraded"}` dhoondhta tha; metric aborted canary ko **`phase="Abort"`** deti hai, aur `namespace` label controller (`argo-rollouts`) ka hota hai, app ka `exported_namespace` mein | Raw metric dekh: `kubectl get --raw "/api/v1/namespaces/monitoring/services/prometheus-operated:9090/proxy/api/v1/query?query=rollout_info"`. Fix (`platform/monitoring/platform-alerts.yaml`): `max by (name, namespace) (label_replace(rollout_info{phase="Abort"}, "namespace", "$1", "exported_namespace", "(.+)")) == 1` |
| `SIMULATE_BAD_RELEASE` build ka canary **pass** ho gaya (analysis 1.0) | Checkbox tick nahi hua → image mein `FAULT_ERROR_RATE=0.0` | `kubectl exec <pod> -- env \| grep FAULT`; Build with Parameters → tick → naam ke neeche "SIMULATED BAD RELEASE" check |
| `kubectl get a,b -w` → "you may only specify a single resource type" | Watch ek hi type leta hai | Do terminals, ya `while true; do clear; kubectl get a,b; sleep 10; done` |
| `kubectl` → `localhost:8080 ... actively refused` | Is terminal mein `KUBECONFIG` set nahi (kubeconfig nahi mila → purana default localhost:8080). Cluster down **nahi** | `export KUBECONFIG=~/.kube/order-platform-dev`; permanent: `~/.bashrc` mein daal |
| `kubectl get polr -n <ns>` → "No resources found" (pod abhi bana) | PolicyReport ~10–30s baad banta hai (EphemeralReport → reports-controller) | Thoda ruk; turant ke liye `kubectl get events -n <ns> --field-selector reason=PolicyViolation` |
| Cluster mein `kubectl patch/scale/delete` kiya, kuch second mein wapas purana | Argo CD **selfHeal** (expected) | Badlav Git mein karo. Events: `kubectl get events -n argocd --field-selector involvedObject.name=<app>` |
| `root` app hamesha **OutOfSync** (har ~30s Synced ↔ OutOfSync), sirf `Application kyverno` diff | Kyverno chart ke PreDelete hooks → Argo CD khud `pre-delete-finalizer.argocd.argoproj.io` (+`/cleanup`) lagata hai; Git mein nahi → selfHeal hatata, controller lagata | `clusters/<env>/addons.yaml` mein kyverno Application ke `finalizers:` mein teeno likho. Check: `kubectl -n argocd get app -o custom-columns=N:.metadata.name,GEN:.metadata.generation,F:.metadata.finalizers` |
| Pipeline "live in prod" bola, par `kubectl get rollout` → `Paused step=1` | Pehla deploy: purane (`0.0.0`) pods kabhi Ready nahi → saara traffic canary pod pe → verify ke 10 checks jaldi pass | Canary khud poora hoga (analysis chal raha hai). Fix: Jenkins Argo CD API (read-only token) se `health == Healthy` + synced revision check kare |
| Naye cluster mein root app: `project default which does not exist` | Root app Argo CD ke `default` AppProject banne se pehle apply hui (startup race) | ~1 min ruko, Argo CD retry khud theek karta hai |
| Cluster stack plan/init: shared state / bucket nahi mila | Shared stack kabhi apply nahi hua (VPC/Jenkins manual); state bucket nahi | B6 Option 3: bootstrap + override variables |
| `aws logs ... --log-group-name /...` → "failed to satisfy constraint" (Git Bash) | MSYS `/...` ko Windows path bana deta hai | `export MSYS_NO_PATHCONV=1` |
| `read -rs https://...` → "not a valid identifier" | `read -rs VAR` mein VAR **naam** hai | `read -rs SLACK_URL` → Enter → **phir** paste → Enter |

**Debug commands jo hamesha kaam aate hain:**
```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -20
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
journalctl -u kubelet -f            # node pe
sudo crictl ps -a                   # node pe containers (docker ps jaisa)
kubectl -n argocd get applications
```

---

## K. Cleanup + cost

**Ulti order mein destroy kar** (clusters shared VPC use karte hain):
```bash
cd terraform/stacks/cluster
for env in prod staging dev; do
  terraform init -reconfigure -backend-config=../../backend.hcl -backend-config=key=cluster/$env/terraform.tfstate
  terraform destroy -var-file=envs/$env.tfvars -auto-approve
done

cd ../shared
terraform destroy

# State bucket (optional, tabhi jab sab khatam): prevent_destroy hata ke, bucket empty karke destroy
```
Cluster stacks destroy karne se unke CloudWatch alarms, dashboards, log groups (logs ke saath) aur node IAM roles bhi hat jaate hain. SNS topic shared stack ke saath jaata hai.

> Shared stack **cluster stacks se pehle** destroy mat kar. Cluster stack SNS topic ARN aur VPC shared state se padhta hai; shared pehle gaya to cluster destroy atak jayega.
**Paisa bachane ke tips:**
- Kaam nahi kar raha? EC2 **Stop** kar de (EBS ka thoda charge lagta hai, compute free). Jenkins ka Elastic IP same rahega. Cluster nodes ke public IP badal jaate hain, isliye kubeconfig dobara lena (`get-kubeconfig.sh`).
- Seekhte waqt sirf **dev** cluster bana.
- Billing → Cost Explorer hafte mein ek baar dekh.

**Manual (Part A) wala cleanup:** EC2 → Instances → select → Terminate. Phir Security Groups delete, Elastic IP **release** (unattached EIP ka charge lagta hai), key pair rakh sakta hai.

---

## L. Cheat sheet

```bash
# ---------- Terraform ----------
terraform init -reconfigure -backend-config=../../backend.hcl -backend-config=key=cluster/dev/terraform.tfstate
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
terraform output
terraform state list

# ---------- Jenkins server ----------
sudo systemctl status|restart jenkins
sudo journalctl -u jenkins -f
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
id jenkins                                  # docker group check

# ---------- Kubernetes ----------
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd
kubectl argo rollouts get rollout order-service -n order-service -w
kubectl argo rollouts promote order-service -n order-service   # pause skip karna
kubectl argo rollouts abort   order-service -n order-service   # manual abort
kubectl get analysisrun -n order-service
kubectl get clusterpolicy
kubectl get policyreport -A
kubeadm token create --print-join-command    # master pe

# ---------- Monitoring ----------
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093   # Alertmanager UI
kubectl get prometheusrules -A                           # saare alert rules
kubectl get servicemonitors -A                           # kya-kya scrape ho raha hai
kubectl get cm -A -l grafana_dashboard=1                 # dashboards
aws cloudwatch describe-alarms --state-value ALARM --query 'MetricAlarms[].AlarmName'
aws cloudwatch set-alarm-state --alarm-name <name> --state-value ALARM --state-reason test
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status   # node pe

# ---------- App ----------
curl http://<node-ip>:30080/api/version
curl http://<node-ip>:30080/api/orders
curl -X POST -H 'Content-Type: application/json' -d '{"item":"pen","quantity":3}' http://<node-ip>:30080/api/orders
curl http://<node-ip>:30080/actuator/health

# ---------- Local build ----------
cd app && mvn -B verify && docker build -t order-service:local .
docker run --rm -p 8080:8080 order-service:local
```

---

### Interview mein bolne layak summary

> "Maine ek GitOps-based delivery platform banaya. Jenkins Java microservice build karta hai, tests chalata hai, Trivy se image scan karta hai, aur immutable tag ke saath Docker Hub pe push karta hai. Deployment ke liye Jenkins cluster ko touch nahi karta, sirf GitOps repo mein image tag commit karta hai, aur har environment ke cluster mein Argo CD usko pull karke sync karta hai. Infra Terraform se banta hai: kubeadm-based Kubernetes clusters EC2 pe, aur same code dev, staging, prod mein approval gates ke saath promote hota hai. Policy-as-code teen layers mein hai: Terraform plans aur rendered manifests pe conftest/OPA CI mein, aur Kyverno plus Pod Security Admission cluster ke andar. Releases Argo Rollouts canary se jaate hain jo Prometheus success rate check karta hai aur bad version ko automatically abort karta hai. Jenkins phir GitOps commit revert kar deta hai. Clusters hardened hain: IMDSv2, encrypted volumes, audit logs, default-deny NetworkPolicies, non-root read-only containers.
>
> Monitoring teen layers mein hai. Cluster ke andar Prometheus SLO-based multi-window burn-rate alerts chalata hai: 99.5% availability aur latency SLO. Alertmanager grouping, inhibition aur severity routing ke saath Slack pe bhejta hai, aur har alert mein runbook link hota hai. Grafana dashboards code mein hain, error-budget aur deployment markers ke saath. Cluster ke bahar CloudWatch agent aur composite alarms (suppression ke saath) SNS pe email bhejte hain, taaki poora cluster gir jaye tab bhi pata chale. Audit logs off-host CloudWatch mein jaate hain. Aur Jenkins approval, rollback aur release events Slack pe bhejta hai."
