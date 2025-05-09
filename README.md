 README: Linux Wi-Fi Sharing Toggle Script

 SYNOPSIS:
   Toggle Linux IP forwarding and NAT between a prioritized Wi-Fi interface
   and a prioritized Ethernet interface, based on MAC address lists.

 FILES:
   - wifishare.sh       : Bash script implementing the toggle logic, auto-scan and MAC management.
   - mac.txt            : Priority list of Wi-Fi and Ethernet MAC addresses.
   - README_linux.md    : This documentation file.

 PREREQUISITES:
   - Linux distribution with bash, iproute2, iptables, ethtool
   - Root privileges (script auto-elevates via sudo)
   - Internet Tools: ip, sysctl, ethtool

 mac.txt FORMAT:
   Lines must start with 'wifi:' or 'ethernet:' followed by a MAC address.
   Accepts '-' or ':' separators, case-insensitive.

   Example:
     wifi:    3C-55-76-48-60-31
     wifi:    A1:B2:C3:D4:E5:F6
     ethernet:5C-60-BA-77-0E-D1
     ethernet:02-AB-CD-EF-12-34

 USAGE:
   1. Place wifishare.sh, mac.txt, and README_linux.md in the same folder.
   2. Make the script executable: chmod +x wifishare.sh
   3. Run: ./wifishare.sh
   4. A menu will prompt you to:
        1) Enable sharing
        2) Disable sharing
        3) Add a Wi-Fi MAC (manual entry)
        4) Add an Ethernet MAC (manual entry)
        5) Auto-add a Wi-Fi MAC (scan & select)
        6) Auto-add an Ethernet MAC (scan & select)
        Q) Quit the script

 LOGGING:
   - All actions and errors are logged to 'logps.txt' in the script directory.
   - Timestamps are in UTC (ISO 8601).

 IMPLEMENTATION DETAILS:
   - MAC list is loaded from mac.txt into arrays.
   - Interfaces are matched by normalized MAC against /sys/class/net/*/address.
   - IP forwarding toggles via sysctl net.ipv4.ip_forward.
   - NAT and forwarding rules applied/removed with iptables.
   - Auto-scan uses 'ip -o link show' and ethtool to list interfaces, MAC, state, and speed.

 NOTES:
   - Requires iptables rules to be supported (legacy or nft).
   - Adjust firewall rules as necessary for your distribution.
   - You can edit mac.txt manually or via menu options.

 LICENSE:
   MIT License (or your preferred license).

 END OF README