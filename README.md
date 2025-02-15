# Sachen zur Information:

ansible -i 192.168.0.62, -m setup 192.168.0.62

ansible -m setup localhost

ansible-inventory --list

https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html

Do make from a playbook a executable brogramm
```
#!/usr/bin/ansible-playbook --inventory=localhost,
```

Has some problem with command line attributes
