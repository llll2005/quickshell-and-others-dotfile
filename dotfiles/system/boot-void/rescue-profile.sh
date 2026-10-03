# boot-void: in the Rescue console boot (Limine's Recovery > Rescue console sets void.rescue),
# root's login opens the rescue menu. Installed as /etc/profile.d/boot-void-rescue.sh.
case " $(cat /proc/cmdline 2>/dev/null) " in
    *" void.rescue "*)
        if [ "$(id -u)" = 0 ] && [ -t 0 ] && [ -z "$VOID_RESCUE" ]; then
            export VOID_RESCUE=1
            /usr/local/lib/boot-void/void-rescue
        fi ;;
esac
