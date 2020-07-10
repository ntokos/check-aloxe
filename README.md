## Description
check-aloxe is a plugin written in Perl for use with Icinga/Nagios to check status and report statistics on Alcatel OmniPCX Enterprise (OXE) PBXs.

It connects (currently only via telnet) to an Alcatel OXE PBX and reports:
 - coupler (i.e. cards) service status for a given crystal number and a user specified list of coupler types or a 
   given coupler number
 - terminal (i.e. phones, faxes etc) status statistics for the PBX or a specific crystal number
 - trunk group channel usage statistics (Free vs non Free channels) for a given trunk group number
 - link channel usage statistics (Free vs non Free channels) for a given pair of crystal number/coupler number
The output includes some basic performance data in format understood by icinga/nagios.

## Compatibility
- The plugin was written and tested for Icinga2 v.2.8, 2.9. It probably works on Nagios/Icinga1 too.
- It is tested for Alcatel OXE Releases 5, 6 and 8.

### Prerequisites
- The plugin is built using the [Monitoring::Plugin](https://metacpan.org/pod/Monitoring::Plugin) Perl module.
- It currently also uses the [Net::Telnet](https://metacpan.org/pod/Net::Telnet) Perl module to connect to the PBX.

## How it works
The plugin establishes a telnet connection to the PBX and then issues one of the commands:
- `config`
- `listerm`
- `trkstat`

## Install
- Just copy the `check_aloxe.pl` file inside your (local) plugins directory.
- You will then need to create a host configuration with the apropprirate variables, a command and the needed services. See the guide on  [how you can do these in Icinga2](#how-to-use-in-icinga2).

## How to use
You can always run it (via command line) with the `-h` or `--help` option to see the help text.

Here is a more detailed explanation of the command options and things to be aware of:

 | Option | Value | Description |
 | :--- | :---: | :--- |
 | `-H,--host` | *IPv4 addr string* | IP address of the PBX management interface |
 | `-m,--mode` | *String* | What mode the plugin should run on (i.e. what to check): |
 |   | 'coupler' | Checks the status of couplers in a given crystal number.<br>If you provide a list of coupler types (option `-y`) only those coupler types will be checked.<br>If you provide a coupler number (option `-c`) only that coupler will be checked.<br>Couplers in state 'IN SERVICE' are considered OK, those in state 'OUT OF SERVICE' are reported as CRITICAL and those that are *not* in states similar to 'REG NOT INIT', 'MISS MAO FILE', 'MISS OPS FILE' are reported with WARNING.<br>The plugin output includes only the CRITICAL/WARNING couplers (otherwise it reports total number of OK couplers).<br>The performance data contain status totals per coupler type (value=couplers of this type that are OK;warn=0;crit=0;min=0;max=total couplers of this type) |
 |   | 'link' | Check the channel usage on the link designated by a given crystal/coupler pair (specified via the `-i`, `-c` options) and report Busy vs total channels.<br>A channel state of value different than 'F' is considered Busy.<br>In the current plugin version, there is no way to specify warning/critical thresholds. When *all* link channels are Busy, the plugin will report a WARNING status.<br>You can provide a text (via the `-r-` option) describing the PBX on the otherside of the link that will be added on the plugin output (useful as a place to store the crystal/coupler pair of the remote PBX).<br>The performance data contain the number of *non* Free channels (value=total non Free channels;warn=total channels;crit=0;min=0;max=total channels). It also contains in and out parameters (same values) so you can create weathermap lines in Nagvis. |
 |   | 'terminal' | Checks the status of the terminals on the PBX.<br>If the option `-i` is provided, then only the terminals on the given crystal number will be checked.<br>The plugin will report the number of different terminal types, the total number of terminals that are OK and total number of terminals that are not OK (based on the flags of the last column of PBX command 'listerm')<br>The performance data contain total status numbers per terminal type (value=total terminals of this type that are OK;warn=0;crit=0;min=0;max=total terminals of this type) |
 |   | 'trunk' | Check, similarly to mode 'link', channel usage on a trunk group.<br>The trunk group is specified with its number (via option `-g`) rather than crystal/coupler numbers pair.<br>The plugin output, instead of the given remote pbx, will contain the configured name of the trunk group. |
 | `-i,--crystal` | *Integer* | Perform check on the given crystal number |
 | `-c,--coupler` | *Integer* | Perform check on the given coupler number (and the crystal given by option `-i`) |
 | `-y,--ctype` | *String* | A comma-separated list of coupler types that should be checked (valid only for mode 'coupler') |
 | `-g,--trkgroup` | *Integer* | The trunk group number for which to check channel usage (valid only for mode 'trunk') |
 | `-r,--rdescr` | *String* | A descriptive text of the remote pbx on a link, to be included in the plugin output (only valid for mode 'link') |
 | `-t,--timeout` | *Integer* | Set plugin timeout in secs (currenly this only affects the telnet timeout, see below) |
 | `-v,--verbose` |  | Print verbose information (currently only one verbose level is implemented) |

#### Timeouts
The telnet timeout is set to 2secs less than the plugin timeout. The default plugin timeout is 15 secs (setting telnet timeout to 13secs).
Note that on some PBXs (with old CPUs) the telnet session might not respond in time even with the default timeout. So you might need to consider increasing the plugin timeout (using the `-t|--timeout` option) to more than 15secs if you get telnet timeouts.

### Example runs
- Check couplers for coupler types in specified list on a given crystal:
```
check_aloxe.pl -H 10.1.1.1 -m coupler -i 0 -y "CPU6,CPU7_STEP2,INTOF_A,INTOF_B,INTIPA,PRA2,UA32,Z32,Z24,Z24_2,Z12,Z12_2,UAZP,NDDI"
Couplers OK - All 19 couplers OK | CPU7_STEP2=2;0;0;0;2 INTIPA=1;0;0;0;1 INTOF_A=6;0;0;0;6 PRA2=10;0;0;0;10

check_aloxe.pl -H 10.1.1.1 -m coupler -i 3 -y "CPU6,CPU7_STEP2,INTOF_A,INTOF_B,INTIPA,PRA2,UA32,Z32,Z24,Z24_2,Z12,Z12_2,UAZP,NDDI"                 
Couplers CRITICAL -  3-4-Z24: OFF | INTOF_B=1;0;0;0;1 UA32=1;0;0;0;1 Z24=0;0;0;0;1 
```
- Check coupler on a given crystal/coupler numbers pair:
```
check_aloxe.pl -H 10.1.1.1 -m coupler -i 0 -c 26
Couplers OK - All 1 couplers OK | INTOF_A=1;0;0;0;1
```
- Check channel usage on link designated by a given crystal/coupler numbers pair
```
check_aloxe.pl -H 10.1.1.1 -m link -i 0 -c 11
Link from: (0-11) OK - 28 Free channels | NonFree=2;30;0;0;30 in=2;0;0;0;30 out=2;0;0;0;30
```
- Check channel usage link designated by a given crystal/coupler numbers pair, remote bpx has the given description
```
check_aloxe.pl -H 10.1.1.1 -m link -i 0 -c 11 -r "mypbx2 (0-26)"
Link from: (0-11) to: mypbx2 (0-26) OK - 28 Free channels | NonFree=2;30;0;0;30 in=2;0;0;0;30 out=2;0;0;0;30
```
- Check terminals status on the PBX
```
check_aloxe.pl -H 10.1.1.1 -m terminal
Terminals OK - 6 types, 677 total terminals, 581 OK, 96 not OK | 4010-VLE_3=69;0;0;0;83 4012-LE=187;0;0;0;227 4019=88;0;0;0;108 4020-LE_3G=37;0;0;0;42 4034-MR2=56;0;0;0;62 AUTPOS=144;0;0;0;155
```
- Check terminals status on the PBX only on a given crystal
```
check_aloxe.pl -H 10.1.1.1 -m terminal -i 1
Terminals OK - 5 types, 262 total terminals, 232 OK, 30 not OK | 4012-LE=79;0;0;0;96 4019=19;0;0;0;26 4020-LE_3G=18;0;0;0;21 4034-MR2=36;0;0;0;38 AUTPOS=80;0;0;0;81
```
- Check channel usage statistics on trunk group number 1
```
check_aloxe.pl -H 10.1.1.1 -m trunk -g 1
TG 1: PSTN-OUT OK - 20 Free channels | NonFree=10;30;0;0;30 in=10;0;0;0;30 out=10;0;0;0;30
```


### How to use in Icinga2
1. Create a hosts configuration file (e.g. a *pbx.conf* file inside your icinga2 *conf.d* directory).
For each of your PBXs create a host declaration similar (but not limited) to this:
```processing
object Host "mypbx1" {
   import "generic-host"

   address = "pbx ip address"

   vars.monitorcouplers = "CPU6,CPU7_STEP2,INTOF_A,INTOF_B,INTIPA,PRA2,UA32,NDDI"    # add more types

   vars.monitorterminals = true

   vars.crystals["0"] = { monitor = true }
   vars.crystals["1"] = { monitor = true }
   vars.crystals["2"] = { monitor = true }
   ...
   ...

   vars.trkgroups["1"] = { monitor = true }
   vars.trkgroups["2"] = { monitor = true }
   ...
   ...

   vars.links["2001"] = {
        monitor = true
        crystal = 0
        coupler = 11
        remote_description = "mypbx2 (Crystal:0, Coupler:26)"
   }
   vars.links["2002"] = {
        monitor = true
        crystal = 0
        coupler = 0
        remote_description = "mypbx3 (Crystal:0, Coupler:5)"
   }
   ...
   ...
}
```
2. Now create a command (e.g. inside your *commands.conf* file) like this:
```processing
// Command to check Alcatel OXE PBXs
object CheckCommand "aloxe" {
    import "plugin-check-command"
    command = [ LocalPluginDir + "/check_aloxe.pl" ]
    arguments = {
            "--host" = "$aloxe_address$"
            "--mode" = "$aloxe_mode$"
            "--crystal" = "$aloxe_crystal$"
            "--coupler" = "$aloxe_coupler$"
            "--ctype" = "$aloxe_ctype$"
            "--trkgroup" = "$aloxe_trkgroup$"
            "--rdescr" = "$aloxe_rdescr$"
            "--timeout" = "$aloxe_timeout$"
    }
 
    vars.aloxe_address = "$address$"
    vars.aloxe_mode = "coupler"
    vars.aloxe_timeout = 20
}
```
3. Then create a number of services (e.g. inside your *services.conf* file) that use the command on the hosts.
In Icinga2 this is much easy to do by using apply rules.

Here are some examples:
- create services to check couplers status for each desired crystal:
```processing
apply Service "crystal-" for (crystal => c_conf in host.vars.crystals) {
   import "generic-service"
 
   check_command = "aloxe"
 
   vars.aloxe_mode = "coupler"
   vars.aloxe_crystal = crystal
   vars.aloxe_ctype = host.vars.monitorcouplers
 
   assign where host.address && host.vars.crystals && host.vars.monitorcouplers && c_conf.monitor
 }
```
- create services to report channel usage statistics for each trunk group:
```processing
apply Service "trunk-group-" for (tgroup => t_conf in host.vars.trkgroups) {
   import "generic-service"
 
   check_command = "aloxe"
 
   vars.aloxe_mode = "trunk"
   vars.aloxe_trkgroup = tgroup
 
   assign where host.address && host.vars.trkgroups && t_conf.monitor
 }
```
- create services to report channel usage statistics for each link:
```processing
 apply Service "link-" for (l_num => l_conf in host.vars.links) {
   import "generic-service"
 
   check_command = "aloxe"
 
   vars.aloxe_mode = "link"
   vars.aloxe_crystal = l_conf.crystal
   vars.aloxe_coupler = l_conf.coupler
   vars.aloxe_rdescr = l_conf.remote_description
 
   assign where host.address && host.vars.links && l_conf.monitor
}
```
- create services to report terminal status statistics for each PBX:
```processing
apply Service "terminals" {
   import "generic-service"
 
   check_command = "aloxe"
 
   vars.aloxe_mode = "terminal"
 
   assign where host.address && host.vars.monitorterminals
} 
```

## Possible future additions
####Implementation
- Add *ssh* as method of connecting to a PBX (using system call), possibly via command line option. Or even throw away telnet option alltogether.
- Add a mode to display status of remote crystals connected in a coupler
- Add a mode to display crystal topology information
- Add the ability to specify warning/critical thresholds for channel usage in links and trunk groups.

#### Goodies
- Describe how to configure a NagVis map to show the PBXs and the links interconnecting them.

## Notes
*Due to lack of available time, I will probably not respond to any requests, while my response to questions and comments will be very limited.*

This is a pretty amateur effort in perl programming. _I encourage you to improve this plugin to make it better, fit your needs and fix any issues/bugs you find_
