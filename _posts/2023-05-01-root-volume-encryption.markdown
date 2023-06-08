---
layout: post
title: "Root Volume Encryption"
description: "Passwordless root volume encryption with a Yubikey."
modified: 2023-05-01
category: articles
tags : [linux luks debian yubikey]
---

My Linux work station is a headless server like system that I access via SSH. I
would like to make sure the data on this system is secure even if some one were
to physically get hold of the SSDs and install them in another system. To that
end I always make sure I am using encrypted volumes.

My Linux distro of choice is Debian, usually the current stable version which
at the time of writing is bullseye. The standard Debian installer has an option
to encrypt the root partition. This option does not encrypt the boot partition
(which is possible). But since this system is my daily driver for work and I
want it to be stable and reliable and low maintenance, I decided to go with the
installer option.

Technically this option creates a partition with a LUKS encrypted volume. This
volume is made the only physical volume in an LVM volume group. By default one
logical volume is created for the root filesystem and one for swap. This means
the swap on the system is also encrypted.

Obviously, this setup will require a LUKS passphrase to be entered on every
boot to decrypt the volumes. This is an inconvenience on a system that is
intended to be headless (no display or keyboard). This blog post demonstrates
one solution to this problem using a Yubikey device.

### Yubikeys

Yubikeys are small USB security devices that provide many different
authentication services.

After plugging in my Yubikey 5C and installing the command line tools.

```bash
$ sudo apt install -y yubikey-personalization
```

You can see your USB Yubikey device.

```bash
$ lsusb -d 1050:0407
Bus 001 Device 006: ID 1050:0407 Yubico.com Yubikey 4/5 OTP+U2F+CCID
```

The service used to boot the system is called OTP, or one time password.
Yubikeys have two OTP slots. The first comes preconfigured with the Yubico
OTP credential.

```bash
$ sudo ykinfo -a
serial: XXX
serial_hex: XXX
serial_modhex: XXX
version: 5.2.4
touch_level: 775
programming_sequence: 3
slot1_status: 1
slot2_status: 1
vendor_id: 1050
product_id: 407
```

I left this slot alone and configured the second slot with a challenge-response
credential.

```bash
$ sudo ykpersonalize -2 -ochal-resp -ochal-hmac -ohmac-lt64 -oserial-api-visible
Firmware version 5.2.4 Touch level 775 Program sequence 3

Configuration data to be written to key configuration 2:

fixed: m:
uid: n/a
key: h:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
acc_code: h:000000000000
OATH IMF: h:0
ticket_flags: CHAL_RESP
config_flags: CHAL_HMAC|HMAC_LT64
extended_flags: SERIAL_API_VISIBLE

Commit? (y/n) [n]: y
```

When this credential is passed a challenge password from the user it returns
a hashed response unique to the challenge and the specific Yubikey. This
response will be used as the LUKS passphrase.

### Yubikey LUKS

Fortunately there is an existing tool called yubikey-luks[^1] that helps
integrate the Yubikey with LUKS encryption. This tool is even available in the
Debian package repositories, but I decided to build a newer version of the
package from the Git repo.

First install the build dependencies and clone the GitHub repository.

```bash
$ sudo apt install -y devscripts udisks2
$ sudo apt build-dep -y yubikey-luks
$ git clone https://github.com/cornelinux/yubikey-luks.git /tmp/yubikey-luks
$ cd /tmp/yubikey-luks
```

Build the package and install it.

```bash
$ make clean builddeb NO_SIGN=1
$ sudo dpkg -i DEBUILD/yubikey-luks_*_all.deb
```

During install the initramfs boot image is regenerated to include the
yubikey-luks scripts and the other dependencies and any subsequent changes
to the yubikey-luks configuration will require the initramfs to be regenerated
manually.

### Configuration

The yubikey-luks tool is a collection of scripts that make it easier to
manage the encrypted volume. The most important script is the key script
which is used to unlock the volume. After installing the package you should be
able to run the keyscript.

```bash
$ sudo /usr/share/yubikey-luks/ykluks-keyscript
Please insert Yubikey and press enter or enter a valid passphrase
Accessing yubikey...
Retrieved the response from the Yubikey
XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

This will still ask for a challenge password but it will also require the
Yubikey to generate the response. Using the keyscript in this configuration is
the equivalent of a 2-factor authentication.

It is possible to configure yubikey-luks to use a hardcoded challenge password
in the `/etc/ykluks.cfg` file. Edit this file and set the value of
`YUBIKEY_CHALLENGE` (or uncomment the line).

```
YUBIKEY_CHALLENGE="notmyrealpassword"
```

Now running the keyscript will response with the same hash string every time. Of
course this will effectively reduce the authentication back to 1-factor, that
being the physical Yubikey.

Commit these changes to the initramfs boot image.

```bash
$ sudo update-initramfs -u
```

### Enrollment

Next we need to add the Yubikey response as a passphrase to a LUKS key slot on
the root partition. The Debian installer will have created LUKS key slot 0 using
the passphrase chosen during installation. This key slot will not be touched, so
if you lose your Yubikey, you can still use the original passphrase.

You can view the current luks keyslots (replacing the device with yours).

```bash
$ sudo cryptsetup luksDump /dev/nvme0n1p3
```

The yubikey-luks tool includes a helpful script to add the Yubikey response to a
LUKS keyslot (by default keyslot 7)

```bash
$ sudo yubikey-luks-enroll -d /dev/nvme0n1p3
```

This might ask you for the challenge password again, so just enter the password
you used in the config file. It will also ask for an existing LUKS passphrase,
this is the passphrase you chose during installation.

You should now be able to see the new keyslot with the dump command.

### Crypttab

Finally we are now ready add the keyscript to the `/etc/crypttab` file. This
file configures which encrypted volumes to open and how to open them. By default
if a keyfile or keyscript is not configured the boot process will ask for a
passphrase. In this file, identify your boot partition and add the option

```
keyscript=/usr/share/yubikey-luks/ykluks-keyscript
```

My updated crypttab file looks like

```
nvme0n1p3_crypt UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX none luks,discard,keyscript=/usr/share/yubikey-luks/ykluks-keyscript
```

Now one final initramfs update.

```bash
$ sudo update-initramfs -u
```

### Reboot

Upon rebooting (if you have a display plugged in) you should see the messages
from the keyscript. There is usually a pause while the keyscript finds the
Yubikey, but in the end it should boot up.

If the Yubikey is removed, the system is locked, and will go back to requesting
a LUKS passphrase during boot up.

### References

[^1]: <https://github.com/cornelinux/yubikey-luks>
