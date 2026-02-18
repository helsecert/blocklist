import datetime
import json
import logging
import requests
from typing import Literal
from enum import StrEnum


class IndicatorType(StrEnum):
    DOMAIN = "domain"
    WILDCARD_DOMAIN = "wildcard_domain"
    IPV4 = "ipv4"
    IPV4_CIDR = "ipv4_cidr"
    IPV6 = "ipv6"
    IPV6_CIDR = "ipv6_cidr"
    URL = "url"


class ListFormat(StrEnum):
    LIST = "list"
    LIST_CONTEXT = "list_context"
    LIST_CIDR = "list_cidr"
    LIST_CIDR_CONTEXT = "list_cidr_context"
    LIST_REGEX = "list_regex"
    LIST_REGEX_CONTEXT = "list_regex_context"
    PALOALTO = "paloalto"
    SQUID = "squid"


class KillChain(StrEnum):
    DELIVERY = "delivery"
    ACTION = "action"
    C2 = "c2"
    EXPLOITATION = "exploitation"
    UNKNOWN = "unknown"
    RECONNAISSANCE = "reconnaissance"


class Category(StrEnum):
    CEOFRAUD = "ceofraud"
    MALWARE = "malware"
    PHISHING = "phishing"
    SCAN = "scan"
    ATTACK = "attack"
    BRUTEFORCE = "bruteforce"
    SCAM = "scam"
    MINING = "mining"
    WEBSHELL = "webshell"
    UNKNOWN = "unknown"
    DDOS = "ddos"


class Malware(StrEnum):
    BAZAR = "bazar"
    LOKIBOT = "lokibot"
    NANOCORE = "nanocore"
    NJRAT = "njrat"
    VIPERSOFTX = "vipersoftx"
    UNKNOWN = "unknown"
    DARKCOMET = "darkcomet"
    CRYPTOLOCKER = "cryptolocker"
    KWAMPIRS = "kwampirs"
    RETEFE = "retefe"
    DUSTYSKY = "dustysky"
    CERBER = "cerber"
    LOCKY = "locky"
    WANNACRY = "wannacry"
    IRCBOT = "ircbot"
    RACCOON = "raccoon"
    CARBERP = "carberp"
    ASPROX = "asprox"
    REDOSDRU = "redosdru"
    LUMINOSITYLINK = "luminositylink"
    KEYBASE = "keybase"
    SHADOWSCYTHE = "shadowscythe"
    SYSTEMBC = "systembc"
    DIRTJUMPER = "dirtjumper"
    AZORULT = "azorult"
    REMCOSRAT = "remcosrat"
    TR_CRYPT = "tr/crypt"
    CONTI = "conti"
    HUNTER = "hunter"
    SQUIBLYDOO = "squiblydoo"
    GORJOLECHO = "gorjolecho"
    ALPHACRYPT = "alphacrypt"
    SPINDEST = "spindest"
    NETSUPPORTMANAGER = "netsupportmanager"
    CARBANAKVBS = "carbanakvbs"
    PROXYBOT1 = "proxybot1"
    ZEGOST = "zegost"
    BOTLICK = "botlick"
    HERMETICWIPER = "hermeticwiper"
    CARBANAK = "carbanak"
    OPERATIONDUSTSTORM = "operationduststorm"
    OPACHKI = "opachki"
    NUCLEAREK = "nuclearek"
    STOBEROX = "stoberox"
    JJDOOR = "jjdoor"
    OSCELESTIAL = "oscelestial"
    INFOADMIN = "infoadmin"
    TORPIG = "torpig"
    NETWIRE = "netwire"
    CHTHONIC = "chthonic"
    QUASARRAT = "quasarrat"
    NEXUSLOGGER = "nexuslogger"
    TINYLOADER = "tinyloader"
    XMRIG = "xmrig"
    ANDROMEDA = "andromeda"
    CRYPTXXX = "cryptxxx"
    CONFICKER = "conficker"
    CABART = "cabart"
    DRIDEX = "dridex"
    WEEVELY = "weevely"
    POWERDUKE = "powerduke"
    IMMINENT_MONITOR = "imminent monitor"
    SOGU = "sogu"
    HWORM = "hworm"
    ICEDID = "icedid"
    RATTY = "ratty"
    JCFBMAINEXSTEALER = "jcfbmainexstealer"
    CRYPTOWALL = "cryptowall"
    QADARS = "qadars"
    CITADEL = "citadel"
    METERPRETER = "meterpreter"
    BEDEP = "bedep"
    FORTDISCO = "fortdisco"
    RERDOM = "rerdom"
    NYMAIM = "nymaim"
    XXZH = "xxzh"
    AGENTTESLA = "agenttesla"
    KOVTER = "kovter"
    THEM00N = "them00n"
    AUGUSTSTEALER = "auguststealer"
    NOKNOK = "noknok"
    BUMBLEBEE = "bumblebee"
    KINS = "kins"
    JBIFROST = "jbifrost"
    COBALTSTRIKE = "cobaltstrike"
    QRAT = "qrat"
    UPATRE = "upatre"
    N3UTRINO = "n3utrino"
    RISINGSUN = "risingsun"
    DOPPELDRIDEX = "doppeldridex"
    PONY = "pony"
    JSPY = "jspy"
    COREBOT = "corebot"
    RASPBERRYROBIN = "raspberryrobin"
    GALILEO = "galileo"
    CHANITOR = "chanitor"
    NEUTRINO_EK = "neutrino ek"
    ZEUS_ICEIX = "zeus-iceix"
    EMOTET = "emotet"
    TRICKBOT = "trickbot"
    JAVA_DOWNLOADER = "java-downloader"
    KEGOTIP = "kegotip"
    CRYPTOGARBAGE = "cryptogarbage"
    FLAWEDAMMYY = "flawedammyy"
    JSOCKET = "jsocket"
    JACKSBOT = "jacksbot"
    MINEBRIDGE = "minebridge"
    PUSHDO = "pushdo"
    ISRSTEALER = "isrstealer"
    GOZI = "gozi"
    DYREZA = "dyreza"
    KELIHOS = "kelihos"
    QUARTERRIG = "quarterrig"
    DIAMONDFOX = "diamondfox"
    TOFSEE = "tofsee"
    VMZEUS = "vmzeus"
    NECURS = "necurs"
    TROCHILUS = "trochilus"
    FORMBOOK = "formbook"
    TORRENTLOCKER = "torrentlocker"
    BUGAT = "bugat"
    TINBA = "tinba"
    ZEROACCESS = "zeroaccess"
    QEALLER = "qealler"
    ZEUS = "zeus"
    GAMEOVERZEUS = "gameoverzeus"
    RYUK = "ryuk"
    SMOKELOADER = "smokeloader"
    LOKI = "loki"
    JRAT = "jrat"
    METALJACK = "metaljack"
    REVIL = "revil"
    DREAMBOT = "dreambot"
    VJWORM = "vjw0rm"
    QAKBOT = "qakbot"


class BlockListItem:
    def __init__(self, value: str, context: str | None = None):
        self.value = value
        if context:
            self.tags = []
            self.full_context = context
            self._parse_context(context)

    def _parse_context(self, context: str):
        try:
            parts = context.split(" ")
            self.date_added = datetime.datetime.fromisoformat(parts[0])
            for p in parts[1:]:
                self.tags.append(p)
                if ":" in p:
                    key, val = p.split(":")
                    setattr(self, key, val)

        except Exception as e:
            logging.error(f"Failed to parse context {context}: {e}")

    def to_json(self):
        self_dict = self.__dict__.copy()
        self_dict["date_added"] = self_dict["date_added"].isoformat() if "date_added" in self_dict else None
        return json.dumps(self_dict)


class BlocklistClient:
    """Client for interacting with the Helsecert Blocklist API.

    :param api_key: API key received from Helsecert
    :param api_url: Base URL for the Helsecert Blocklist API

    :type api_key: str
    :type api_url: str
    """

    def __init__(
        self, api_key: str, api_url: str = "https://blocklist.helsecert.no/v3"
    ):
        """Initialize the BlocklistClient with the provided API key and optional URL."""
        if not api_key:
            raise ValueError("API key must be provided")

        self.api_key = api_key
        self.api_url = api_url

    def get_blocklist(
        self,
        type: IndicatorType | list[IndicatorType] = IndicatorType.DOMAIN,
        format: ListFormat = ListFormat.LIST_CONTEXT,
        hash: bool = False,
        list_name: Literal["default", "auth"] | None = None,
        confidence: Literal["low", "medium", "high"] | None = None,
        impact: Literal["low", "medium", "high"] | None = None,
        fp_rate: Literal["none", "low", "medium", "high"] | None = None,
        kill_chain: KillChain | str | None = None,
        category: Category | str | None = None,
        malware_family: Malware | str | None = None,
        limit: int | None = None,
    ) -> list[BlockListItem]:
        """Retrieve a filtered blocklist from the API with optional formatting and metadata filtering.
        This method constructs a query to the API endpoint and parses the response into
        BlockListItem objects. Each item may contain a value and optional context information.
        Args:
            type: The indicator type(s) to include in the blocklist. Can be a single type or
                a list of types (e.g., DOMAIN, IPV4). Defaults to DOMAIN.
            format: The output format for each list item (e.g., plain text, regex).
                Defaults to LIST_CONTEXT.
            hash: If True, include a checksum of the blocklist content. Defaults to False.
            list_name: Which blocklist to fetch from ('default' or 'auth'). Defaults to the
                server's default list if not specified.
            confidence: Filter by confidence level ('low', 'medium', 'high'). Optional.
            impact: Filter by impact level ('low', 'medium', 'high'). Optional.
            fp_rate: Filter by false positive rate ('none', 'low', 'medium', 'high'). Optional.
            kill_chain: Filter by Cyber Kill Chain phase. Optional.
            category: Filter by malicious activity category. Optional.
            malware_family: Filter by malware family. Optional.
            limit: Maximum number of signatures to return. Oldest signatures are omitted
                if the limit is exceeded. Defaults to unlimited if not specified.
        Returns:
            list[BlockListItem]: A list of parsed blocklist items. Each item contains a value
                and optional context information extracted from the API response.
        Raises:
            Exception: If the API request fails (status code != 200), containing the status
                code and response text.
        Examples:
            >>> blocklist = client.get_blocklist(type=IndicatorType.IPV4, limit=100)
            >>> blocklist = client.get_blocklist(type=[IndicatorType.DOMAIN, IndicatorType.IPV4])

        :param format: This specifies the format of each list item, e.g. plain text or a regex.
        :param type: The type of the items included in the list, e.g. domain, ipv4 address.
        :param list_name: This specifies which list to fetch signatures from. Defaults to the default list.
        :param hash: This returns a checksum of the blocklist content.
        :param limit: Max number of signatures, where the oldest signatures are omitted. Optional, defaults to unlimited.
        :param confidence: The level of confidence attached to a signature.
        :param impact: The level of impact attached to a signature.
        :param fp_rate: The rate of false positive incidents a signature produces.
        :param kill_chain: The phase of the Cyber Kill Chain a signature is a part of.
        :param category: The category of malicious activity the signature is a part of.
        :param malware_family: The malware family the signature belongs to.

        :type format: ListFormat
        :type type: IndicatorType | list[IndicatorType]
        :type list_name: ListName | None
        :type hash: HashType | None
        :type confidence: Confidence | None
        :type impact: Impact | None
        :type fp_rate: FPRate | None
        :type kill_chain: KillChain | None
        :type category: Category | None
        :type malware_family: Malware | None
        :type limit: int | None
        """

        url = self.api_url + "?apikey=" + self.api_key
        url += f"&format={format}"
        if isinstance(type, list):
            for t in type:
                url += f"&type={t}"
        else:
            url += f"&type={type}"
        if list_name:
            url += f"&list_name={list_name}"
        if hash:
            url += f"&hash={hash}"
        if confidence:
            url += f"&confidence={confidence}"
        if impact:
            url += f"&impact={impact}"
        if fp_rate:
            url += f"&fp_rate={fp_rate}"
        if kill_chain:
            url += f"&kill_chain={kill_chain}"
        if category:
            url += f"&category={category}"
        if malware_family:
            url += f"&malware_family={malware_family}"
        if limit:
            url += f"&limit={limit}"

        response = requests.get(url)
        if response.status_code != 200:
            raise Exception(
                f"Failed to fetch blocklist: {response.status_code} - {response.text}"
            )

        raw_blocklist = [line for line in response.iter_lines()]

        parsed_blocklist = []
        for entry in raw_blocklist:
            parts = entry.decode().split("#")
            if len(parts) == 2:
                value, context = (p.strip() for p in parts)
                parsed_blocklist.append(BlockListItem(value=value, context=context))
            else:
                parsed_blocklist.append(BlockListItem(value=parts[0].strip()))

        return parsed_blocklist

    def get_all_blocklists(self, *args, **kwargs) -> list[BlockListItem]:
        return_list = []
        for indicator_type in IndicatorType:
            blocklist = self.get_blocklist(type=indicator_type, *args, **kwargs)
            for entry in blocklist:
                return_list.append(entry)

        return return_list
