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

Even back then, I left most of the network configuration details to others and had already started to focus more on automated deployments. Current situation does not differ that much; I believe to have some very proficient colleagues capable of configuring the needed networking just fine. That being said, the company policy to use SONiC as default switch OS is new. So the kremlins in my head are screaming that I needed to brush-up on networking technology and configuration proficiency fast...

## SONiC emulator

The get to know any new system, it is quite common to start with an emulator. Especially concerning networking devices as their investment can be severe and need to endure.

Diving down deeper into the rabbit hole, I stumbled upon the [official SONiC github wiki and noticed that the provided software switch](https://github.com/sonic-net/SONiC/wiki/SONiC-P4-Software-Switch) to use as a test-bed [is not support anymore](https://github.com/sonic-net/SONiC/issues/1429).

The github repo seems to be maintained quite badly overall. This to me seems not like good sign for any organization trying to advocate their emerging technology. Especially not when the claim is that it is open source.

So I looked elsewhere for sources. It first a came across [the CISCO 8000 emulator](https://blogs.cisco.com/developer/8000vemulatorsandboxsonic01). But this turned out to be a sandbox environment, hosted by CISCO, which you need to sign-up for, request and receive a ~6 hour period availability after going trhough hoops and loops. Too restricted time frame wise; I tend to work on this over many days in short time sprints and too little freedom to do as like. Not my cup of tea.

Then I stumbled upon a [writeup by 'Adam Dunstan' on Medium](https://medium.com/sonic-nos/creating-a-sonic-nos-virtual-lab-5a9ec431e0d0). Don't know him and have no affiliation with him whatsoever. But total transparency here; next session is inspired on that article. Just not the same or copied*. This to avoid any copyright claims. On the other hand, I feel obliged to attribute him and his work as I have used it as a source for mine.

### Download the image

As new builds are being published regularly, it makes sense to detect latest official build first [here](
https://sonic-build.azurewebsites.net/ui/sonic/Pipelines). Look for the latest version of 'Azure.sonic-buildimage.official.vs', go to 'build history' and then in top row, choose 'Artifacts'.

You will end up running into another list of files. These files represent solutions, build for several platforms (OSses). A list of commonly used hypervisors and container below:

| platform | image name |
| -- | -- |
| Docker | target/docker-sonic-vs.img.gz |
| KVM | target/sonic-vs.img.gz |
| Hyper-V | target/sonic-vs.vhdx |

The focus is getting the [official SONiC github wiki scenario](https://github.com/sonic-net/SONiC/wiki/SONiC-P4-Software-Switch) working via Docker again.




\* One reason is that I really dislike Medium who seems to be more interested in logging your online behavior and monotizing on information than anything else. Everytime I am forced to accept their cookie policy i get a clickbait feeling. 






