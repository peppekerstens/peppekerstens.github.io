---
---

# Ramblings and tid bits of me

Here you may find ramblings of any and all things that keep me awake at night or busy at day. Good or bad, you decide. Chances are this site does only get updated sporadically because like most thing I start with the best intentions intending to do things differently this time around only to end up loosing myself in a rabit hole details and astrays.

There is no concept, no promise, no specific goal other then me trying to write things down and publish. That being said, me being an random IT guy, you may expect technical stuff. So let's dig in right there.

# Minimalistic Windows - the journey to WinGet Desired State Configuration

For reasons not important right now, I wound up looking through some old laptops I had laying around and found my son's old Dell Lattitude 3190 used during his education. This thing has really limited specs; N5000, 4 cores, 1.1Ghz with 4Gb memory and 128GB Mvme disk. You cannot expand its memory because it is fixed on the main board. Input/output is limited to two 3.0 USB ports and an HDMI port.

On the plus side, it has very low power demands and a touch screen which can be folded around, creating a tablet of sorts. So it could still be a nice little causual Internet browse device or an dashboard for [Home Assistant](https://www.home-assistant.io/) (another project which still needs to be rebirthed someday).

I already resetted this thing to defaults way back, removing any other software except Windows 10 only. To my surprise, it is Windows 11 compatible. The update took ages, but it succeeded. But as you may have guessed, it was so slowwwwww. The CPU at 100% constantly. Memory at 91%. Constantly swapping to disk. Draining the battery in no time. In that state, not vaible for its intended purpose.

I started wondering if I could make it perform better by reducing the resource footprint.

## My requirements

In total transparency, my requirements grew along my journey.

- Reduce the footprint of Windows
- Ensure default security measures provided
- Ensure updatability
- Ensure the same end-result, regardless of begin state
- Can be used in any scenario

I do not require or want to

- Reduce the footprint on disk
- Remove Edge as a browser
- Distribute or install a large number of machines

## Existing solutions

I was already aware of others efforting in reducing Windows program bloat. During work I stumbled upon a few sources in the past and decided to search for them again. 

### Win11Debloat

This is a PowerShell script which you can use in interactive mode or silent via the use of parameters. I have not tested its latest inception, but tried it in the past. It does a nice job of cleaning up Windows. The advantage over Tiny11Builder is that it is simpler; it does not require a complete reinstall of Windows.

https://github.com/Raphire/Win11Debloat

### Tiny11builder

With this script you create an Windows 11 image which in turn can be used to install a machine. By using this setup, it is clearly targetted towards the more IT savvy crowd. The advantage over Win11Debloat is that you could potentionally save install time during a mass reinstall of of machines. The downside is that you end up reinstalling Windows and thus loosing whatever software and information on that machine.

https://github.com/ntdevlabs/tiny11builder

### Others

With a near 100% certainty, there may be other solutions available. I just don't know them and did not bother to look. Chances are, that whatever I created, someone already did as well.

## Simplify 

Before someone gets cross at me; both solutions seem to have been maintained quite well do a nice job. The hard work most times is finding what can- and cannot be disabled. Whatever I am publishing here; it is build upon that hard work and I fully credit whomever has done so. 

My itch with both solutions ended up being that they are quite bloated themselves and just remove stuff instead of ensuring some stuff only remains. The bloated part I can understand; in order to ensure proper behavior in most scenario's and understandable responses for the mass, a lot of whistles and bells must be added.

``` PowerShell
#Requires -RunAsAdministrator

$winget = Get-Module -Name Microsoft.WinGet.Client -ListAvailable
If ($null -eq $winget){
    Install-Module -Name Microsoft.WinGet.Client
}
Import-Module -Name Microsoft.WinGet.Client
#https://powershellisfun.com/2024/11/28/using-the-powershell-winget-module/

#Check Winget


# Windows stuff
$packagePrefixes  = @('Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GamingApp', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsAlarms', 'microsoft.windowscommunicationsapps', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'MicrosoftCorporationII.MicrosoftFamily', 'MicrosoftCorporationII.QuickAssist', 'MicrosoftTeams', 'Microsoft.549981C3F5F10')

# Bing stuff
$packagePrefixes += @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch')

# Office like stuff
$packagePrefixes += @('Microsoft.Office.OneNote', 'Microsoft.SkypeApp','Microsoft.549981C3F5F10', 'Microsoft.BingSearch', 'Microsoft.Teams.Free', 'Microsoft.DevHome','Microsoft.XboxAp','Microsoft.XboxIdentityProvider','Microsoft.MixedReality','Microsoft.OutlookForWindows')

# Xbox stuff
$packagePrefixes += @('Microsoft.Xbox.TCUI', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.XboxAp','Microsoft.XboxIdentityProvider')

# Miscellanious
$packagePrefixes += @('Clipchamp.Clipchamp', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.YourPhone', 'MicrosoftTeams', 'Microsoft.Teams.Free', 'Microsoft.SkypeApp', 'Microsoft.MixedReality')


$packagePrefixes +=


$packagePrefixes += 
#Microsoft.OneDrive
#Microsoft.OneDriveSync
#Microsoft.MicrosoftEdge
#Microsoft.EdgeWebView2Runtime

$installedPackages = Get-WinGetPackage

$packagesToRemove = @()
$packagePrefixes | Foreach-Object { 
    $currentPackage = $_ 
    $packagesToRemove += $installedPackages.where{$_.Id -like "*$($currentPackage)*"}
}
$packagesToRemove | Foreach-Object {Uninstall-WinGetPackage -Name $_.Name -Force}


```



## Light weight development

Transending further into my rabbit hole

So I'm actually forcing myself to create this content using this laptop. No promises how long this will continue; the screen is 11 inches, my eye sight is bad. Besides that, I really dislike to use a mousepad and a laptop keyboard as well. Using this thing for a prolonged time it is a recipe for headache and sore neck.

At this point, you might be banging your head on the desk, wondering why I don't simply install a Linux disribution on that thing. Well, I like to hurt myself, essentially. 


\* a peek into my mind; I have been doubting on buying one of those N100 based hardware boxes with 2.5Gb NICs to replace my current Internet firewall. They are supposedly capable enough to run proxmox with a software based firewall on top of that. As I needed to clean up a room anyways because the floor is waiting for a replacement like...months, I stumbled upon some older laptops. I started wondering if one of these could be a cheap proof of concept, picked out the Dell Lattitude 3190 first. 

{% assign date = '2020-04-13T10:20:00Z' %}

- Original date - {{ date }}
- With timeago filter - {{ date | timeago }}