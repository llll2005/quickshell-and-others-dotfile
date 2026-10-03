#!/bin/sh
# A stand-in for `sudo -A pacman` (test.py): asks for the password through askpass, then
# draws a download, a provider choice and a yes/no the way pacman does (zh_TW strings).
pw=$("$SUDO_ASKPASS" "[sudo] password for test: ") || { echo "sudo: a password is required"; exit 1; }
echo ":: Synchronizing package databases..."
printf " core  12.0 MiB  3.0 MiB/s 00:04 [###---]  30%%\r"; sleep 0.3
printf " core  12.0 MiB  3.0 MiB/s 00:00 [######] 100%%\n"
echo ":: There are 2 providers available for java-runtime:"
echo ":: Repository extra"
echo "   1) jdk-openjdk  2) jre-openjdk"
printf "\n輸入某個數字（預設=1）： "
read n; echo "picked provider $n"
printf ":: 進行安裝嗎？ [Y/n] "
read a; echo "answered $a"
echo "error: example failure line"
[ "$pw" = "secret" ] && exit 0 || exit 3
