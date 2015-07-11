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

All computers in this operation SHOULD have unique and stable IP addresses. In
an ideal world, IPv6 should be used; however, the code does not depend on this.

(The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in RFC 2119.)

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
    1. Take the union of all zones which have been used at all.
    2. For each zone in the union, remove it from the union, then iterate over
       all touches in the ticket, checking intersection with that touch's zones.
       If any intersection comes up empty, the zone is needed, and must be kept.
       Otherwise, it can be removed.
    3. For ultimate optimization, perform this search recursively and seek the
       minimum zone count. As an efficiency cheat, assume that any removal is a
       valid removal, but then acknowledge that there MAY be crazy edge cases
       that depend on the order of the checks done. For consistency, always
       check in an obvious order, eg lexicographically by zone identifier.
    4. The number of zones in the union at the end is the ticket's zone count.
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

Touch-Off Detection
===================

Conceptually, your ticket will be touched off automatically when the vehicle
you were on reaches its destination. Practically, however, this happens only on
the next touch or other pinging of the card (eg if you request a balance, the
system MAY at that time bill you for a previous trip). This ensures that your
ticket is still in its "touched on" state any time an AO checks it.

Each touch operation sends three signature values: where the vehicle is now,
where it will be at end-of-trip, and its run number. These three integers are
stored as the ticket's touched-on status. If the next touch is on the same
vehicle and has the same run number, it is a touch-off; otherwise it is deemed
a touch-on, and an implicit touch-off is performed at the end-of-trip location.
Edge case: As a vehicle approaches the end-of-trip location (usually a route
terminus), it MUST instantly update its end-of-trip and run number to be the
*next* end and run (which may be the terminus at the far end, a depot, or
0 meaning that touches-on are to be rejected (vehicle not taking passengers));
until it departs that location, all touches MUST be sent with an additional
"matching run number", the previous run identifier. A touched-on ticket that
used the previous run number is counted as a touch off.
Additional edge case: Railway stations don't have a concept of vehicles or trip
end locations. All stations are therefore given a common end location, and the
back-end knows the ID of this location, and will ignore the vehicle IP for the
purposes of touch-off recognition. (The IP is still used for public key lookup,
but if both touches use the same end location, it is a touch-off.) In order to
make this make sense, travellers will be told that they MUST touch off when
using the trains, else they will be charged an automatic fine (which would be
set to exceed the normal travel cost of any regular train trip). This fine can
be charged by simply making the end location a premium location, incurring an
immediate debit whenever it is auto-touched. To make this less disconcerting
for passengers, as many railway stations as possible should be equipped with
barriers, as anyone who physically jumps over barriers is generally going to be
aware that s/he is fare evading; where this is impractical, signage has to
suffice, and as we all know, signage is seldom noticed.
(Parenthesis: Train journeys can easily cross many zones, especially since
changing services at Flinner doesn't involve any touches. This makes a problem
for point-to-point fare calculation. See below.)
(Parenthesis: Train journeys can easily consume many hours, especially since
changing services doesn't involve any touches. This makes a problem for the
policy that touches-off do not affect ticket duration. This may need to be
special-cased; railway station touches may always affect duration. Don't like.)

This requires that a vehicle know in advance what its next trip will be, or
else to reject touches-on until it knows that. Is that a problem? TODO: Ask.
Vehicles must also have run numbers, which are never reused; XKCD 1340 style
recommended, but not enforced. Since run numbers are per-vehicle (with the
exception of railway stations, which don't use them at all), it doesn't hurt
if there are collisions across vehicle types (eg if tram run numbers use a
different scheme from the one bus run numbers use), as long as the tuple of
(vehicle, run) is used once only. Once that vehicle begins a new run, it MUST
NOT re-enter the previous run.

Note that if multiple service modes (eg metro trams and trains) have validators
on platforms, they can work the same way, but with different targets (probably
the same premium fare, but separate to detect failure to touch off when going
from one to the other).

Timestamping
============

Date and time: The system is posited on a cycle of days, each with a known
beginning and end. This works very nicely with a system that has a regular
downtime (say, 2AM-4AM); it doesn't hurt if a day contains additional hours
from midnight until some particular cut-off, just as long as it's consistent.
The stipulated day-break (and no, I don't mean the coronet) is handled as some
number of hours (possibly zero) after midnight in some time zone (possibly UTC)
and always, for all operations, treats those hours as belonging to the previous
day. Note that touches-off are detected on the basis of their run numbers, NOT
the date of operation; if you touch on prior to the roll-over, then touch off
after the roll-over, it will be correctly detected. However, if you then touch
on again, it will be deemed a new day, and will open a new ticket or check for
longer validity on your period ticket.

Note that currently, the system assumes that time increases monotonically, and
that touches are processed in chronological order. The former can be ensured by
slewing (rather than stepping) the server's clock, such that any date, once
over, will never be re-entered; if the server's clock is ever found to be too
far wrong, it must be corrected during an effective outage. The latter is a
major problem with the bus/tram retry loop - it is theoretically possible to
touch on, then touch off in a dead spot, make all haste to your next service,
touch on again, and then have the retry of your touch off arrive. This would
result in all three touches (and the touch off at the end of your second trip)
to be counted as touches-on. To reduce the chances of this occurring, coverage
at railway stations needs to be excellent; it may also be important to hammer
the retry loop, possibly with no gap exceeding 15 seconds. None of this can
entirely prevent the problem, but it will make it vanishingly unlikely.

NOTE: In time zones using Daylight Saving Time, it is possible to experience
times more than once; in many locations, this occurs between 2AM and 3AM, with
the times from 02:00:00 to 02:59:59.999 occurring twice, but the instant of
03:00:00 occurs only once. Avoid setting the day-break inside this duplicated
period, as it will result in a day being potentially restarted. Using 3AM as
the day-break would work with this scenario, but 2AM would not. Check your DST
rules before selecting a cut-off point.

Identifiers: Vehicles
=====================

ThirdSquare needs to be able to uniquely identify every tram and bus, in order
to correctly recognize a touch-off. Currently, the system is posited on the use
of fixed IP addresses to identify these vehicles; if no 3G/4G provider is able
to guarantee this, an alternative could be devised involving a lookup table,
but this has security implications. Even with that change, though, the system
depends on any given vehicle maintaining a unique and constant IP address for
the duration of one "session", with no passengers remaining on board across a
session break. For instance, a bus might return to the depot, shut down, and
relinquish its IP address, but if it reboots during a run, matters could become
extremely messy if its IP changes.

The IP address is tied to a public key. Consequently, each vehicle must have a
single encryption computer; it may have multiple validators, but they will be
considered to be a single "unit". Notably, if a user touches on at one of the
validators and touches off at another one, they are considered to be the same
vehicle if and only if they use the same IP address and encryption key.

Railway stations do not have a concept of vehicles (the entire rail network is
treated as one vehicle), but must still tie encryption keys to IP addresses.
Whether a station has a single key+IP or multiple does not matter; it would be
perfectly reasonable to operate a two-platform island station off a single IP,
and equally reasonable to operate Spencer Street Station off several separate
nodes, just as long as each node has a dedicated IP address and keypair.

Identifiers: Locations
======================

Whenever a ThirdSquare card is touched to a validator, that validator MUST know
its current location. This location need not necessarily correspond to a single
point on the globe, but MUST carry a single zone map, and ideally, it should be
impractical for anyone to board a vehicle, ride, and then disembark, all within
a single location. The system MAY assume that a second touch in the location of
the latest touch on is a cancellation rather than a short trip. Note that using
the same location ID for multiple routes is acceptable as long as no route ever
exits a location and then reenters it, all while heading toward the same target
location; this could confuse location descriptors. In other words, it's fine to
exit a location, go to the terminus, then start a return journey that goes into
the same location in the opposite direction; but not to loop around and hit the
same place again after leaving it... it may be safer to deem the entire loop as
a single location, although this is NOT RECOMMENDED.

Locations SHOULD be identified in a service-specific way, such that bus, train,
and tram locations in near proximity are still distinguishable. This allows for
zone-map differences based on mode of travel, which may be important.

Regions which cross state boundaries (eg Albury-Wodonga) MUST be managed by one
state or the other for ticketing purposes. The region cannot be divided up such
that a single journey might involve multiple governing states.

Identifiers: Zones
==================

Ticketing zones are broad areas of coverage charged at the same rate. Any given
location may be in one single zone, or may be in the overlap of any number of
zones; a ticket for any of those zones is valid for travel at that location.
The set of all zones valid at a given location is that location's zone map. The
set of all zones for which a period ticket is valid is similar; so long as any
intersection exists between the ticket's zones and the location's zone map, it
is valid. For automated tickets, the system chooses the minimum number of zones
in the manner described above.

Zones must be defined in a totally ordered manner. Identifying them with simple
numbers or alphabetizable strings is sufficient.

Open questions
==============

Point-to-point fare calculation
-------------------------------

Currently, all fares are calculated on the basis of endpoints only. So long as
all routes run relatively short distances, this is not a problem - a bus might
go across one zone boundary, and include overlaps with several others, but no
single trip on any bus would ever cost more than two zones. Train journeys,
however, are often going to be longer, and may require line-based zoning. How
should this be calculated? See above - zones have no concept of geography, so
a vehicle that goes from zone 1|2 to zone 5|9 might have passed through any
other zones in between. One solution might be to maintain a table of zone
overlaps; for instance, the above would demonstrate that zones 1 and 2 overlap,
and likewise zones 5 and 9. In order to determine the actual fare, a complete
chain must be found. Suppose there is, somewhere in the system, a station in
zones 2|4, and another in zones 4|9. This would indicate that the trip would be
possible with constant overlap by progressing 1|2, 2|4, 4|9, 5|9, with the two
ends being the actual touch locations. The system would then presume touches in
all four locations instead of just one, and then bill accordingly; if this were
the only trip done on a ticket, then it would be charged as a three-zone ticket
(covering zones 2|4|9), which is thus sufficient to cover the entire zone set.

Downside: Lots and LOTS of processing in what will be a very common case.

Upside: Approximately perfect result.

Note that it may be possible to cache these. Every pair (N!) of zones would be
assigned a number; X-X is implicitly zero, any pair that has an overlap is one,
and thereafter as per the algo above. Given any pair of zone maps, the cross
product could be examined, and the lowest pair selected. This may turn out to
give no benefit beyond the current plan. (Think Erdős numbers or graph
distance.)

To build the cache:

    zone-pairs = mapping
    For unique zone-map in locations:
        For zone in zone-map:
            If zone not in zone-pairs:
                zone-pairs[zone] = mapping
                zone-pairs[zone][zone] = empty # loopback
            For other-zone in zone-map except zone: # double nested
                zone-pairs[zone][other-zone] = zone-map
                For destination in zone-pairs[other-zone]:
                    path = zone-map + zone-pairs[other-zone][destination]
                    zone-pairs[zone][destination] = path if shorter than existing value
		    Ditto zone-pairs[destination][zone]

This is linear in the number of locations, but need be done only once (until
the locations get changed; could be done once on bootup or signal). The end
result is a mapping from any zone to any other reachable zone, containing the
set of all intermediate locations in the shortest path from one to the other;
this mapping, obviously, contains N² entries, where N is the number of zones in
any geographically-cohesive area. (Completely disparate areas do not interact;
it is assumed that no trip can touch on in one area and touch off in another.)
Lookups into this table are performed in constant time.

To use this cache, take the zone-maps for the two endpoints, and find the pair
(origin zone, destination zone) with the shortest path. If this path is empty
(which includes the trivial case of a common zone), no additional touches need
to be simulated; otherwise, create touches for each of the zone-pairs in the
path. The above example locations would produce the following table (trivial
entries and reverse paths omitted for brevity):

    (1,2) -> 1|2
    (2,4) -> 2|4
    (1,4) -> 1|2, 2|4
    (5,9) -> 5|9
    (4,9) -> 4|9
    (4,5) -> 4|9, 5|9
    (1,9) .......

Oh. Turns out I forgot something in the above algorithm: that a new node, when
discovered, may affect path lengths not involving any of its zones. In fact,
the search can be modeled with zones as vertices and zone-maps representing one
or more edges connecting them, each with weight one... which reduces this to
the good ol' Travelling Salesman Problem. Unless some massive optimization can
be found, this is a fundamentally hard problem. That said, though, a TSP brute
force algorithm can probably handle the dozen or so nodes we'll be using here,
so it might turn out to be "good enough".

Ticket durations and touches-off
--------------------------------

Whenever you touch on, the current time is checked for validity, and if you do
not have an active ticket, one will be created (or a previous one extended) to
cover 'now'. What happens when you touch off explicitly, and what happens when
your ticket is automatically touched off for you?

If explicit touches extend tickets, then automated touches MUST also extend.
Otherwise, failing to touch off will frequently result in a lower fare than
touching off, which violates a fundamental principle of our Association.

If touches extend tickets, there may be extreme weirdnesses across a day-break.
Does your existing ticket get a "loading" for its extra hours? Is a new ticket
opened, and if so, for what zones? Or is there a special case, that touching
off after day-break doesn't extend your ticket? This would be an extremely odd
corner case, and maybe it's rare enough that people shouldn't need to worry
about it, but it's still hard to explain. The Zen of Python advises against
this proposal (lines 8 and 17), and while we're not governed by it, it's still
worth noting.

Also, if touches extend tickets, the deemed time of the automated touch becomes
significant. This may mean that people complain very loudly when their ticket
gets unexpectedly expanded to a daily (roughly doubling their fare), and may
have other unintended consequences; it also worsens the day-break problem, as
any run which spans the boundary will trigger this for failed-touches-off.
Consistency could be achieved by deeming that ALL automated touches occur at
notional end-of-day, which would mean that failing to touch off would always
result in a daily fare; this would likely cause resentment in other areas, and
doesn't improve the situation significantly, and so is not worth doing.

Conversely, if touches do NOT extend tickets, there is an incentive to cheat on
rail journeys. Suppose a commuter lives on one side of the city and works on
the other, in each case either walking to/from the station or using a bicycle.
If he travels to work in the morning and home again in the evening, he ought to
touch four times; conceptually, he should be charged for a daily ticket for all
zones of his journey (cf "Point-to-point" above, but certainly a daily ticket),
as he has travelled for (say) 90 minutes in the AMs and 90 more in the PMs. But
if he consistently fails to touch off, the system will detect only two touches
per day, one at his home station in the morning, and one at his work station in
the afternoon, and will treat the latter as a touch-off. Technically he is fare
evading by failing to touch off, but the reward is a half-price ticket, which
is extremely tempting, and the system is unable to detect this (without some
kind of silly boundary condition, like assuming that no train journey lasts
more than X hours - which would have its own stupid cases).

A messy system in which railway station touches always affect times but others
do not would further complicate matters, and I'm not sure it fixes the problem.

Current inclination: Touches-off should not extend tickets. Fare evasion is
fare evasion, and while it is be nice to build evasion discouragement into the
code, it is not important enough to justify excessive complexity.

Evening ticket duration
-----------------------

Dating back at least as far as Metcard, two-hourly tickets opened after 6PM
have been valid until the end of the day. This is simple enough to do; should
it be done? With round-the-clock services, is 6PM still a significant boundary?
