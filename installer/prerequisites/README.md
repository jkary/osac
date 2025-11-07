# Required components for which OSAC expects to be available

## Overview

The OSAC solution makes some assumptions about the cluster it is being installed onto.
Your administrator may have setup one or more of these components already and if you are
not the administrator then you should check with them first.

The OSAC solution assumes the following components are installed:

- Red Hat Advanced Cluster Management
- Red Hat Ansible Automation Platform
- Cert Manager
- Red Hat Openshift Virtualization with the desired storageclass

The manifests provided in this directory are meant as examples only and can serve to be
useful for developers and admins.
