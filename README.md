# get-kali-vbox
Automation script to get the current Kali VirtualBox file and add it to VirtualBox

## adding a link to the desktop
```
"C:\Program Files\Git\git-bash.exe" -c "cd /c/Users/<USERNAME_HERE> && ./get_kali_vbox.sh; exec bash"
```

## After installation
```
sudo apt update
sudo apt install -y --reinstall virtualbox-guest-x11
sudo reboot -f
```
