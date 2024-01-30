import json
import logging
import os
import sqlite3

from logging.handlers import RotatingFileHandler
from dotenv import load_dotenv
from web3 import Web3

ETSM_ADDRESS = '0x0cD11e63b4AC7f8f0bD1F658e1Be1BfeAd8eEd02'
PROJECT_URL = "<SPECIAL_MEMBERSHIP_SITE>"
COMMUNITY_URL = "https://www.reddit.com/r/EthTrader"


def create_nft_meta(tokenId, expiration):
    nft_meta = {
        "name": f"EthTrader Special Membership (Standard) #{tokenId}",
        "description": f"r/EthTrader Special Membership (Standard)\n\n"
                       f"By minting an nft in this series, you can help support the EthTrader project. It also grants you special features in Reddit and roles in Discord."
                       f"Please be sure to check the expiration date before purchasing!\n\n"
                       f"To verify the expiration date on this NFT, refresh this metadata or visit {PROJECT_URL}.\n\n"
                       f"Visit our community at {COMMUNITY_URL}",
        "image": "ipfs://bafkreieiqwfgsm4kltmarjywmbo42m6gvzocdijqsb6b2rqsjazli36iki",
        "attributes": [
            {
                "display_type": "date",
                "trait_type": "Expiration",
                "value": expiration
            }
        ]
    }

    meta_file_location = f"meta/{tokenId}.json"

    if os.path.exists(meta_file_location):
        os.remove(meta_file_location)

    with open(meta_file_location, 'w') as j:
        json.dump(nft_meta, j, indent=4)


if __name__ == '__main__':
    # load environment variables
    load_dotenv()

    # remove old curl command file
    curl_commands = "#!/bin/bash\n\n"
    curl_file_location = f"curl/opensea.sh"

    if os.path.exists(curl_file_location):
        os.remove(curl_file_location)

    # set up logging
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    logger = logging.getLogger("etsm")
    logger.setLevel(logging.INFO)

    base_dir = os.path.dirname(os.path.abspath(__file__))
    log_path = os.path.join(base_dir, "logs/etsm.log")
    handler = RotatingFileHandler(os.path.normpath(log_path), maxBytes=2500000, backupCount=4)
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    # setup db
    with sqlite3.connect("etsm.db") as db:
        sql_create = """
            CREATE TABLE IF NOT EXISTS
                `rundata` (
                `id` integer not null primary key autoincrement,
                `event` NVARCHAR2 not null collate NOCASE,
                `latest_block` BIGINT not null default 0,
                `created_at` datetime not null default CURRENT_TIMESTAMP
              );
        """

        db.row_factory = lambda c, r: dict(zip([col[0] for col in c.description], r))
        cur = db.cursor()
        cur.executescript(sql_create)

        sql_latest_block = """
            select max(latest_block) latest_block 
            from rundata
            where event == 'UpdateMeta';
        """

        cur.execute(sql_latest_block)
        latest_block = cur.fetchone()['latest_block']

    if not latest_block:
        latest_block = 0

    w3 = Web3(Web3.HTTPProvider(os.getenv('ARB1_SEPOLIA_INFURA_IO')))
    if not w3.is_connected():
        exit(4)

    with open(os.path.normpath("abi/etsm.json"), 'r') as f:
        etsm_abi = json.load(f)

    etsm_contract = w3.eth.contract(address=Web3.to_checksum_address(ETSM_ADDRESS), abi=etsm_abi)

    max_block = latest_block
    events = etsm_contract.events.UpdateMeta().get_logs(fromBlock=latest_block + 1)
    for event in events:
        create_nft_meta(event.args.tokenId, event.args.expirationDate)
        curl_commands += f"echo update token: {event.args.tokenId};\n"
        curl_commands += f'curl --request POST --header "X-API-KEY: {os.getenv("OPENSEA_API")}" --url https://api.opensea.io/api/v2/chain/arbitrum_sepolia/contract/{ETSM_ADDRESS}/nfts/{event.args.tokenId}/refresh\n\n'

    with sqlite3.connect("etsm.db") as db:
        sql_insert = """
            INSERT INTO rundata (event, latest_block)
            VALUES ('UpdateMeta', ?);
        """

        db.row_factory = lambda c, r: dict(zip([col[0] for col in c.description], r))
        cur = db.cursor()
        cur.execute(sql_insert, [max_block])

    with open(curl_file_location, 'w') as curl:
        curl.write(curl_commands)