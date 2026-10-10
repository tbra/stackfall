class_name JoinCode
extends RefCounted
## Join codes for internet play without Steam (Bontago-1pi.164): an IPv4 address and a UDP port
## packed into 48 bits and written as ten base32 characters, "XXXXX-XXXXX".
##
## Alphabet is Crockford's with the look-alikes dropped rather than silently remapped: no I, L,
## O or U, so a typo is an error the player sees, not a wrong host. The 48 bits sit in the low end
## of a 50-bit value, so the first character is 0..7 only; that spare bit pair is the whole
## checksum (a random mistyped first letter is caught about 3 times in 4). IPv6 is out of scope.
## Pure and static: no scene tree, no Net.

const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CODE_CHARS: int = 10
const GROUP_CHARS: int = 5
const BITS_PER_CHAR: int = 5
const DATA_BITS: int = 48
const PORT_BITS: int = 16
const OCTET_BITS: int = 8
const OCTET_COUNT: int = 4
const OCTET_MAX: int = 255
const PORT_MAX: int = 65535
const CHAR_MASK: int = 31
## CIDR blocks a friend on another network can never reach: this-network, RFC 1918, CGNAT, loopback,
## link-local, IETF protocol 192.0.0.0/24, the three documentation nets, benchmarking 198.18.0.0/15.
const _UNREACHABLE: Array[String] = ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24"]
const _ADDRESS_BITS: int = 32
const _MULTICAST_FIRST_MIN: int = 224
const _THIRD_SHIFT: int = 3
const _TYPO_REASON: String = "That join code has a typo; check it and try again."


## "1.2.3.4" + port -> "XXXXX-XXXXX", or "" when the address or port is not valid IPv4/port.
static func encode(address: String, port: int) -> String:
	var octets: Array[int] = parse_ipv4(address)
	if octets.is_empty() or port < 1 or port > PORT_MAX:
		return ""
	var value: int = 0
	for octet: int in octets:
		value = (value << OCTET_BITS) | octet
	value = (value << PORT_BITS) | port
	var chars: String = ""
	for i: int in CODE_CHARS:
		chars = ALPHABET[value & CHAR_MASK] + chars
		value >>= BITS_PER_CHAR
	return chars.substr(0, GROUP_CHARS) + "-" + chars.substr(GROUP_CHARS)


## Text -> {"valid": true, "address": String, "port": int}, or {"valid": false, "reason": String}.
## Case, spaces and dashes are ignored.
static func decode(text: String) -> Dictionary:
	var clean: String = text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if clean.length() != CODE_CHARS:
		return {"valid": false, "reason": "A join code has 10 letters and digits, like 7XK2M-9QD4R."}
	var value: int = 0
	for i: int in CODE_CHARS:
		var index: int = ALPHABET.find(clean[i])
		if index < 0:
			return {"valid": false, "reason": "\"%s\" is not used in join codes (no I, L, O or U)." % clean[i]}
		value = (value << BITS_PER_CHAR) | index
	if value >> DATA_BITS != 0:
		return {"valid": false, "reason": _TYPO_REASON}
	var port: int = value & PORT_MAX
	if port < 1:
		return {"valid": false, "reason": _TYPO_REASON}
	var ip: int = value >> PORT_BITS
	var address: String = "%d.%d.%d.%d" % [
		(ip >> (OCTET_BITS * _THIRD_SHIFT)) & OCTET_MAX, (ip >> (OCTET_BITS * 2)) & OCTET_MAX,
		(ip >> OCTET_BITS) & OCTET_MAX, ip & OCTET_MAX,
	]
	return {"valid": true, "address": address, "port": port}


## True for text that is not an IP address ("1.2.3.4" / "1.2.3.4:5"), so a menu field can route it to decode().
static func looks_like_code(text: String) -> bool:
	var clean: String = text.strip_edges()
	return not clean.is_empty() and not clean.contains(".") and not clean.contains(":")


## Four octets, or [] when `address` is not dotted-quad IPv4.
static func parse_ipv4(address: String) -> Array[int]:
	var result: Array[int] = []
	var parts: PackedStringArray = address.strip_edges().split(".")
	if parts.size() != OCTET_COUNT:
		return result
	for part: String in parts:
		if not part.is_valid_int():
			return [] as Array[int]
		var octet: int = int(part)
		if octet < 0 or octet > OCTET_MAX:
			return [] as Array[int]
		result.append(octet)
	return result


## False for addresses a friend on another network can never reach (private, CGNAT, loopback, reserved...).
static func is_public_ipv4(address: String) -> bool:
	var o: Array[int] = parse_ipv4(address)
	if o.is_empty() or o[0] >= _MULTICAST_FIRST_MIN:
		return false
	var value: int = _to_int(o)
	for cidr: String in _UNREACHABLE:
		var parts: PackedStringArray = cidr.split("/")
		var host_bits: int = _ADDRESS_BITS - int(parts[1])
		if value >> host_bits == _to_int(parse_ipv4(parts[0])) >> host_bits:
			return false
	return true


static func _to_int(octets: Array[int]) -> int:
	var value: int = 0
	for octet: int in octets:
		value = (value << OCTET_BITS) | octet
	return value
