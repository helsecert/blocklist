# Oppskrift på hvordan man kan hente ned IOC-er til Splunk Enterprise Security for automatisk IOC matching

[Splunk Enterprise Security](https://www.splunk.com/en_us/products/enterprise-security.html) er en SIEM som leveres som et premium-produkt på toppen av Splunk-plattformen.

Enterprise Security har støtte for å importere threat feeds direkte. Når Threat Feed er importert inn i Splunk og det skjer et indikatortreff vil det skapes en Finding (alarm) med tittel *Threat Activity Detected*.  

Automatisk Threat Matching skjer på nye data som går inn i Splunk, og krever at data som skal matches er normalisert iht. [Common Information Model](https://docs.splunk.com/Documentation/CIM/latest/User/Overview)

[Oversikt over støttede Threat Feeds i ES](https://help.splunk.com/en/splunk-enterprise-security-8/administer/8.0/threat-intelligence/overview-of-threat-intelligence-in-splunk-enterprise-security)

### Konfigurasjon
Vi følger [dokumentasjonen](https://help.splunk.com/en/splunk-enterprise-security-8/administer/8.0/threat-intelligence/add-new-threat-intelligence-sources-in-splunk-enterprise-security) til punkt og prikke:

Naviger til *Enterprise Security-appen*, trykk *Configure* -> *Threat Intelligence* -> *Threat Intelligence Sources* -> *New* -> *Line Oriented*
<img width="1689" alt="image" src="/splunk-enterprise-security/1.png" />

Eksempel:  
<img width="675" alt="image" src="/splunk-enterprise-security/2.png" />

*Name*, *Description*, *Interval*, *Max age* og *Max size* er veiledende og kan endres ved behov.

#### Domain (Verbatim)
<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_domain</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_domain</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=domain</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>domain:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>

#### Domain (Wildcard)
<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_domain_wildcard</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_domain</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=wildcard_domain</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>domain:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>

#### IPv4

<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_ipv4</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_ip</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=ipv4</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>ip:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>

#### IPv6

<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_ipv6</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_ip</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=ipv6</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>ip:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>

#### IPv4 CIDR

<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_ipv4_cidr</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_ip</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=ipv4_cidr</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>ip:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>

#### IPv6 CIDR

<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_ipv6_cidr</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_ip</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=ipv6_cidr</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>ip:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>

#### URL

<table>
  <caption>General</caption>
  <tr>
    <th>Name</th>
    <td>helsecert_url</td>
  </tr>
  <tr>
    <th>Description</th>
    <td>HelseCERT and KommuneCERT blocklists</td>
  </tr>
  <tr>
    <th>Type</th>
    <td>threatlist_url</td>
  </tr>
  <tr>
    <th>Url</th>
    <td>https://blocklist.helsecert.no/v3?apikey=YOURAPIKEYHERE&format=list&type=url</td>
  </tr>
  <tr>
    <th>Weight</th>
    <td>60</td>
  </tr>
  <tr>
    <th>Interval</th>
    <td>43200</td>
  </tr>
  <tr>
    <th>Max age</th>
    <td>-30d</td>
  </tr>
  <tr>
    <th>Max size</th>
    <td>52428800</td>
  </tr>
  <tr>
    <th>Archive Member</th>
    <td></td>
  </tr>
  <tr>
    <th>POST arguments</th>
    <td></td>
  </tr>
  <tr>
    <th>Threat Intelligence</th>
    <td>TRUE</td>
  </tr>
</table>
<table>
  <caption>Parsing</caption>
  <tr>
    <th>File Parser</th>
    <td>line</td>
  </tr>
  <tr>
    <th>Delimiting regular expression</th>
    <td>,</td>
  </tr>
  <tr>
    <th>Extracting regular expression</th>
    <td></td>
  </tr>
  <tr>
    <th>Ignoring regular expression</th>
    <td>(^#|^\s*$)</td>
  </tr>
  <tr>
    <th>Fields</th>
    <td>url:$1,description:HelseCERT</td>
  </tr>
  <tr>
    <th>Skip header lines</th>
    <td>0</td>
  </tr>
</table>


## Avslutningsvis

Enterprise Security støtter også Threat Matching på *Sertifikater*, *User Agents*, *Prosess* osv som beskrevet [her](https://help.splunk.com/en/splunk-enterprise-security-8/administer/8.0/threat-intelligence/supported-types-of-threat-intelligence-in-splunk-enterprise-security)

For å gjøre automatisk retrospektiv matching finnes det en Splunk app for dette også. Kontakt [mbjerkel@cisco.com](mailto:email@domain.com) for å få tilgang på denne.
