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
 | `-H\|--host` | *IPv4 addr string* | IP address of the PBX management interface |
 | `-m\|--mode` | *String* | What mode the plugin should run on (i.e. what to check): |
 |   | 'coupler' | Checks the status of couplers in a given crystal number. If you provide a list of coupler types (option `-y`) only those coupler types will be checked. If you provide a coupler number (option `-c`) only that coupler will be checked. The performance data contain status numbers per coupler type (value=couplers of this type that are IN SERVICE;warn=0;crit=0;min=0;max=total couplers of this type) |
 | `-t\|--timeout` | *Integer*| Set plugin timeout in secs (currenly this only affects the telnet timeout, see below |
 | `-v\|--verbose` |  | Print verbose information (currently only one verbose level is implemented) |

#### Timeouts
The telnet timeout is set to 2secs less than the plugin timeout. The default plugin timeout is 15 secs (setting telnet timeout to 13secs).
Note that on some PBXs (with old CPUs) the telnet session might not respond in time even with the default timeout. So you might need to consider increasing the plugin timeout (using the `-t|--timeout` option) to more than 15secs if you get telnet timeouts.

### Example runs

### How to use in Icinga2
1. Create a hosts configuration file (e.g. a `pbx.conf` file inside your icinga2 `conf.d` directory).
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
2. Now create a command (e.g. inside your `commands.conf` file) like this:
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
3. Then create a number of services that use the command on the hosts. In Icinga2 these is much easy to do by using apply rules.
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
   import "uoi-service-long"
 
   check_command = "aloxe"
 
   vars.aloxe_mode = "terminal"
 
   assign where host.address && host.vars.monitorterminals
} 
```

## Note
__Due to lack of available time, I will probably not respond to any requests, while my response to questions and comments will be very limited.__

_I encourage you to improve this plugin to fit your needs and fix any issues/bugs you find_ 
