# Validate and demo locally (Windows + VS Code)

No AWS account is needed. You will:

1. validate the Terraform code in **PowerShell**
2. run the Ansible demo in **WSL (Ubuntu)**, because Ansible does not run natively on Windows
3. open the generated HTML report in your browser

Commands are meant to be pasted into the VS Code terminal (**Terminal → New Terminal**).

---

## Part 1 – Validate Terraform (PowerShell)

Prerequisite: Terraform 1.10 or later (`winget install Hashicorp.Terraform`).

```powershell
cd C:\Users\<you>\path\to\mytest\aws-disk-monitoring

# 1. Formatting check (no output = all files are formatted)
terraform fmt -check -recursive terraform

# 2. Validate every root configuration and module (no AWS credentials needed)
Get-ChildItem terraform\live, terraform\modules -Directory | ForEach-Object {
    Write-Host "== $($_.Name)"
    terraform -chdir="$($_.FullName)" init -backend=false -input=false | Out-Null
    terraform -chdir="$($_.FullName)" validate
}
```

Every folder should print `Success! The configuration is valid.`

The first run downloads the AWS provider, which takes a few minutes. Later runs are fast.

---

## Part 2 – Run the Ansible demo (WSL)

### Step 1 – Open WSL in the VS Code terminal

```powershell
wsl
```

The prompt changes to something like `you@PC:/mnt/c/...$`. Every command from here on is a Linux command.

### Step 2 – Put the repo in your WSL home folder

Ansible **ignores `ansible.cfg` when it runs from `/mnt/c/...`**, because Windows folders look world-writable to Linux. Working from your Linux home folder avoids that:

```bash
git clone https://github.com/khansameer421421/mytest.git ~/mytest
cd ~/mytest/aws-disk-monitoring
```

(Already cloned on Windows? You can copy it instead: `cp -r /mnt/c/Users/<you>/path/to/mytest ~/mytest`.)

### Step 3 – Install Ansible in a virtual environment (one time)

```bash
python3 -m venv ~/.venvs/diskmon
source ~/.venvs/diskmon/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
ansible --version
```

If `python3 -m venv` says venv is missing, run `sudo apt update && sudo apt install -y python3-venv python3-pip` and try again.

In a new terminal later, only the `source ~/.venvs/diskmon/bin/activate` line is needed again.

### Step 4 – Run the demo

```bash
ansible-playbook -i inventories/local playbooks/collect_disk_usage.yml
```

What happens:

| Demo host | What it shows |
|---|---|
| `demo-web-01`, `demo-db-01` | Your WSL machine, under two names in two different fake AWS accounts. Shows collection and aggregation across accounts |
| `demo-legacy-01` | A deliberately unreachable address (192.0.2.10). It waits about 10 seconds, then is reported as a **coverage gap** instead of failing the run |

The run ends with a **Fleet summary**, for example `Hosts: 2/3 reporting across 2 account(s)`.

### Step 5 – Open the report

```bash
explorer.exe "$(wslpath -w reports/latest/disk_report.html)"
```

This opens the report in your Windows browser. Next to it are `disk_report.json` and `disk_report.csv`, plus `reports/history.csv`, which gains one line per run.

### Step 6 – Show alerts firing (good for a live demo)

Your disks are probably not 80% full, so nothing shows as warning or critical. Lower the thresholds for one run:

```bash
ansible-playbook -i inventories/local playbooks/collect_disk_usage.yml \
  -e disk_warning_pct=1 -e disk_critical_pct=5
```

Refresh the report: filesystems now appear under **Needs attention** as critical or warning.

To see the run fail on critical findings, as you might gate a CI pipeline:

```bash
ansible-playbook -i inventories/local playbooks/collect_disk_usage.yml \
  -e disk_critical_pct=5 -e report_fail_on_critical=true
```

---

## Part 3 – Lint checks (optional, same as CI)

Inside WSL, with the virtual environment active:

```bash
pip install ansible-lint yamllint
yamllint .
ansible-lint
for p in playbooks/*.yml; do ansible-playbook --syntax-check -i inventories/local "$p"; done
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `[WARNING]: Ansible is being run in a world writable directory ... ignoring it as an ansible.cfg source` | You are running from `/mnt/c/...`. Use the copy in `~/mytest` (Step 2) |
| `ansible-playbook: command not found` | Activate the venv: `source ~/.venvs/diskmon/bin/activate` |
| `couldn't resolve module/action 'amazon.aws...'` | Run `ansible-galaxy collection install -r requirements.yml` from the `aws-disk-monitoring` folder |
| Demo pauses about 10 s on `demo-legacy-01` | Expected: that host is unreachable on purpose |
| `wsl` says no distribution is installed | In an **admin** PowerShell: `wsl --install -d Ubuntu`, reboot, then create a Linux user |
