import os
import sys
import logging
import requests
import json
import uuid
import stix2
from azure.identity import EnvironmentCredential, AzureCliCredential
from .hkcblocklist import IndicatorType, BlocklistClient


# Constants
API_VERSION = "2024-02-01-preview"
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
STIX_NAMESPACE = uuid.UUID("00abedb4-aa42-466c-9c01-fed23315a9b7")

WORKSPACE_ID = os.getenv("WORKSPACE_ID")
if not WORKSPACE_ID:
    raise ValueError("WORKSPACE_ID environment variable is not set.")

SUBSCRIPTION_ID = os.getenv("SUBSCRIPTION_ID", "")
if not SUBSCRIPTION_ID:
    raise ValueError("SUBSCRIPTION_ID environment variable is not set.")

BLOCKLIST_API_KEY = os.getenv("BLOCKLIST_API_KEY", "")
if not BLOCKLIST_API_KEY:
    raise ValueError("BLOCKLIST_API_KEY environment variable is not set.")

# Initialize logging
logging.basicConfig(
    level=LOG_LEVEL, format="[%(levelname)s] %(asctime)s - %(message)s"
)

# Reduce noise from azure module
identity_logger = logging.getLogger("azure")
identity_logger.setLevel(logging.WARNING)

# The indicator types we want to fetch
INDICATOR_TYPES = [
    IndicatorType.IPV4,
    IndicatorType.IPV6,
    IndicatorType.DOMAIN,
    IndicatorType.URL,
]

BLOCKLIST_TYPES_TO_STIX = {
    IndicatorType.IPV4: "ipv4-addr",
    IndicatorType.IPV6:"ipv6-addr",
    IndicatorType.DOMAIN: "domain-name",
    IndicatorType.URL: "url",
}

BLOCKLIST_CONFIDENCE_TO_STIX = {
    "none": 100,
    "low": 90,
    "medium": 50,
    "high": 10,
}


def main():
    # Authenticate using EnvironmentCredentials if available
    logging.debug("Attempting to acquire Sentinel API token using EnvironmentCredential...")
    credential = EnvironmentCredential()
    if credential._credential:
        sentinel_token = credential.get_token("https://management.azure.com/.default")
    else:
        # Attempt AzureCLI credential as fallback
        logging.debug("No valid Azure credentials found in environment variables.")
        logging.debug("Attempting to acquire Sentinel API token using AzureCliCredential...")
        credential = AzureCliCredential()
        sentinel_token = credential.get_token("https://management.azure.com/.default")
    
    if not sentinel_token:
        logging.error("Failed to acquire Sentinel API token. Check your Azure credentials.")
        return
    
    # Initialize Sentinel Threat Intelligence Upload API
    sentinel_endpoint = "https://api.ti.sentinel.azure.com/workspaces/{}/threat-intelligence-stix-objects:upload?api-version={}".format(WORKSPACE_ID, API_VERSION)
    sentinel_session = requests.session()
    sentinel_session.headers = {
        "Authorization": f"Bearer {sentinel_token.token}",
        "Content-Type": "application/json" 
    }

    # Initialize HelseCERT API Client
    client = BlocklistClient(BLOCKLIST_API_KEY)

    # Iterate our selected indicator types
    for attribute_type in INDICATOR_TYPES:
        logging.info(f"Fetching blocklist for {attribute_type.name}...")
        indicators = client.get_blocklist(type=attribute_type)
        logging.info(f"Fetched {len(indicators)} indicators for {attribute_type.name}")

        # Iterate indicators in batches of 100 to avoid hitting Sentinel API limits
        for batch_index in range(0, len(indicators), 100):
            upload_indicators = []
            for indicator in indicators[batch_index:batch_index+100]:
                confidence = BLOCKLIST_CONFIDENCE_TO_STIX[indicator.fp_rate] # type: ignore
                stix_indicator = stix2.Indicator(
                    created=indicator.date_added,
                    name=f"HelseCERT Blocklist indicator",
                    confidence=confidence,
                    description=indicator.full_context,
                    pattern_type="stix",
                    pattern=f"[{BLOCKLIST_TYPES_TO_STIX[attribute_type]}:value = '{indicator.value}']",
                    valid_from=indicator.date_added,
                    labels=indicator.tags,
                    kill_chain_phases=[{"kill_chain_name":"lockheed-martin-cyber-kill-chain","phase_name":indicator.kill_chain}] # type: ignore
                )
                upload_indicators.append(json.loads(stix_indicator.serialize()))

            upload_object = {
                "sourcesystem": "HelseCERT Blocklist",
                "stixobjects": upload_indicators
            }
            
            # Post indicators to Sentinel
            logging.debug(f"Posting {attribute_type} indicators to Sentinel {batch_index}/{len(indicators)}")
            response = sentinel_session.post(sentinel_endpoint, json=upload_object)
            if response.status_code != 200:
                logging.error(f"Sentinel returned error: {response.status_code} - {response.reason}")
                try:
                    error_details = response.json().get("error", {})
                    logging.error(f"Code: {error_details.get("code")}")
                    logging.error(f"Message: {error_details.get("message")}")
                except Exception as e:
                    logging.error(f"Failed to parse error details: {response.text}")
                finally:
                    sys.exit(1)


if __name__ == "__main__":
    main()
