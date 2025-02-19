# Sachen zur Information:

# Ansible verwenden: Verschiedene Ansätze

## 1. Ansible lokal verwenden

Ansible kann lokal verwendet werden, um Aufgaben auf dem aktuellen System auszuführen. Dies ist nützlich für Einzelplatzrechner oder wenn nur wenige Hosts verwaltet werden müssen.

```bash
ansible all -i localhost, -m ping --connection=local
```

In diesem Beispiel wird das `ping`-Modul verwendet, um eine Verbindung zum lokalen Host herzustellen und zu testen.

## 2. Ansible vom Server (Remote) verwenden

Wenn Ansible auf mehreren Remote-Hosts verwendet werden soll, kann man eine Inventardatei erstellen und das `ansible`-Kommando benutzen, um Playbooks oder Module auf diesen Hosts auszuführen.

### Beispiel-Inventardatei (hosts.ini):
```ini
[webserver]
192.168.1.1
192.168.1.2

[dbserver]
192.168.1.3
```

### Beispiel Playbook ausführen:
```bash
ansible-playbook -i hosts.ini site.yml
```

Hier wird das `site.yml` Playbook auf den in der Inventardatei definierten Hosts ausgeführt.

## 3. Ansible-pull verwenden

`ansible-pull` ist eine Alternative zu `ansible-push`. Es zieht die Playbooks von einem Versionskontrollsystem (z.B. Git) auf den Remote-Host und führt sie dort aus. Dies ist nützlich, um sicherzustellen, dass alle Hosts stets mit den neuesten Konfigurationen aktualisiert werden.

### Beispiel:
```bash
ansible-pull -U https://github.com/your-repo/your-playbook-repo.git
```

In diesem Beispiel wird das Playbook-Repository von GitHub geklont und auf dem Host ausgeführt.

## 4. Direkte Befehle mit -i localhost, und --connection=local

Um direkte Befehle lokal auszuführen, können die Parameter `-i localhost,` und `--connection=local` verwendet werden.

### Beispiel:
```bash
ansible all -i localhost, -m shell -a "echo Hello, World!" --connection=local
```

In diesem Beispiel wird der Shell-Befehl `echo Hello, World!` lokal ausgeführt.
```

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

