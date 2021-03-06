//ThirdSquare ticketing server - requires Hogan.
mapping(int:function) services=([5000|HOGAN_UDP:decode_packet]);

object private_key; //Decryption/signing key (parsed from the private key file)
mapping(string:object) public_keys=([]); //Encryption/verification keys (parsed from public key file)
Sql.Sql ticketsdb, accountsdb; //Database connections (must be distinct)

//For debugging, enable a console log of incoming packets
#define VERBOSE

//Send a pre-signed request or response packet.
void send_packet(string(0..255) data, string ip, int port)
{
	object udp=values(G->socket)[0];
	udp->send(ip, port, data);
}

//Sign a packet, ready to send. Note that the protocol requires bytes, not text. For
//safety and simplicity, I am mandating ASCII for the time being; whether the protocol
//expands to UTF-8 or goes binary can be decided later.
string sign_packet(string(0..127) data, string ip)
{
	if (sizeof(data)>256) exit(1, "Data too long!\n"); //We want the resulting packet to have no more than 512 data bytes. Boom! Assert fail.
	string sig = private_key->pkcs_sign(data, Crypto.SHA256); //The signature should always be exactly 256 bytes (2048 bits) long.
	//data = public_keys[ip]->encrypt(data); //Optionally encrypt as well as signing. Note that this reduces the maximum payload to 245 bytes.
	return data + sig;
}

//Convenience function to sign and send a packet immediately.
void sign_and_send_packet(string(0..127) data, string ip, int port) {send_packet(sign_packet(data, ip), ip, port);}

//Receive and verify a packet
void decode_packet(int portref, mapping(string:int|string) data)
{
	#ifdef VERBOSE
	write("Packet from %s : %d, %d bytes\n",data->ip, data->port, sizeof(data->data));
	#define ERROR(s) {write(s "\n"); return;}
	#else
	#define ERROR(s) return;
	#endif
	if (sizeof(data->data)<256) ERROR("Undersized packet, can't have a valid signature")
	string body=data->data[..<256], sig=data->data[<255..]; //The last 256 bytes are the signature.
	object decoder = public_keys[data->ip];
	if (!decoder) ERROR("Unrecognized source address")
	//body = server_key->decrypt(body); //Optionally decrypt as well as verifying signature.
	if (!decoder->pkcs_verify(body, Crypto.SHA256, sig)) ERROR("Verification failed - bad signature")
	//The message cryptographically checked out - yay! Pass it on to the trusted function.
	handle_packet(body, data->ip, data->port);
}

void handle_packet(string body, string ip, int port)
{
	#ifdef VERBOSE
	write("Message body: %s\n",body);
	#endif
	//Simple connectivity test: Send "HELO", get back "OK". Great way to test key sharing.
	if (body == "HELO") sign_and_send_packet("OK", ip, port);

	//Note that all timestamping is on the basis of processing time, not the time the
	//packet was sent. This MAY occasionally be significant, but attempting to embed
	//timestamps in the packets raises as many issues as it solves (eg clock sync over
	//the whole system), so we accept that delayed packet delivery can cause problems.
	//mapping now = localtime(time());
	mapping now_offset = localtime(time()-4*3600); //For the purposes of date calculations, we reset at 4AM.
	string today = sprintf("%d-%02d-%02d", now_offset->year+1900, now_offset->mon+1, now_offset->mday);
	//Parse a touch request. Note that currently the format is quite strict; it's designed to be readable and extensible,
	//though, and can ultimately be parsed as a series of name=value pairs.
	if (sscanf(body, "TOUCH id=%d card=%d loc=%d targ=%d", int id, int card, int loc, int targ) && id && card && loc) //Note that targ is allowed to be zero
	{
		ticketsdb->query("begin"); accountsdb->query("begin");
		#define RETURN(x) {accountsdb->query("commit"); ticketsdb->query("commit"); sign_and_send_packet(x, ip, port); return;}
		array ret = ticketsdb->typed_query("select touch_target, touch_date, touch_vehicle, touch_id from active_cards where id=%d", card);
		if (!sizeof(ret))
		{
			//The card has never been used with this system yet. Ensure that it exists in the master,
			//then create it here. Note that we don't care about the potential race between the two
			//databases; tickets will be created but not usually destroyed.
			if (!sizeof(accountsdb->typed_query("select id from cards where id=%d", card))) RETURN(sprintf("REJECT id=%d card=%d reason=BADCARD", id, card))
			ticketsdb->query("insert into active_cards (id) values (%d)", card);
			ret = ({ ([]) });
		}
		mapping info = ret[0];
		int prevcharge=0, charge=0;
		//If all three signature values match, then this is a repeated touch, so skip any
		//database recording and just jump straight to returning a response. We know that
		//the response has to be affirmative, or the previous touch wouldn't have been in
		//the database. TODO: Also figure out if money got charged.
		if (info->touch_date!=today || info->touch_vehicle!=ip || info->touch_id!=id)
		{
			//The signatures DON'T match, so this is a real touch.
			if (info->touch_target)
			{
				//The card was previously in the touched-on state. There are three
				//possibilities: Either this is a re-touch at the same location on
				//the same vehicle (which MAY be treated as a cancellation), or it
				//is a touch-off (same vehicle, same date, different location), or
				//it is an unrelated touch. If it's unrelated, we simulate a touch
				//off at the previous target, and then process this as a touch on.
				//Otherwise, we process this as a touch off.
				if (info->touch_date==today && info->touch_vehicle==ip //Same date and vehicle, else it's not possibly a touch off
					&& (info->touch_target==targ || info->touch_target==loc)) //Either the same target, or currently located at the target (ie we've just hit a terminus)
				{
					//It's a touch off. Flag it so we don't do the touch on.
					//May set 'charge' to a number of cents.
				}
				else
				{
					//It's a new touch; we presume a touch-off at the previous target.
					//May set 'prevcharge' to a number of cents.
				}
			}
			//Now touch the card on at the new location, unless this was flagged as a touch-off.
			//This may set 'charge' to a number of cents. If so, attempt to charge the account
			//atomically; on failure, RETURN(sprintf("REJECT id=%d card=%d reason=NOMONEY prevcharge=%d", id, card, prevcharge))
			//Note that it's possible to fail and still have a prevcharge.
		}
		//Finally, figure out what the current balance is, and return that.
		RETURN(sprintf("ACCEPT id=%d card=%d prevcharge=%d charge=%d", id, card, prevcharge, charge))
	}
}

//Parse and load a private key for encryption purposes
object load_private_key(string fn)
{
	return Standards.PKCS.RSA.parse_private_key(Standards.PEM.simple_decode(Stdio.read_file(fn)));
}

//Parse and load a public key for verification purposes
object load_public_key(string fn) {return decode_public_key((Stdio.read_file(fn)/" ")[1]);}
object decode_public_key(string key)
{
	//Decoding technique provided by Henrik Grubbström (grubba) - thanks!
	Stdio.Buffer buf = Stdio.Buffer(MIME.decode_base64(key));
	string tag = buf->read_hstring(4);
	if (tag != "ssh-rsa") error("Incorrect signature on public key (%O)", tag);
	int pub = buf->read_hint(4);
	int modulo = buf->read_hint(4);
	return Crypto.RSA()->set_public_key(modulo, pub);
}

//Load a private key and a fileful of public keys
void load_keys(string priv, string pub)
{
	if (!file_stat(priv)) Process.create_process(({"ssh-keygen","-q","-N","","-f",priv}))->wait();
	private_key = load_private_key(priv);

	foreach ((Stdio.read_file(pub)||"")/"\n", string line) catch //Any errors, just ignore them and skip the line.
	{
		[string sshrsa, string key, string ip] = line/" ";
		if (sshrsa != "ssh-rsa") continue;
		public_keys[ip] = decode_public_key(key);
	};
}

/* From the README:
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
       that depend on the order of the checks done. As a general rule, working
       from the least frequently used zones will give optimal results; but in
       case edge cases exist, ensure that zones are checked in some consistent
       order (eg lexically by zone identifier) even when multiple have the same
       frequency. Frequency-based ordering is unnecessary if the full recursive
       search is performed, but this should be cheaper (I think!).
    4. The number of zones in the union at the end is the ticket's zone count.

This function takes an array representing today's touches. Each is either a set or
a blank-delimited string of zone identifiers. It will return an array of zones for
which the traveller should be charged. Note that the exact *set* of zones should
not be trusted (though it's useful debugging information); only the *count* is of
any use long-term.
*/
array(string) zoneset(array(multiset|string) touches)
{
	if (!sizeof(touches)) return ({ }); //No touches? No zones.
	if (stringp(touches[0])) touches=(array(multiset))(touches[*]/" "); //An array of sets is more useful to us.
	mapping(string:int) zones=([]);
	//1. Take the union of all zones used at all, and count up usages.
	foreach (touches,multiset zonemap) foreach (zonemap;string z;) ++zones[z];
	//2. Try removing zones and see if it fails. Start with the least-frequently-used.
	array all_zones=indices(zones),counts=values(zones);
	//We could just use "sort(v,i);" and then iterate over i, but that would
	//leave elements unsorted in the case of count collisions, which will be
	//common. The consequence of such a collision is unlikely to be significant,
	//but at the cost of one extra sort operation, we ensure that they're sorted
	//lexically by zone identifier within that. (Pike's sort() is stable.)
	sort(all_zones,counts); sort(counts,all_zones);
	multiset(string) minimum=(multiset)all_zones;
	foreach (all_zones,string zone)
	{
		minimum[zone]=0;
		foreach (touches,multiset t) if (!sizeof(t&minimum))
		{
			//Problem: If we remove this one, we have no zone that
			//covers this touch. So this zone needs to be reinstated.
			minimum[zone]=1;
			break;
		}
	}
	return (array)minimum;
}

void create()
{
	load_keys("server_key", "client_keys");
	//Invoke as "pike hogan thirdsquare --clients" to list valid clients.
	if (G->options->clients) exit(0,"Valid clients:\n%{\t%s\n%}%d clients authenticated.\n",sort(indices(public_keys)),sizeof(public_keys));

	if (G->options->distances)
	{
		//Test: Calculate point-to-point distances
		//Ultimately this will be done as a regular thing, and this dump
		//will become a simple check for verification purposes.

		//zones[x][y] exists if there is adjacency between x and y.
		mapping(string:multiset(string)) zones=([]);

		//routes[x][y] is the fewest-steps link from zone x to zone y.
		//If x==y || zones[x][y], routes[x][y]==({}); otherwise, it is an
		//array of zone identifiers through which one must go. Note that
		//the exact chain is unreliable; there may be multiple chains that
		//can get you from x to y, but there will be none shorter than
		//this one.
		mapping(string:mapping(string:array(string))) routes=([]);

		//Ultimately this will come from the database eg
		//"select distinct zone_map from locations"
		foreach (Stdio.read_file("stations")/"\n",string zonemap) if (zonemap!="")
		{
			array parts = zonemap/" ";
			foreach (parts,string x) foreach (parts,string y) if (x!=y)
			{
				if (!zones[x]) zones[x]=(<>);
				zones[x][y]=1;
			}
		}

		//Okay. Now to build up the full map.
		//For each initial zone, add destinations for all its links.
		//For each destination, add destinations for all its links, if not already present.
		foreach (zones;string initial;multiset(string) links)
		{
			mapping(string:array(string)) dest = routes[initial] = ([initial: ({initial})]);
			array(string) wavefront = ({initial});
			while (sizeof(wavefront))
			{
				array(string) newfront = ({ });
				foreach (wavefront, string zone)
				{
					foreach (zones[zone];string loc;) if (!dest[loc])
					{
						dest[loc] = dest[zone] + ({loc});
						newfront += ({loc});
					}
				}
				wavefront=newfront;
			}
		}
		write("Zone adjacencies: %O\n",zones);
		write("Zone paths: %O\n",routes);
		foreach (routes;string initial;mapping destinations)
		{
			foreach (destinations;string dest;array(string) path) if (sizeof(path) && dest>initial)
			{
				array forward=zoneset(({initial,dest})+path);
				array reverse=zoneset(({initial,dest})+routes[dest][initial]);
				if (!equal(forward,reverse))
					write("%s:%s = %s = %d (%s)\n%s:%s = %s = %d (%s)\n",
						initial,dest,path*" ",sizeof(forward),forward*", ",
						dest,initial,routes[dest][initial]*" ",sizeof(reverse),reverse*", ");
			}
		}
		exit(0);
	}

	if (G->options->zoneset)
	{
		foreach (({
			({"1 2","2 3","3 4","4 5"}),
			({"1 2","2 3 4","1 2","1 3"}),
			({"1 2","1 3","1 4","1 5","1 6"}),
			({"1 9","2 9","3 9","4 9","5 9"}),
			({"5","6","2 5","2 6"}),
		}),array(string) touches)
		{
			array zones=zoneset(touches);
			write("Touch in %s\nZones: %d (%s)\n",touches*" | ",sizeof(zones),zones*", ");
		}
		exit(0);
	}

	//Beyond proof-of-concept, these database connection strings would of course be tightly secured.
	//Note that it may be possible to use the same database for these, but it is NOT possible to use
	//the same database connection (you can't simply assign accountsdb=ticketsdb), as they MUST be
	//able to establish and commit transactions independently.
	ticketsdb = Sql.Sql("pgsql://tickets:tickets@localhost/thirdsquare");
	accountsdb = Sql.Sql("pgsql://accounts:accounts@localhost/thirdsquare");
}
