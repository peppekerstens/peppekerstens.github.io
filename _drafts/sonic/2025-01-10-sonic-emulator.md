---
title: Sonic Emulator
parent: main
---

# The SONiC promise

In case you have not heard; SONiC is supposedly the latest and greatest in networking OS-es. To quote [the website](https://sonicfoundation.dev/):

*"Software for Open Networking in the Cloud (SONiC) is an open source network operating system (NOS) based on Linux that runs on switches from multiple vendors and ASICs"*

It should bring us a unified management interface for differente hardware and faster development of new features with better intergration between different hardware. Sounds to good to be true...

## The use case

As it turnes out, I have been asked to help out building an ~~Azure HCI~~ ~~Azure Stack~~ [Azure Local](https://azure.microsoft.com/products/local) (come on Microsoft, really?) stamp for internal use in my company. Probably because of my experience with building and maintaining [VMM](https://learn.microsoft.com/system-center/vmm/overview)/[Azure Pack](https://learn.microsoft.com/previous-versions/azure/windows-server-azure-pack) environments on the past. But this has been around 2014-2019 I believe. Ancient history in IT terms. 

Even though much of the management interfacing has changed, core technology components (Clustering, Hyper-V, Storage Spaces) and requirements not so much. It was critical to have networking and network interfacing absolutaly correctly and homogeneously configured. With this I mean *every* aspect of the network stack, including firmare, switching, drivers etcetera.

Quriosity had the better of me, creating kremlins in my head that I need to brush-up  

## SONiC emulator

https://medium.com/sonic-nos/creating-a-sonic-nos-virtual-lab-5a9ec431e0d0
