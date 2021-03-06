# ASM2ATC

# Description
Create nodes for ASM monitors in DX APM Team Center which can be used in DX OI Services as well.

## Short Description
Create nodes for ASM monitors in DX APM Team Center which can be used in DX OI Services as well.

## APM version
DX APM SaaS 20.9.0.13, Nov 10, 2020

## Supported third party versions
CA App Synthetic Monitor API 10.5.0.5/10.5.1

## Limitations
The shell script needs to run at least once every 24 hours. Otherwise the nodes will expire. Therefore, we recommend to configure to run it periodicially via `crontab`.

## License
[Eclipse Public License - v 1.0](LICENSE)

# Installation Instructions

## Installation
Unpack the release archive ideally to the same server where your ASM-APM integration is running, e.g. to `/opt/asm2atc`.
We want to run this script every 8 hours and add this line to the system's `/etc/crontab`. Run `crontab -e` as root user, and you're editing it for root straight.

```
10 */8  * * *   /opt/asm2atc/asm2atc.sh
```
(Don't forget a final newline which is needed by crontab.)

## Configuration
You need to gather the following information from your ASM and APM accounts and edit `asm2atc.cfg` accordingly:
* `APM_URL`: This is the URL that you see in the browser address tab once you go to Experience view or Map on APM SaaS or APM 20.x on premise. Include the tenant ID (i.e. the number) that is shown after the hostname but in front of `/apm/atc`. r.g. `APM_URL=https://apmgw.dxi-na1.saas.broadcom.com/nnn`
* `APM_API_TOKEN`: In the APM section of DXI open *Settings/Security* from the navigation panel on the left and click the *Generate New Token* button, select *Public API Token* and copy the values.
* `APM_AGENT_NAME`: Please insert the agent name of your ASM-APM integration via APM Infrastructure Agent exactly as reported in the APM metric view, e.g. `APM_AGENT_NAME=myhostname|ASM|App Synthetic Monitor Agent`. If the agent name is not matched metrics and alarms in DX APM and DX OI won't work .
* `ASM_USER_EMAIL`: use the email address of your ASM account, e.g. `ASM_USER_EMAIL=john.doe@broadcom.com`
* `ASM_API_PASSWORD`: use the ASM API password for that account.


# Usage Instructions
You can run `./asm2atc.sh` manually for testing. If you configured cron as outlined above the script will run every 8 hours.

## ATC description
The script will query all ASM monitors from your account and create a vertex/node for every monitor in the Application layer of APM Team Center (ATC).
Each vertex will have the following properties:
* `id`: `ASM:$folder:$monitor`
* `name`: `$folder|$monitor`
* `type`: `Synthetic Transaction`
* `agent`: `$APM_AGENT_NAME`
* `monitor`: `$monitor`
* `folder`: `$folder`
* `active`: y or n
* `interval`: e.g. 00:05:00 for every 5 minutes
* `monitor_type`: e.g. http, dns, script, script_firefox, browser
* `host`: the host that the monitor is calling
* `ASM link`: a link to the logs of that monitor, requires ASM login

The following metrics are mapped to the `Synthetic Monitor` vertex:
* Uptime (%)
* Last Check Status
* Errors Per Interval
* Total Time (ms)
* Connect Time (ms)
* Download Time (ms)
* Processing Time (ms)

In addition, the script will look for existing `BUSINESSTRANSACTION` nodes in the ATC map and connect the corresponding `Synthetic Monitor` vertex to it if:
 * `BUSINESSTRANSACTION.Business Service == Synthetic Monitor.folder`
 * `BUSINESSTRANSACTION.Name` =~ `Synthetic Monitor.monitor` \*via ASM\*, i.e. the name must start with the monitor name and also contain "via ASM".

E.g. the `BUSINESSTRANSACTION` vertex with `Business Service` attribute *Ticketing* and `name` *TixChange Step 13 via ASM 10* will match a `Synthetic Monitor` vertex with `folder` *Ticketing* and `monitor` *TixChange*.

### End User Experience Monitoring (EUM)
In order to get `BUSINESSTRANSACTION` vertices created by APM from the transactions coming for ASM you have to add additional headers to your monitor configuration in ASM. DX App Experience Analytics (AXA) or DX APM Browser Agent send those headers automatically.

In the `Advanced` section of your ASM monitor configuration under `Transaction Tag Header` select the option `Mobile Apps Analytics monitors` and set the headers accordingly. See [End User Experience Monitoring](https://techdocs.broadcom.com/us/en/ca-enterprise-software/it-operations-management/dx-apm-saas/SaaS/implementing-agents/extend-data-monitoring/end-user-endpoints-monitoring.html) in the APM documentation for more information. E.g.:

![Transaction Tag Header configuration](images/monitor_configuration.png)

Use the folder name e.g. `Ticketing` as Business Service name (`bs=Ticketing`) and the monitor name e.g. `TixChange` as business transaction name `bt=TixChange` and set platform `p=ASM` in the Transaction Tag Header configuration of you monitor. `bt=TixChange Step {step_number}` matches as well as we compare to `$monitor* via ASM*` in `asm2arc.sh`. The appendix `via ASM` is automatically appended by APM just like `via iOS` or `via Chrome`. If your monitor is not in a folder but at the top level use `bs=ROOT_FOLDER`. Currently `{step_number}` is not substituted for Webdriver monitors, only for jmeter scripts.

That configuration will create this node in APM:
![ATC Map](images/atc.png)

The nodes in the left column are the `Synthetic Transactions` created by `asm2atc`. In the center are the `Business Transactions` created by APM from the EUE headers in the http requests from either ASM, browser agent or mobile app. And further to the right (hidden by the panel) are the `Generic Frontends, Servlets, ???` nodes created by DX APM from the java application.

## Custom Management Modules
A Management Module is not included but all alerts that are defined for the monitors will be mapped to the corresponding vertex. This can be used for alerting via any channels provided in DX OI.


## Debugging and Troubleshooting
Enable additional printf commands in `asm2atc.sh` to get debugging output.


## Support
This document and associated tools are made available from CA Technologies as examples and provided at no charge as a courtesy to the CA APM Community at large. This resource may require modification for use in your environment. However, please note that this resource is not supported by CA Technologies, and inclusion in this site should not be construed to be an endorsement or recommendation by CA Technologies. These utilities are not covered by the CA Technologies software license agreement and there is no explicit or implied warranty from CA Technologies. They can be used and distributed freely amongst the CA APM Community, but not sold. As such, they are unsupported software, provided as is without warranty of any kind, express or implied, including but not limited to warranties of merchantability and fitness for a particular purpose. CA Technologies does not warrant that this resource will meet your requirements or that the operation of the resource will be uninterrupted or error free or that any defects will be corrected. The use of this resource implies that you understand and agree to the terms listed herein.

Although these utilities are unsupported, please let us know if you have any problems or questions by adding a comment to the CA APM Community Site area where the resource is located, so that the Author(s) may attempt to address the issue or question.

Unless explicitly stated otherwise this extension is only supported on the same platforms as the APM core agent. See [APM Compatibility Guide](https://techdocs.broadcom.com/us/product-content/status/compatibility-matrix/application-performance-management-compatibility-guide.html).

### Support URL
https://github.com/CA-APM/ca-apm-asm2atc

# Contributing
The [CA APM Community](https://communities.ca.com/community/ca-apm) is the primary means of interfacing with other users and with the CA APM product team.  The [developer subcommunity](https://communities.ca.com/community/ca-apm/ca-developer-apm) is where you can learn more about building APM-based assets, find code examples, and ask questions of other developers and the CA APM product team.

If you wish to contribute to this or any other project, please refer to [easy instructions](https://communities.ca.com/docs/DOC-231150910) available on the CA APM Developer Community.

## Categories
Integration


# Change log
Changes for each version of the extension.

Version | Author | Comment
--------|--------|--------
1.0 | Broadcom Inc. | First version of the extension.
1.0 | Broadcom Inc. | Fixes and create edge to Business Transaction vertex
