set dotenv-load := true

# ~/.ansible is read-only on this machine; point Ansible's local dirs elsewhere.
export ANSIBLE_LOCAL_TEMP := "/tmp/ansible-local"
export ANSIBLE_SSH_CONTROL_PATH_DIR := "/tmp/ansible-cp"

# Apply Ansible changes to the homelab host (HOST, ANSIBLE_USER from .env)
deploy:
    uv run --project ansible ansible-playbook -i "$HOST," -u "$ANSIBLE_USER" ansible/playbook.yml
