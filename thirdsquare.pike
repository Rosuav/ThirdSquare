//ThirdSquare ticketing server - requires Hogan.
mapping(int:function) services=([5000|HOGAN_UDP:decode_packet]);

object private_key; //Decryption/signing key (parsed from the private key file)
mapping(string:object) public_keys=([]); //Encryption/verification keys (parsed from public key file)
Sql.Sql ticketsdb, accountsdb; //Database connections (must be distinct)

//For debugging, enable a console log of incoming packets
#define VERBOSE

//Sign and send a response packet. Note that the protocol requires bytes, not text. For
//safety and simplicity, I am mandating ASCII for the time being; whether the protocol
//expands to UTF-8 or goes binary can be decided later.
void send_packet(string(0..127) data, string ip, int port)
{
	object udp=values(G->socket)[0];
	if (sizeof(data)>256) exit(1, "Data too long!\n"); //We want the resulting packet to have no more than 512 data bytes. Boom! Assert fail.
	string sig = private_key->pkcs_sign(data, Crypto.SHA256); //The signature should always be exactly 256 bytes (2048 bits) long.
	//data = public_keys[ip]->encrypt(data); //Optionally encrypt as well as signing. Note that this reduces the maximum payload to 245 bytes.
	udp->send(ip, port, data + sig);
}

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
	if (body == "HELO") send_packet("OK", ip, port);
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
	key=MIME.decode_base64(key);
	//I have no idea how this rewrapping works, but it appears to. There's some
	//signature data at the beginning of the MIME-encoded file, but we need some
	//different signature data for parse_public_key().
	return Standards.PKCS.RSA.parse_public_key("0\202\1\n\2\202"+key[20..]+"\2\3\1\0\1");
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

void create()
{
	load_keys("server_key", "client_keys");
	//Invoke as "pike hogan thirdsquare --clients" to list valid clients.
	if (G->options->clients) exit(0,"Valid clients:\n%{\t%s\n%}%d clients authenticated.\n",sort(indices(public_keys)),sizeof(public_keys));

	//Beyond proof-of-concept, these database connection strings would of course be tightly secured.
	//Note that it may be possible to use the same database for these, but it is NOT possible to use
	//the same database connection (you can't simply assign accountsdb=ticketsdb), as they MUST be
	//able to establish and commit transactions independently.
	ticketsdb = Sql.Sql("pgsql://tickets:tickets@localhost/thirdsquare");
	accountsdb = Sql.Sql("pgsql://accounts:accounts@localhost/thirdsquare");
}
