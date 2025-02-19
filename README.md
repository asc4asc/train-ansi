# Sachen zur Information:

# Idempotenz 
ist ein zentrales Konzept in Ansible und bezieht sich auf die Eigenschaft, dass eine Operation mehrmals ausgeführt werden kann, ohne das Endergebnis zu verändern. Das bedeutet, dass wenn ein Playbook oder ein Task in Ansible mehrfach ausgeführt wird, das System am Ende immer denselben Zustand hat.

Hier ein Beispiel, um das Konzept zu verdeutlichen: Angenommen, du möchtest sicherstellen, dass ein bestimmtes Paket auf einem Server installiert ist. In Ansible könntest du eine Aufgabe definieren, die überprüft, ob das Paket bereits installiert ist und es nur dann installiert, wenn es fehlt. Wenn diese Aufgabe mehrfach ausgeführt wird, wird das Paket nur einmal installiert, was den idempotenten Charakter der Operation zeigt.

ansible -i 192.168.0.62, -m setup 192.168.0.62

ansible -m setup localhost

ansible-inventory --list

https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html

Do make from a playbook a executable brogramm
```
#!/usr/bin/ansible-playbook --inventory=localhost,
```

Has some problem with command line attributes

After install before first ssh in. But only in secure space.
ssh-keyscan -H host >> ~/.ssh/known_hosts

