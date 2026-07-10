#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# CruiseConnect Cross-Guardian — jeder Mini-PC bewacht den ANDEREN.
#
# Läuft als Container (python:3.12-alpine, --net=host --restart=always) auf beiden
# PCs. Prüft periodisch, ob der Peer-PC überhaupt lebt (TCP-Connect auf dessen
# SSH-Port über die LAN-IP). Ist der Peer über mehrere Minuten tot (Strom weg,
# Total-Hang der zu einem Reboot führte der am POST hängt, o.ä.), schickt dieser
# PC ein Wake-on-LAN-Magic-Packet an die MAC des Peers.
#
# So deckt das Paar den Fall ab, den ein PC allein nicht kann: „der ganze PC ist
# aus / kommt nicht mehr hoch". Solange EINER lebt, weckt er den anderen.
# WoL an einen bereits laufenden PC ist ein No-Op -> unschädlich.
#
# Args: PEER_LAN  PEER_MAC  BCAST  [PEER_PORT=22]  [THRESH_CYCLES=15]
# Braucht KEIN root (nur --net=host für den LAN-Broadcast).
# ─────────────────────────────────────────────────────────────────────────────
import socket, sys, time, datetime

PEER_LAN = sys.argv[1]
PEER_MAC = sys.argv[2]
BCAST    = sys.argv[3]
PEER_PORT = int(sys.argv[4]) if len(sys.argv) > 4 else 22
THRESH    = int(sys.argv[5]) if len(sys.argv) > 5 else 15   # ×20s = 5 min
INTERVAL  = 20

def log(m):
    print(datetime.datetime.now(datetime.timezone.utc).isoformat() + " [cross-guardian] " + m, flush=True)

def peer_alive():
    try:
        with socket.create_connection((PEER_LAN, PEER_PORT), timeout=5):
            return True
    except OSError:
        return False

def send_wol():
    mac = PEER_MAC.replace(":", "").replace("-", "")
    if len(mac) != 12:
        log("BAD MAC '%s' — WoL skipped" % PEER_MAC)
        return
    packet = b"\xff" * 6 + bytes.fromhex(mac) * 16
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    for target in (BCAST, "255.255.255.255"):
        for port in (9, 7):
            try:
                s.sendto(packet, (target, port))
            except OSError as e:
                log("send err %s:%d %s" % (target, port, e))
    s.close()
    log("WoL magic packet sent to %s via %s" % (PEER_MAC, BCAST))

log("start peer=%s:%d mac=%s bcast=%s thresh=%d(×%ds)" % (PEER_LAN, PEER_PORT, PEER_MAC, BCAST, THRESH, INTERVAL))
down = 0
while True:
    if peer_alive():
        if down:
            log("peer reachable again (after %d fail cycles)" % down)
        down = 0
    else:
        down += 1
        log("peer %s:%d unreachable %d/%d" % (PEER_LAN, PEER_PORT, down, THRESH))
        if down >= THRESH:
            send_wol()
            down = 0
            time.sleep(120)   # dem Peer Zeit zum Booten geben
    time.sleep(INTERVAL)
