class_name NetIds
extends RefCounted
## Wire/handshake identifiers shared by the net layer. Kept out of autoload/Net.gd
## so net/LanDiscovery.gd and net/SteamClient.gd do not name the Net autoload;
## Net keeps `const X: T = NetIds.X` aliases.

## Key the LAN advert carries so a stray UDP broadcast on 47777 is ignored.
const DISCOVERY_MAGIC: StringName = &"stackfall"

## Steam's public test app ("Spacewar"), passed directly into
## Steam.steamInitEx() (no steam_appid.txt is needed once the app id is passed as an argument).
const STEAM_APP_ID_EXPECTED: int = 480
