//ThirdSquare ticketing server - requires Hogan.
mapping(int:function) services=([5000|HOGAN_UDP:decode_packet]);

object server_key; //Decryption/signing key (parsed from the private key file)
mapping(string:object) client_keys=([]); //Encryption/verification keys (parsed from public key file)
Sql.Sql ticketsdb, accountsdb; //Database connections (must be distinct)

//For debugging, enable a console log of incoming packets
#define VERBOSE

//Sign and send a response packet
void send_packet(string data,string ip,int port)
{
	object udp=values(G->socket)[0];
	if (sizeof(data)>256) exit(1,"Data too long!\n"); //We want the resulting packet to have no more than 512 data bytes. Boom! Assert fail.
	string sig = server_key->pkcs_sign(data,Crypto.SHA256); //The signature should always be exactly 256 bytes (2048 bits) long.
	//data = client_keys[ip]->encrypt(data); //Optionally encrypt as well as signing.
	udp->send(ip, port, data + sig);
}

//Receive and verify a packet
void decode_packet(int portref,mapping(string:int|string) data)
{
	#ifdef VERBOSE
	write("Packet from %s : %d, %d bytes\n",data->ip, data->port, sizeof(data->data));
	#endif
	if (sizeof(data->data)<256) return; //Undersized packet, can't have a valid signature
	string body=data->data[..<256], sig=data->data[<255..]; //The last 256 bytes are the signature.
	object decoder = client_keys[data->ip];
	if (!decoder) return; //Unrecognized source address
	if (!decoder->pkcs_verify(body, Crypto.SHA256, sig)) return; //Verification failed - bad signature
	//body = server_key->decrypt(body); //Optionally decrypt as well as verifying signature.
	//The message cryptographically checked out - yay! Pass it on to the trusted function.
	handle_packet(data->ip, data->port, body);
}

void handle_packet(string ip, int port, string body)
{
	#ifdef VERBOSE
	write("Message body: %s\n",body);
	#endif
}

//Parse and load a private key for encryption purposes
object load_private_key(string fn)
{
	sscanf(Stdio.read_file(fn),"%*s-----BEGIN RSA PRIVATE KEY-----%s-----END RSA PRIVATE KEY-----",string key);
	return Standards.PKCS.RSA.parse_private_key(MIME.decode_base64(key));
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

void create()
{
	if (!file_stat("server_key")) Process.create_process(({"ssh-keygen","-q","-N","","-f","server_key"}))->wait();
	server_key = load_private_key("server_key");

	foreach ((Stdio.read_file("client_keys")||"")/"\n", string line) catch //Any errors, just ignore them and skip the line.
	{
		[string sshrsa, string key, string ip] = line/" ";
		if (sshrsa != "ssh-rsa") continue;
		client_keys[ip] = decode_public_key(key);
	};

	//Invoke as "pike hogan thirdsquare --clients" to list valid clients.
	if (G->options->clients) exit(0,"Valid clients:\n%{\t%s\n%}%d clients authenticated.\n",sort(indices(client_keys)),sizeof(client_keys));

	//Beyond proof-of-concept, these database connection strings would of course be tightly secured.
	//Note that it may be possible to use the same database for these, but it is NOT possible to use
	//the same database connection (you can't simply assign accountsdb=ticketsdb), as they MUST be
	//able to establish and commit transactions independently.
	ticketsdb = Sql.Sql("pgsql://tickets:tickets@localhost/thirdsquare");
	accountsdb = Sql.Sql("pgsql://accounts:accounts@localhost/thirdsquare");
}
