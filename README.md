=============================================================
ThirdSquare - proof-of-concept ticketing system for Australia
=============================================================

(Why, the README alone is worth a thousand pounds a word!)

An entirely open standards ticketing system, aimed primarily at the public
transport system of trains, trams, and buses, and capable of being extended to
other billing systems too. Everything is cryptographically signed using well
known standards.

The system is built on an Australia-wide financial database, hosted centrally,
and individual ticketing systems for each state. Travellers carry smart cards
which are keyed to their accounts; accounts store money, cards do not. Above
all, cards carry no editable information whatsoever - only a reference ID.
(Note that making the cards themselves uncopyable is outside the scope of this
proposal; at worst, it would be equivalent to stealing someone else's card. As
the cards carry no value of their own, cloning your own card would give you no
benefit. An expert on NFC hardware can doubtless advise on this point, and also
on the related point of permitting people to use their mobile phones as
ThirdSquare cards.)

All computers in this operation should have unique and stable IP addresses. In
an ideal world, IPv6 should be used; however, the code does not depend on this.

The financial database is simply a PostgreSQL server. It has no custom software
and no access other than from the states' servers (ergo its HBA config can and
should stipulate that their IPs are the only ones permitted); each state gets a
dedicated database user, and standard security methods will be deployed to
ensure that this server cannot be tampered with. This is all unsurprising to a
PostgreSQL database admin.

Where things get interesting is the per-state servers. These contain a local
PostgreSQL database which records cards and open tickets, and also maintain a
running instance of the server script. The server receives touch-on and -off
requests, and sends back responses saying "OK, no charge", "OK, fare deducted"
(with an amount), or "Denied, insufficient funds". The client (which may be a
single validator, or may be a bank of validators) communicates solely with the
one local server.

A card will most often be used in the state that issued it, but this is not a
requirement. Whenever a card is used for the first time in a new state, it is
verified against an account, and then a new per-state record is created for it;
most likely, the account will then be debited the price of a ticket. This makes
multi-state usage almost transparent - a Melburnian commuter with an active
monthly ticket can travel to Adelaide, the monthly ticket is ignored, and a few
dollars get debited to pay for local travel.

All communication goes through the local server, which is therefore in total
control of the system. It uses a Unix socket to access its local database, a
TCP/IP socket (with SSL) to access the financial database, and UDP (with
cryptographic signatures, but no encryption) to receive and respond to touch
requests. Note that this implies that a MITM could snoop on validations. If
this is deemed to be a problem, the payload can be encrypted using the target
server's public key, at the cost of forcing all packets to carry exactly 512
bytes of data, with a maximum of 245 bytes of true payload.

Cryptography is based around SSH keypairs, which can be generated with the Unix
'ssh-keygen' command; they are kept in their text format for convenience. Every
client will need a keypair, and the server will need a lookup table mapping IP
addresses to public keys; the server also needs a keypair, and the public key
can be embedded into the client software.

The system is built on a concept of touching on and touching off, but it's not
always possible to recognize one from the other, and touches off do not always
happen. When a touch occurs, check to see if it could plausibly be a touch off
for the previous touch-on: same mode of transport, same vehicle (if applicable;
all railway stations on one line are the "same vehicle", and the city loop is
the same vehicle as all other lines), and same day. If so, it's a touch off.

Any time there is a touch on for an already-touched-on card, and any time that
the card is probed and it's been more than a day since the touch on, the server
will register a "presumed touch off". This is done as the "longest logical"
journey from the touch-on point; it might be possible to travel further (esp on
the trains - you could ride in and out all day), but a normal sane traveller
would be unlikely to travel further than this. For buses and trams, this would
be the end of the route; for railway stations... Houston, we have a problem.

To simplify the boundary conditions (particularly with presumed touches off),
timestamps are ignored for touches off. If you board a vehicle at 8:59 when you
have an open ticket until 9:00, you will not be charged for a daily ticket.
The touch off (presumed or explicit) will affect your zone usage, however.

Automated tickets
=================

Prepurchased tickets are always of at least one day duration, and have their
zones listed explicitly. Automatic tickets currently have a maximum duration of
one day (to keep the decision tree bounded - see below), and have a cut-off
timestamp. When you first touch on, the timestamp is set to be two hours away;
round forwards to the next hour, and after 6PM, give until 4AM. If a touch-on
occurs after this time, the ticket is expanded to a daily, flagging it as a
double-price ticket and granting until 4AM.

Zone usage of automated tickets is completely independent of the duration. Each
time a touch (or presumed touch) occurs, the following steps are performed:

1. Look for a prepurchased ticket valid for the current day and having nonzero
   zone intersection with the current location's zones. If there is one, permit
   the touch - done.
2. Look for an existing automated ticket for this card. If there is none, add
   one with zero paid-for zones and a cut-off time as described above. If there
   is one, check if its duration has expired; if so, expand it to daily. NOTE:
   This could add a nasty slab to the price, if the user has previously touched
   on in a large number of zones, and particularly if s/he failed to touch off,
   picking up some very remote touches. The sudden expansion to daily will cost
   roughly as much as all previous touches combined (more if it also adds yet
   another zone to the bill).
3. Add a new entry to the ticket, listing the zones of the current trip.
4. Count the number of zones needed for this ticket. This is the smallest
   number of zones which can, between them, cover every touch done today.
4.1. Take the union of all zones which have been used at all.
4.2. For each zone in the union, remove it from the union, then iterate over
     all touches in the ticket, checking intersection with that touch's zones.
     If any intersection comes up empty, the zone is needed, and must be kept.
     Otherwise, it can be removed.
4.3. For ultimate optimization, perform this search recursively and seek the
     minimum zone count. As an efficiency cheat, assume that any removal is a
     valid removal, but then acknowledge that there MAY be crazy edge cases
     that depend on the order of the checks done. For consistency, always check
     in an obvious order, eg lexicographically by zone identifier.
4.4. The number of zones in the union at the end is the ticket's zone count.
5. If the current zone count exceeds the paid-for zone count, charge for the
   additional zone(s) and reject the touch if the charge is rejected.

These steps are 100% reproducible and deterministic, and can never decrease the
ticket's zone count. They do, however, require examination of *every* touch in
the ticket's period. Handling this for a single day is reasonable (there won't
normally be more than maybe a dozen touches in a typical day), but allowing the
automated tickets to expand to weekly, monthly, or yearly (!!) would be utterly
unworkable; the algorithm as described above scales with the square of touches.
Additionally, while it's reasonable to count a single day's travel as covering
all applicable zones, trying to expand this to multiple days becomes hairier;
if a commuter steps outside his usual route for one day in a month, how should
this be charged? The safest solution is to keep each day's travel separate. For
the regular travellers who wish to save money by using longer-duration tickets,
the overhead of explicitly purchasing them will be easily justified.

Conceptually, your ticket will be touched off automatically when the vehicle
you were on reaches its destination. Practically, however, this happens only on
the next touch or other pinging of the card (eg if you request a balance, the
system MAY at that time bill you for a previous trip). This ensures that your
ticket is still in its "touched on" state any time an AO checks it.

Each touch operation sends two signature values: where the vehicle is now, and
where it will be at end-of-trip. The end marker and vehicle identifier are
stored as the ticket's touched-on status. If the next touch is on the same
vehicle and has the same end-of-trip marker, it is a touch-off; otherwise it is
a touch-on, and an implicit touch-off is performed at the end-of-trip location.
Edge case: As a vehicle approaches the end-of-trip location (usually a route
terminus), it MUST instantly update its end-of-trip to be the *next* end (which
may be the terminus at the far end, a depot, or "NULL" meaning that touches-on
are to be rejected (vehicle not taking passengers)); so long as its location
matches the ticket's EOT marker, it is a touch off.
Additional edge case: Railway stations don't have a concept of vehicles or trip
end locations. Defining the entire rail network as a single vehicle with a
constant end location of FSS gives us a reasonably plausible average, with the
system broadly working (as long as you touch off at any station, it'll be seen
as a touch off), but with the following corner cases:
1. People will think of down journeys as ending at the down terminus, and up
   journeys as ending at the up terminus. This can produce unexpected charges
   when someone boards at Dandenong, hops off at Officer, and expects to be
   auto-touched-off at Pakenham; or boards a Lilygrave shuttle at FTG, gets
   off at Ringwood, and expects to be auto-touched-off there. In both cases,
   the implicit touch off will happen at FSS, which will most likely add an
   additional zone to the charge. Solution: Make sure you always touch off for
   the lowest fare, same as we've always said.
2. Journeys running into the city and out again will be charged for their two
   end points and nothing in between. This makes the rail network into a magic
   orbital route - you can ride from Pakenham to Belgrave and be charged as if
   you quantum-tunneled from one to the other. In this case, though, I expect
   that there will normally be an orbital bus route that does the same job and
   quicker, so this will be significant only in a very VERY few cases, and
   it'll be the slow option anyway. Slightly less bizarre is the through-city
   trip - board at Pakenham, ride all the way in (maybe change trains in the
   Loop, but don't touch off/on), and then all the way out to Broadmeadows.
   Again, your fare will be calculated as if you quantum tunneled from one to
   the other. There's no viable way to recognize the actual trip taken, so we
   grant you a cheaper fare as an apology for the slowness of such travel.
   (Note that the same assumption applies to other trips, too, but the plan is
   for most vehicles to not cross myriad zone boundaries; the 903 needs to be
   reworked to make it marginally sane anyway. In those cases, we could have a
   system of "passed-through zones", but I would much prefer to minimize their
   incidence rather than implement their charges.)
This requires that a vehicle know in advance what its next trip will be, or
else to reject touches-on until it knows that. Is that a problem? TODO: Ask.
Additional corner case: If you ride a vehicle toward one EOT, then get off and
don't touch off, then wait for it to complete *one entire cycle* and return to
you (going in the same direction as when you'd departed), it would be seen as
a touch off; the target and vehicle are the same, so you clearly are touching
off. To prevent this, we could add a fourth value to the touch tuple: a unique
run number, which MUST increment any time the same vehicle makes a run to the
same destination on the same day. (It MAY increment at other times too, but
it MUST NOT ever repeat a (vehicle, date, target) tuple.) But the likelihood
that this would ever actually matter is extremely low, and I'm leaving this as
a "note to self" without any implementation requirement.

Timestamping
============

Date and time: The system is posited on a cycle of days, each with a known
beginning and end. This works very nicely with a system that has a regular
downtime (say, 2AM-4AM); it doesn't hurt if a day contains additional hours
from midnight until some particular cut-off, just as long as it's consistent.
The simplest way to handle this is to have all times handled in UTC, with a
stipulated day-break (no, not the coronet); alternatively, use some civil time
that's consistent across the entire system. (Interstate travel will be an issue
anyway, so this doesn't make it any worse.) Problem: NightRider buses operate a
different day cycle. If they are to be zoned as per the other tickets, they'll
need a hack that puts them on a different day-break. Otherwise, just treat them
the same way that SkyBus and your morning coffee are treated - a simple price
that gets charged to your account, and does not interact in any way with ticket
usage for the rest of the system.
